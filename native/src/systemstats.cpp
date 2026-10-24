#include "systemstats.h"

#include <QDateTime>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>

// ---- NVML, the parts used, declared here so there's no build dependency ----
namespace {
using nvmlReturn_t = int;             // 0 = success
struct nvmlUtilization_t { unsigned int gpu; unsigned int memory; };
struct nvmlMemory_t { unsigned long long total; unsigned long long free; unsigned long long used; };
constexpr int NVML_TEMPERATURE_GPU = 0;

// a small /proc file, read whole (their reported size is 0, so read to EOF)
int readFile(const char *path, char *buf, int cap) {
    FILE *f = std::fopen(path, "re");
    if (!f) return -1;
    size_t n = std::fread(buf, 1, cap - 1, f);
    std::fclose(f);
    buf[n] = '\0';
    return int(n);
}
}

struct SystemStats::Fns {
    nvmlReturn_t (*init)();
    nvmlReturn_t (*shutdown)();
    nvmlReturn_t (*byIndex)(unsigned int, void **);
    nvmlReturn_t (*util)(void *, nvmlUtilization_t *);
    nvmlReturn_t (*temp)(void *, int, unsigned int *);
    nvmlReturn_t (*mem)(void *, nvmlMemory_t *);
    nvmlReturn_t (*power)(void *, unsigned int *);
};

SystemStats::SystemStats(QObject *parent) : QObject(parent) {
    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &SystemStats::sample);
}

SystemStats::~SystemStats() {
    if (m_fn && m_dev) m_fn->shutdown();
    delete m_fn;
    if (m_nvml) dlclose(m_nvml);
}

void SystemStats::setInterval(int ms) {
    ms = qMax(250, ms);
    if (ms == m_timer.interval()) return;
    m_timer.setInterval(ms);
    emit intervalChanged();
}

void SystemStats::setRunning(bool on) {
    if (on == m_timer.isActive()) return;
    if (on) { m_timer.start(); sample(); }   // a first reading straight away
    else m_timer.stop();
    emit runningChanged();
}

void SystemStats::sample() {
    readCpu();
    readMem();
    readNet(QDateTime::currentMSecsSinceEpoch());
    readGpu();
    emit updated();
}

void SystemStats::readCpu() {
    char buf[512];
    if (readFile("/proc/stat", buf, sizeof buf) <= 0) return;
    // "cpu  user nice system idle iowait irq softirq steal ..."
    unsigned long long v[8] = {0};
    if (std::sscanf(buf, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
                    &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7]) < 4) return;
    unsigned long long total = 0;
    for (auto x : v) total += x;
    const unsigned long long idle = v[3] + v[4];
    if (m_lastTotal && total > m_lastTotal) {
        const double dt = double(total - m_lastTotal);
        const double di = double(idle - m_lastIdle);
        m_cpuPct = int(100.0 * (dt - di) / dt + 0.5);
    }
    m_lastTotal = total;
    m_lastIdle = idle;
}

void SystemStats::readMem() {
    char buf[4096];
    if (readFile("/proc/meminfo", buf, sizeof buf) <= 0) return;
    unsigned long long total = 0, avail = 0;
    for (char *line = buf; line && *line; ) {
        char *next = std::strchr(line, '\n');
        if (next) *next++ = '\0';
        std::sscanf(line, "MemTotal: %llu", &total);
        if (std::sscanf(line, "MemAvailable: %llu", &avail) == 1) break;
        line = next;
    }
    if (total) m_memPct = int(100.0 * double(total - avail) / double(total) + 0.5);
}

void SystemStats::readNet(qint64 nowMs) {
    char buf[8192];
    if (readFile("/proc/net/dev", buf, sizeof buf) <= 0) return;
    unsigned long long rx = 0, tx = 0;
    int lineNo = 0;
    for (char *line = buf; line && *line; ++lineNo) {
        char *next = std::strchr(line, '\n');
        if (next) *next++ = '\0';
        if (lineNo >= 2) {                        // two header lines
            char *colon = std::strchr(line, ':');
            if (colon) {
                *colon = '\0';
                char *name = line;
                while (*name == ' ') ++name;
                if (std::strcmp(name, "lo") != 0) {
                    unsigned long long f[9] = {0};
                    if (std::sscanf(colon + 1, "%llu %llu %llu %llu %llu %llu %llu %llu %llu",
                                    &f[0], &f[1], &f[2], &f[3], &f[4], &f[5], &f[6], &f[7], &f[8]) == 9) {
                        rx += f[0];
                        tx += f[8];
                    }
                }
            }
        }
        line = next;
    }
    if (m_lastNetMs && nowMs > m_lastNetMs) {
        const double secs = (nowMs - m_lastNetMs) / 1000.0;
        m_down = rx >= m_lastRx ? (rx - m_lastRx) / secs : 0;
        m_up   = tx >= m_lastTx ? (tx - m_lastTx) / secs : 0;
    }
    m_lastRx = rx;
    m_lastTx = tx;
    m_lastNetMs = nowMs;
}

bool SystemStats::loadNvml() {
    m_nvmlTried = true;
    m_nvml = dlopen("libnvidia-ml.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!m_nvml) return false;
    auto sym = [this](const char *n) { return dlsym(m_nvml, n); };
    auto *fn = new Fns;
    fn->init     = reinterpret_cast<nvmlReturn_t (*)()>(sym("nvmlInit_v2"));
    fn->shutdown = reinterpret_cast<nvmlReturn_t (*)()>(sym("nvmlShutdown"));
    fn->byIndex  = reinterpret_cast<nvmlReturn_t (*)(unsigned int, void **)>(sym("nvmlDeviceGetHandleByIndex_v2"));
    fn->util     = reinterpret_cast<nvmlReturn_t (*)(void *, nvmlUtilization_t *)>(sym("nvmlDeviceGetUtilizationRates"));
    fn->temp     = reinterpret_cast<nvmlReturn_t (*)(void *, int, unsigned int *)>(sym("nvmlDeviceGetTemperature"));
    fn->mem      = reinterpret_cast<nvmlReturn_t (*)(void *, nvmlMemory_t *)>(sym("nvmlDeviceGetMemoryInfo"));
    fn->power    = reinterpret_cast<nvmlReturn_t (*)(void *, unsigned int *)>(sym("nvmlDeviceGetPowerUsage"));
    if (!fn->init || !fn->shutdown || !fn->byIndex || !fn->util || !fn->temp || !fn->mem || !fn->power
        || fn->init() != 0 || fn->byIndex(0, &m_dev) != 0) {
        delete fn;
        dlclose(m_nvml);
        m_nvml = nullptr;
        m_dev = nullptr;
        return false;
    }
    m_fn = fn;
    return true;
}

void SystemStats::readGpu() {
    if (!m_nvmlTried) loadNvml();
    if (!m_fn || !m_dev) { m_gpuOk = false; return; }
    nvmlUtilization_t u{};
    unsigned int t = 0, mw = 0;
    nvmlMemory_t m{};
    if (m_fn->util(m_dev, &u) != 0) { m_gpuOk = false; return; }
    m_gpuPct = int(u.gpu);
    if (m_fn->temp(m_dev, NVML_TEMPERATURE_GPU, &t) == 0) m_gpuTemp = int(t);
    if (m_fn->mem(m_dev, &m) == 0 && m.total) m_gpuMemPct = int(100.0 * double(m.used) / double(m.total) + 0.5);
    if (m_fn->power(m_dev, &mw) == 0) m_gpuWatts = int(mw / 1000.0 + 0.5);
    m_gpuOk = true;
}
