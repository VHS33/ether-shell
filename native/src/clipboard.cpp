#include "clipboard.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QImageReader>
#include <QBuffer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QPointer>
#include <QProcess>
#include <QStandardPaths>
#include <QTimer>

#include <algorithm>
#include <cerrno>
#include <csignal>
#include <deque>
#include <functional>
#include <fcntl.h>
#include <map>
#include <mutex>
#include <poll.h>
#include <pthread.h>
#include <string>
#include <sys/eventfd.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#ifdef ETHER_HAVE_WAYLAND
#include <wayland-client.h>
#include "wlr-data-control-unstable-v1-client-protocol.h"
#endif

namespace {
constexpr size_t kTextLimit = 5u << 20;        // 5 MB of text
constexpr size_t kImageLimit = 40u << 20;      // 40 MB of picture
const char *kTextTypes[] = { "text/plain;charset=utf-8", "text/plain;charset=UTF-8", "text/plain",
                             "UTF8_STRING", "TEXT", "STRING", nullptr };
const char *kImageTypes[] = { "image/png", "image/jpeg", "image/webp", "image/gif", "image/bmp", nullptr };

QString extOfMime(const QString &m) {
    if (m == "image/jpeg") return "jpg";
    if (m.startsWith("image/")) return m.mid(6);
    return "txt";
}
QString mimeOfExt(const QString &e) { return e == "jpg" ? "image/jpeg" : "image/" + e; }
}

// ===========================================================================
//   The compositor side, on its own thread
// ===========================================================================
class ClipWorker {
public:
    explicit ClipWorker(ClipboardHistory *owner) : m_owner(owner) {
        m_wake = ::eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    }
    ~ClipWorker() { if (m_wake >= 0) ::close(m_wake); }

    // from the main thread
    void stop() { { std::lock_guard lk(m_mutex); m_stopping = true; } wake(); }
    void setSelection(QByteArray data, QStringList mimes) {
        { std::lock_guard lk(m_mutex); m_cmds.push_back({ std::make_shared<QByteArray>(std::move(data)), mimes }); }
        wake();
    }
    void run();

#ifdef ETHER_HAVE_WAYLAND
    // ---- protocol callbacks (the worker thread) ----
    struct Offer { zwlr_data_control_offer_v1 *obj; std::vector<std::string> mimes; };
    std::map<zwlr_data_control_offer_v1 *, Offer> offers;
    struct Source { std::shared_ptr<QByteArray> data; };
    std::map<zwlr_data_control_source_v1 *, Source> sources;
    wl_seat *seat = nullptr;
    zwlr_data_control_manager_v1 *manager = nullptr;
    uint32_t managerVersion = 0;
    int ownPending = 0;                // selection events that are our own copy
    bool firstSelection = true;        // the clipboard as it was when we connected
    void onSelection(zwlr_data_control_offer_v1 *offer);
    void startRead(zwlr_data_control_offer_v1 *offer, const std::string &mime, size_t limit);
    void onSend(zwlr_data_control_source_v1 *src, const char *mime, int fd);
#endif

private:
    void wake() { uint64_t one = 1; if (m_wake >= 0) (void)!::write(m_wake, &one, sizeof one); }
    void post(std::function<void(ClipboardHistory *)> f) {
        QPointer<ClipboardHistory> o(m_owner);
        QMetaObject::invokeMethod(m_owner, [o, f] { if (o) f(o.data()); }, Qt::QueuedConnection);
    }

    ClipboardHistory *m_owner;
    int m_wake = -1;
    std::mutex m_mutex;
    bool m_stopping = false;
    struct Cmd { std::shared_ptr<QByteArray> data; QStringList mimes; };
    std::deque<Cmd> m_cmds;
    struct Read { int fd; QByteArray buf; QString mime; size_t limit; qint64 started; bool over = false; };
    std::vector<Read> m_reads;
    struct Write { int fd; std::shared_ptr<QByteArray> data; qsizetype pos; };
    std::vector<Write> m_writes;
    friend class ClipboardHistory;
#ifdef ETHER_HAVE_WAYLAND
public:
    void queueRead(Read r) { m_reads.push_back(std::move(r)); }
    void queueWrite(Write w) { m_writes.push_back(std::move(w)); }
    void postData(QByteArray d, QString m) { post([d, m](ClipboardHistory *o) { o->gotData(d, m); }); }
    void postCleared() { post([](ClipboardHistory *o) { o->gotCleared(); }); }
#endif
};

#ifdef ETHER_HAVE_WAYLAND
namespace {
// ---- offers: collect the formats each one has ----
void offerMime(void *data, zwlr_data_control_offer_v1 *offer, const char *mime) {
    auto *w = static_cast<ClipWorker *>(data);
    auto it = w->offers.find(offer);
    if (it != w->offers.end()) it->second.mimes.emplace_back(mime);
}
const zwlr_data_control_offer_v1_listener kOfferListener = { offerMime };

// ---- the device: new offers, and what the clipboard now holds ----
void deviceDataOffer(void *data, zwlr_data_control_device_v1 *, zwlr_data_control_offer_v1 *offer) {
    auto *w = static_cast<ClipWorker *>(data);
    w->offers[offer] = { offer, {} };
    zwlr_data_control_offer_v1_add_listener(offer, &kOfferListener, w);
}
void deviceSelection(void *data, zwlr_data_control_device_v1 *, zwlr_data_control_offer_v1 *offer) {
    static_cast<ClipWorker *>(data)->onSelection(offer);
}
void deviceFinished(void *, zwlr_data_control_device_v1 *) {}
void devicePrimary(void *data, zwlr_data_control_device_v1 *, zwlr_data_control_offer_v1 *offer) {
    // the middle-click selection: not kept
    auto *w = static_cast<ClipWorker *>(data);
    if (!offer) return;
    w->offers.erase(offer);
    zwlr_data_control_offer_v1_destroy(offer);
}
const zwlr_data_control_device_v1_listener kDeviceListener = { deviceDataOffer, deviceSelection, deviceFinished, devicePrimary };

// ---- our own copies: hand the data over when an app pastes ----
void sourceSend(void *data, zwlr_data_control_source_v1 *src, const char *mime, int32_t fd) {
    static_cast<ClipWorker *>(data)->onSend(src, mime, fd);
}
void sourceCancelled(void *data, zwlr_data_control_source_v1 *src) {
    auto *w = static_cast<ClipWorker *>(data);
    w->sources.erase(src);
    zwlr_data_control_source_v1_destroy(src);
}
const zwlr_data_control_source_v1_listener kSourceListener = { sourceSend, sourceCancelled };

// ---- the registry: the seat and the data-control manager ----
void registryGlobal(void *data, wl_registry *reg, uint32_t name, const char *iface, uint32_t version) {
    auto *w = static_cast<ClipWorker *>(data);
    if (!std::strcmp(iface, wl_seat_interface.name) && !w->seat)
        w->seat = static_cast<wl_seat *>(wl_registry_bind(reg, name, &wl_seat_interface, 1));
    else if (!std::strcmp(iface, zwlr_data_control_manager_v1_interface.name)) {
        w->managerVersion = std::min<uint32_t>(version, 2);
        w->manager = static_cast<zwlr_data_control_manager_v1 *>(
            wl_registry_bind(reg, name, &zwlr_data_control_manager_v1_interface, w->managerVersion));
    }
}
void registryRemove(void *, wl_registry *, uint32_t) {}
const wl_registry_listener kRegistryListener = { registryGlobal, registryRemove };

bool hasMime(const std::vector<std::string> &m, const char *want) { return std::find(m.begin(), m.end(), want) != m.end(); }
}

void ClipWorker::onSelection(zwlr_data_control_offer_v1 *offer) {
    const bool first = firstSelection;
    firstSelection = false;
    // empty: the app that owned it went away (but an empty clipboard when we
    // connect, at login, is just empty: nothing to put back)
    if (!offer) { if (!first) postCleared(); return; }
    auto it = offers.find(offer);
    std::vector<std::string> mimes = it != offers.end() ? it->second.mimes : std::vector<std::string>{};
    offers.erase(offer);
    auto done = [&] { zwlr_data_control_offer_v1_destroy(offer); };
    if (ownPending > 0) { ownPending--; done(); return; }        // our own copy coming back
    // a password manager's copy: never stored
    if (hasMime(mimes, "x-kde-passwordManagerHint")) { done(); return; }
    for (int i = 0; kTextTypes[i]; ++i)
        if (hasMime(mimes, kTextTypes[i])) { startRead(offer, kTextTypes[i], kTextLimit); done(); return; }
    for (int i = 0; kImageTypes[i]; ++i)
        if (hasMime(mimes, kImageTypes[i])) { startRead(offer, kImageTypes[i], kImageLimit); done(); return; }
    done();                                                      // nothing we keep (files, rich formats only)
}

void ClipWorker::startRead(zwlr_data_control_offer_v1 *offer, const std::string &mime, size_t limit) {
    int fds[2];
    if (::pipe2(fds, O_CLOEXEC | O_NONBLOCK) < 0) return;
    zwlr_data_control_offer_v1_receive(offer, mime.c_str(), fds[1]);
    ::close(fds[1]);
    const bool isText = mime.rfind("image/", 0) != 0;
    queueRead({ fds[0], {}, isText ? QStringLiteral("text/plain") : QString::fromStdString(mime), limit,
                QDateTime::currentMSecsSinceEpoch() });
}

void ClipWorker::onSend(zwlr_data_control_source_v1 *src, const char *, int fd) {
    auto it = sources.find(src);
    if (it == sources.end()) { ::close(fd); return; }
    ::fcntl(fd, F_SETFL, ::fcntl(fd, F_GETFL) | O_NONBLOCK);
    queueWrite({ fd, it->second.data, 0 });
}
#endif

void ClipWorker::run() {
#ifdef ETHER_HAVE_WAYLAND
    // a paste target that goes away mid-write mustn't take the shell with it
    sigset_t set; sigemptyset(&set); sigaddset(&set, SIGPIPE);
    pthread_sigmask(SIG_BLOCK, &set, nullptr);

    wl_display *display = wl_display_connect(nullptr);
    if (!display) return;
    wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &kRegistryListener, this);
    wl_display_roundtrip(display);
    if (!seat || !manager) {
        wl_display_disconnect(display);
        return;                                  // no protocol: the shell keeps cliphist
    }
    auto *device = zwlr_data_control_manager_v1_get_data_device(manager, seat);
    zwlr_data_control_device_v1_add_listener(device, &kDeviceListener, this);
    wl_display_roundtrip(display);
    post([](ClipboardHistory *o) { o->setAvailable(true); });

    bool lost = false;
    while (!lost) {
        // our copies, asked for by the main thread
        {
            std::lock_guard lk(m_mutex);
            if (m_stopping) break;
            while (!m_cmds.empty()) {
                Cmd c = std::move(m_cmds.front());
                m_cmds.pop_front();
                auto *src = zwlr_data_control_manager_v1_create_data_source(manager);
                zwlr_data_control_source_v1_add_listener(src, &kSourceListener, this);
                for (const QString &m : c.mimes) zwlr_data_control_source_v1_offer(src, m.toUtf8().constData());
                sources[src] = { c.data };
                ownPending++;
                zwlr_data_control_device_v1_set_selection(device, src);
            }
        }
        while (wl_display_prepare_read(display) != 0)
            if (wl_display_dispatch_pending(display) < 0) { lost = true; break; }
        if (lost) break;
        wl_display_flush(display);

        std::vector<pollfd> pfds;
        pfds.push_back({ wl_display_get_fd(display), POLLIN, 0 });
        pfds.push_back({ m_wake, POLLIN, 0 });
        for (auto &r : m_reads) pfds.push_back({ r.fd, POLLIN, 0 });
        for (auto &w : m_writes) pfds.push_back({ w.fd, POLLOUT, 0 });
        const int n = ::poll(pfds.data(), pfds.size(), 1000);
        if (n > 0 && (pfds[0].revents & POLLIN)) {
            if (wl_display_read_events(display) < 0) { lost = true; break; }
        } else {
            wl_display_cancel_read(display);
        }
        if (pfds[0].revents & (POLLERR | POLLHUP)) { lost = true; break; }
        if (wl_display_dispatch_pending(display) < 0) { lost = true; break; }
        if (pfds[1].revents & POLLIN) { uint64_t v; (void)!::read(m_wake, &v, sizeof v); }

        // what poll said about each transfer, by its file descriptor (a
        // transfer started while dispatching wasn't polled yet: it waits)
        std::map<int, short> ready;
        for (size_t k = 2; k < pfds.size(); ++k) ready[pfds[k].fd] = pfds[k].revents;
        auto revents = [&](int fd) { auto it = ready.find(fd); return it == ready.end() ? short(0) : it->second; };

        // incoming data: read what's there; at the end, hand it over
        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        for (size_t i = 0; i < m_reads.size();) {
            Read &r = m_reads[i];
            bool finished = false;
            if (revents(r.fd) & (POLLIN | POLLHUP | POLLERR)) {
                char buf[65536];
                for (;;) {
                    const ssize_t got = ::read(r.fd, buf, sizeof buf);
                    if (got > 0) {
                        if (size_t(r.buf.size()) + size_t(got) > r.limit) { r.over = true; r.buf.clear(); }
                        else if (!r.over) r.buf.append(buf, got);
                        continue;
                    }
                    if (got == 0 || (errno != EAGAIN && errno != EINTR)) finished = true;
                    break;
                }
            }
            if (!finished && now - r.started > 5000) { finished = true; r.over = true; }   // an app that never answers
            if (finished) {
                ::close(r.fd);
                if (!r.over && !r.buf.isEmpty()) postData(r.buf, r.mime);
                m_reads.erase(m_reads.begin() + long(i));
            } else ++i;
        }
        // outgoing data: an app pasting one of our copies
        for (size_t i = 0; i < m_writes.size();) {
            Write &w = m_writes[i];
            bool finished = false;
            if (revents(w.fd) & (POLLOUT | POLLHUP | POLLERR)) {
                while (w.pos < w.data->size()) {
                    const ssize_t put = ::write(w.fd, w.data->constData() + w.pos, size_t(w.data->size() - w.pos));
                    if (put > 0) { w.pos += put; continue; }
                    if (put < 0 && (errno == EAGAIN || errno == EINTR)) break;
                    finished = true;                     // the app closed its end
                    break;
                }
                if (w.pos >= w.data->size()) finished = true;
            }
            if (finished) { ::close(w.fd); m_writes.erase(m_writes.begin() + long(i)); }
            else ++i;
        }
    }
    for (auto &r : m_reads) ::close(r.fd);
    for (auto &w : m_writes) ::close(w.fd);
    m_reads.clear(); m_writes.clear();
    for (auto &s : sources) zwlr_data_control_source_v1_destroy(s.first);
    for (auto &o : offers) zwlr_data_control_offer_v1_destroy(o.first);
    zwlr_data_control_device_v1_destroy(device);
    zwlr_data_control_manager_v1_destroy(manager);
    wl_seat_destroy(seat);
    wl_registry_destroy(registry);
    wl_display_disconnect(display);
    if (lost) post([](ClipboardHistory *o) { o->setAvailable(false); });
#endif
}

// ===========================================================================
//   The history, on the main thread
// ===========================================================================
ClipboardHistory::ClipboardHistory(QObject *parent) : QObject(parent) {
    m_dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/ether-shell/clipboard";
    QDir().mkpath(m_dir);
    ::chmod(QFile::encodeName(m_dir).constData(), 0700);            // yours only
    load();
    publish();
#ifdef ETHER_HAVE_WAYLAND
    if (!qEnvironmentVariableIsEmpty("WAYLAND_DISPLAY")) {
        m_worker = new ClipWorker(this);
        m_thread = std::thread([w = m_worker] { w->run(); });
    }
#endif
    // the first time: bring cliphist's history over
    if (!QFile::exists(m_dir + "/index.json") && !QStandardPaths::findExecutable("cliphist").isEmpty())
        QTimer::singleShot(0, this, &ClipboardHistory::importCliphist);
}

ClipboardHistory::~ClipboardHistory() {
    if (m_worker) {
        m_worker->stop();
        if (m_thread.joinable()) m_thread.join();
        delete m_worker;
    }
}

void ClipboardHistory::setAvailable(bool on) {
    if (on == m_available) return;
    m_available = on;
    emit availableChanged();
}
void ClipboardHistory::setLimit(int n) {
    n = std::clamp(n, 10, 5000);
    if (n == m_limit) return;
    m_limit = n; emit limitChanged();
    trim(); save(); publish();
}
void ClipboardHistory::setPersist(bool on) { if (on != m_persist) { m_persist = on; emit persistChanged(); } }

QString ClipboardHistory::fileOf(const Entry &e) const { return m_dir + "/" + e.id + "." + e.ext; }

// one line, spaces tidied, like cliphist's list
QString ClipboardHistory::previewOfText(const QByteArray &text) {
    QString s = QString::fromUtf8(text.left(4000)).simplified();
    if (s.size() > 200) s = s.left(200);
    return s;
}

void ClipboardHistory::gotData(const QByteArray &data, const QString &mime) {
    const QString hash = QString::fromLatin1(QCryptographicHash::hash(data, QCryptographicHash::Sha1).toHex());
    // already there: to the top
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].hash != hash) continue;
        Entry e = m_entries.takeAt(i);
        e.time = QDateTime::currentSecsSinceEpoch();
        m_entries.prepend(e);
        save(); publish();
        return;
    }
    Entry e;
    e.id = QString::number(m_nextId++);
    e.hash = hash;
    e.time = QDateTime::currentSecsSinceEpoch();
    if (mime == "text/plain") {
        if (QString::fromUtf8(data).trimmed().isEmpty()) return;     // nothing but spaces
        e.kind = "text"; e.ext = "txt"; e.preview = previewOfText(data);
    } else {
        e.kind = "image"; e.ext = extOfMime(mime);
        QBuffer b; b.setData(data); b.open(QIODevice::ReadOnly);
        const QSize sz = QImageReader(&b).size();
        const QString bytes = data.size() >= 1 << 20 ? QString::number(data.size() / double(1 << 20), 'f', 1) + " MiB"
                                                     : QString::number((data.size() + 1023) / 1024) + " KiB";
        // the same shape as cliphist's, which the panel reads
        e.preview = QStringLiteral("[[ binary data %1 %2%3 ]]").arg(bytes, e.ext,
                    sz.isValid() ? QStringLiteral(" %1x%2").arg(sz.width()).arg(sz.height()) : QString());
    }
    QFile f(fileOf(e));
    if (!f.open(QIODevice::WriteOnly)) return;
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    f.write(data);
    f.close();
    m_entries.prepend(e);
    trim(); save(); publish();
}

void ClipboardHistory::gotCleared() {
    // the app you copied from closed: put your last copy back
    if (!m_persist || m_entries.isEmpty() || !m_worker) return;
    const QString id = m_entries.first().id;
    QTimer::singleShot(100, this, [this, id] { copy(id); });
}

void ClipboardHistory::copy(const QString &id) {
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].id != id) continue;
        QFile f(fileOf(m_entries[i]));
        if (!f.open(QIODevice::ReadOnly)) return;
        const QByteArray data = f.readAll();
        QStringList mimes;
        if (m_entries[i].kind == "text")
            mimes = { "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "TEXT", "STRING" };
        else mimes = { mimeOfExt(m_entries[i].ext) };
        if (m_worker) m_worker->setSelection(data, mimes);
        if (i > 0) { Entry e = m_entries.takeAt(i); e.time = QDateTime::currentSecsSinceEpoch(); m_entries.prepend(e); save(); publish(); }
        return;
    }
}

void ClipboardHistory::remove(const QString &id) {
    for (int i = 0; i < m_entries.size(); ++i) {
        if (m_entries[i].id != id) continue;
        QFile::remove(fileOf(m_entries[i]));
        m_entries.removeAt(i);
        save(); publish();
        return;
    }
}

void ClipboardHistory::clear() {
    for (const Entry &e : m_entries) QFile::remove(fileOf(e));
    m_entries.clear();
    save(); publish();
}

void ClipboardHistory::trim() {
    while (m_entries.size() > m_limit) { QFile::remove(fileOf(m_entries.last())); m_entries.removeLast(); }
}

void ClipboardHistory::load() {
    QFile f(m_dir + "/index.json");
    if (!f.open(QIODevice::ReadOnly)) return;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    m_nextId = std::max<qint64>(1, root.value("nextId").toInteger());
    for (const QJsonValue &v : root.value("entries").toArray()) {
        const QJsonObject o = v.toObject();
        Entry e{ o["id"].toString(), o["kind"].toString(), o["ext"].toString(), o["preview"].toString(),
                 o["hash"].toString(), o["time"].toInteger() };
        if (!e.id.isEmpty() && QFile::exists(fileOf(e))) m_entries.append(e);
    }
}

void ClipboardHistory::save() {
    QJsonArray arr;
    for (const Entry &e : m_entries)
        arr.append(QJsonObject{ { "id", e.id }, { "kind", e.kind }, { "ext", e.ext }, { "preview", e.preview },
                                { "hash", e.hash }, { "time", e.time } });
    const QByteArray json = QJsonDocument(QJsonObject{ { "nextId", m_nextId }, { "entries", arr } }).toJson(QJsonDocument::Compact);
    QFile f(m_dir + "/index.json.tmp");
    if (!f.open(QIODevice::WriteOnly)) return;
    f.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
    f.write(json);
    f.close();
    QFile::remove(m_dir + "/index.json");
    f.rename(m_dir + "/index.json");
}

void ClipboardHistory::publish() {
    QVariantList out;
    out.reserve(m_entries.size());
    for (const Entry &e : m_entries)
        out.append(QVariantMap{ { "id", e.id }, { "preview", e.preview }, { "ext", e.kind == "image" ? e.ext : QString() },
                                { "time", e.time } });
    m_items = out;
    emit itemsChanged();
}

// cliphist's newest 100 entries, oldest first, so the order is kept
void ClipboardHistory::importCliphist() {
    QProcess list;
    list.start("cliphist", { "list" });
    if (!list.waitForFinished(5000)) return;
    QStringList ids;
    for (const QByteArray &line : list.readAllStandardOutput().split('\n')) {
        const int tab = line.indexOf('\t');
        if (tab > 0) ids << QString::fromUtf8(line.left(tab));
        if (ids.size() >= 100) break;
    }
    for (int i = ids.size() - 1; i >= 0; --i) {
        QProcess dec;
        dec.start("cliphist", { "decode", ids[i] });
        if (!dec.waitForFinished(3000)) continue;
        const QByteArray d = dec.readAllStandardOutput();
        if (d.isEmpty()) continue;
        QString mime = "text/plain";
        if (d.startsWith("\x89PNG")) mime = "image/png";
        else if (d.startsWith("\xFF\xD8")) mime = "image/jpeg";
        else if (d.startsWith("GIF8")) mime = "image/gif";
        else if (d.startsWith("RIFF") && d.mid(8, 4) == "WEBP") mime = "image/webp";
        else if (d.startsWith("BM")) mime = "image/bmp";
        gotData(d, mime);
    }
    save();                                  // written even if cliphist had nothing, so this runs once
}
