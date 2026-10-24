#pragma once
// CPU, memory, network and GPU readings, taken in-process.
//
// /proc/stat, /proc/meminfo and /proc/net/dev are read directly (no shell,
// no helper programs).  The GPU is read through NVIDIA's own library, NVML,
// loaded at runtime: on machines without it gpuOk simply stays false.
#include <QObject>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

class SystemStats : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(int interval READ interval WRITE setInterval NOTIFY intervalChanged)
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int cpuPct READ cpuPct NOTIFY updated)
    Q_PROPERTY(int memPct READ memPct NOTIFY updated)
    Q_PROPERTY(double netDownBps READ netDownBps NOTIFY updated)
    Q_PROPERTY(double netUpBps READ netUpBps NOTIFY updated)
    Q_PROPERTY(bool gpuOk READ gpuOk NOTIFY updated)
    Q_PROPERTY(int gpuPct READ gpuPct NOTIFY updated)
    Q_PROPERTY(int gpuTemp READ gpuTemp NOTIFY updated)
    Q_PROPERTY(int gpuMemPct READ gpuMemPct NOTIFY updated)
    Q_PROPERTY(int gpuWatts READ gpuWatts NOTIFY updated)

public:
    explicit SystemStats(QObject *parent = nullptr);
    ~SystemStats() override;

    int interval() const { return m_timer.interval(); }
    void setInterval(int ms);
    bool running() const { return m_timer.isActive(); }
    void setRunning(bool on);

    int cpuPct() const { return m_cpuPct; }
    int memPct() const { return m_memPct; }
    double netDownBps() const { return m_down; }
    double netUpBps() const { return m_up; }
    bool gpuOk() const { return m_gpuOk; }
    int gpuPct() const { return m_gpuPct; }
    int gpuTemp() const { return m_gpuTemp; }
    int gpuMemPct() const { return m_gpuMemPct; }
    int gpuWatts() const { return m_gpuWatts; }

    Q_INVOKABLE void sampleNow() { sample(); }

signals:
    void updated();
    void intervalChanged();
    void runningChanged();

private:
    void sample();
    void readCpu();
    void readMem();
    void readNet(qint64 nowMs);
    void readGpu();
    bool loadNvml();

    QTimer m_timer;
    // cpu: the previous totals, to take the busy share since then
    unsigned long long m_lastTotal = 0, m_lastIdle = 0;
    // network: the previous byte counts, and when they were read
    unsigned long long m_lastRx = 0, m_lastTx = 0;
    qint64 m_lastNetMs = 0;

    int m_cpuPct = 0, m_memPct = 0;
    double m_down = 0, m_up = 0;
    bool m_gpuOk = false;
    int m_gpuPct = 0, m_gpuTemp = 0, m_gpuMemPct = 0, m_gpuWatts = 0;

    // NVML, loaded at runtime
    void *m_nvml = nullptr;
    void *m_dev = nullptr;
    bool m_nvmlTried = false;
    struct Fns;
    Fns *m_fn = nullptr;
};
