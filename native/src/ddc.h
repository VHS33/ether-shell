// Ddc: monitor brightness over DDC/CI, directly, instead of running ddcutil
// for every change.
//
//   Ddc { id: ddc; onRead: (bus, percent) => ...; onFailed: bus => ... }
//   ddc.get(7)          // read the brightness on /dev/i2c-7
//   ddc.set(7, 60)      // set it to 60% (of the monitor's own maximum)
//
// Each monitor's bus is opened once and kept open.  Work happens on a
// background thread; while you drag a slider only the latest value per
// monitor is sent, at the pace the protocol allows (50 ms after each set,
// 40 ms between a get and its reply).  Plain write() and read() are used,
// not combined I2C_RDWR transfers, which NVIDIA's driver rejects (ddcutil
// switches to the same when it meets that).  Anything that doesn't work
// (no access to the bus, a monitor that doesn't answer) is reported with
// failed(bus), and the shell uses ddcutil for that monitor instead.
#pragma once

#include <QObject>
#include <QtQml/qqmlregistration.h>
#include <condition_variable>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <set>
#include <thread>

class DdcTransport {
public:
    virtual ~DdcTransport() = default;
    virtual bool write(const uint8_t *data, size_t len) = 0;
    virtual long read(uint8_t *buf, size_t len) = 0;
};

class Ddc : public QObject {
    Q_OBJECT
    QML_ELEMENT

public:
    explicit Ddc(QObject *parent = nullptr);
    ~Ddc() override;

    Q_INVOKABLE void get(int bus);
    Q_INVOKABLE void set(int bus, int percent);

    // for tests: how buses are opened (default: /dev/i2c-N at address 0x37)
    using Opener = std::function<std::unique_ptr<DdcTransport>(int bus)>;
    static void setOpener(Opener opener);

signals:
    void read(int bus, int percent);
    void failed(int bus);

private:
    void run();
    bool getNow(int bus, int *percent);
    bool setNow(int bus, int percent);
    DdcTransport *busOf(int bus);
    void pace(int bus, int ms);

    std::thread m_thread;
    std::mutex m_mutex;
    std::condition_variable m_wake;
    bool m_stop = false;
    std::set<int> m_gets;                               // buses to read
    std::map<int, int> m_sets;                          // bus -> latest percent to set
    // worker thread only:
    std::map<int, std::unique_ptr<DdcTransport>> m_buses;
    std::set<int> m_dead;                               // buses that couldn't be opened
    std::map<int, int> m_max;                           // bus -> the monitor's maximum
    std::map<int, long long> m_lastAt;                  // bus -> when the last command went, ms
};
