#include "ddc.h"
#include "ddcproto.h"

#include <QMetaObject>
#include <QPointer>

#include <algorithm>

#include <cerrno>
#include <chrono>
#include <cmath>
#include <fcntl.h>
#include <linux/i2c-dev.h>
#include <sys/ioctl.h>
#include <unistd.h>

namespace {
constexpr uint8_t kBrightness = 0x10;

long long nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch()).count();
}
void sleepMs(int ms) { std::this_thread::sleep_for(std::chrono::milliseconds(ms)); }

// a monitor on /dev/i2c-N, at the DDC/CI address 0x37
class I2cTransport : public DdcTransport {
public:
    explicit I2cTransport(int fd) : m_fd(fd) {}
    ~I2cTransport() override { ::close(m_fd); }
    bool write(const uint8_t *data, size_t len) override { return ::write(m_fd, data, len) == ssize_t(len); }
    long read(uint8_t *buf, size_t len) override { return long(::read(m_fd, buf, len)); }
    static std::unique_ptr<DdcTransport> open(int bus) {
        const std::string path = "/dev/i2c-" + std::to_string(bus);
        const int fd = ::open(path.c_str(), O_RDWR | O_CLOEXEC);
        if (fd < 0) return nullptr;
        // a kernel driver may hold the address (ddcutil forces it then too)
        if (::ioctl(fd, I2C_SLAVE, 0x37) < 0 && !(errno == EBUSY && ::ioctl(fd, I2C_SLAVE_FORCE, 0x37) == 0)) {
            ::close(fd);
            return nullptr;
        }
        return std::make_unique<I2cTransport>(fd);
    }
private:
    int m_fd;
};

Ddc::Opener &opener() {
    static Ddc::Opener o = [](int bus) { return I2cTransport::open(bus); };
    return o;
}
}

void Ddc::setOpener(Opener o) { opener() = std::move(o); }

Ddc::Ddc(QObject *parent) : QObject(parent) {
    m_thread = std::thread([this] { run(); });
}

Ddc::~Ddc() {
    { std::lock_guard lk(m_mutex); m_stop = true; }
    m_wake.notify_all();
    if (m_thread.joinable()) m_thread.join();
}

void Ddc::get(int bus) {
    if (bus < 0) return;
    { std::lock_guard lk(m_mutex); m_gets.insert(bus); }
    m_wake.notify_all();
}

void Ddc::set(int bus, int percent) {
    if (bus < 0) return;
    { std::lock_guard lk(m_mutex); m_sets[bus] = std::clamp(percent, 0, 100); }   // replaces an unsent one
    m_wake.notify_all();
}

// the protocol's pause since the last command on this bus
void Ddc::pace(int bus, int ms) {
    auto it = m_lastAt.find(bus);
    if (it == m_lastAt.end()) return;
    const long long wait = it->second + ms - nowMs();
    if (wait > 0) sleepMs(int(wait));
}

DdcTransport *Ddc::busOf(int bus) {
    if (m_dead.count(bus)) return nullptr;
    auto it = m_buses.find(bus);
    if (it != m_buses.end()) return it->second.get();
    auto t = opener()(bus);
    if (!t) { m_dead.insert(bus); return nullptr; }
    return (m_buses[bus] = std::move(t)).get();
}

bool Ddc::getNow(int bus, int *percent) {
    DdcTransport *t = busOf(bus);
    if (!t) return false;
    const auto req = ddc::getRequest(kBrightness);
    for (int attempt = 0; attempt < 4; ++attempt) {
        pace(bus, 50);
        const bool wrote = t->write(req.data(), req.size());
        m_lastAt[bus] = nowMs();
        if (!wrote) continue;
        sleepMs(40);                                          // the reply isn't ready before this
        uint8_t buf[16] = {};
        const long n = t->read(buf, 12);                      // 11, or 12 with a repeated address
        m_lastAt[bus] = nowMs();
        if (n <= 0) continue;
        int cur = 0, max = 0;
        switch (ddc::parseGet(buf, size_t(n), kBrightness, &cur, &max)) {
        case ddc::Reply::Ok:
            if (max <= 0) return false;
            m_max[bus] = max;
            *percent = int(std::lround(100.0 * cur / max));
            return true;
        case ddc::Reply::Unsupported:
            return false;
        case ddc::Reply::Busy:
        case ddc::Reply::Bad:
            continue;                                         // ask again
        }
    }
    return false;
}

bool Ddc::setNow(int bus, int percent) {
    // the monitor's own scale: most are 0-100, some aren't
    if (!m_max.count(bus)) { int p; if (!getNow(bus, &p)) return false; }
    DdcTransport *t = busOf(bus);
    if (!t) return false;
    const int value = int(std::lround(percent * m_max[bus] / 100.0));
    const auto req = ddc::setRequest(kBrightness, value);
    for (int attempt = 0; attempt < 2; ++attempt) {
        pace(bus, 50);
        const bool ok = t->write(req.data(), req.size());
        m_lastAt[bus] = nowMs();
        if (ok) return true;
    }
    return false;
}

void Ddc::run() {
    QPointer<Ddc> self(this);
    for (;;) {
        int bus = -1, percent = 0;
        bool isSet = false;
        {
            std::unique_lock lk(m_mutex);
            m_wake.wait(lk, [this] { return m_stop || !m_gets.empty() || !m_sets.empty(); });
            if (m_stop) return;
            // settings first (what you're dragging), then reads
            if (!m_sets.empty()) {
                auto it = m_sets.begin();
                bus = it->first; percent = it->second; isSet = true;
                m_sets.erase(it);
            } else {
                bus = *m_gets.begin();
                m_gets.erase(m_gets.begin());
            }
        }
        if (isSet) {
            if (!setNow(bus, percent))
                QMetaObject::invokeMethod(this, [self, bus] { if (self) emit self->failed(bus); }, Qt::QueuedConnection);
        } else {
            int p = 0;
            if (getNow(bus, &p))
                QMetaObject::invokeMethod(this, [self, bus, p] { if (self) emit self->read(bus, p); }, Qt::QueuedConnection);
            else
                QMetaObject::invokeMethod(this, [self, bus] { if (self) emit self->failed(bus); }, Qt::QueuedConnection);
        }
    }
}
