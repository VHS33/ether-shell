#include "cavareader.h"

CavaReader::CavaReader(QObject *parent) : QObject(parent) {
    m_values = QList<qreal>(m_bars, 0.0);
    m_proc.setProcessChannelMode(QProcess::SeparateChannels);
    m_proc.setStandardErrorFile(QProcess::nullDevice());
    connect(&m_proc, &QProcess::readyReadStandardOutput, this, &CavaReader::onReadyRead);
    connect(&m_proc, &QProcess::finished, this, [this] { clear(); });
}

CavaReader::~CavaReader() { stop(); }

void CavaReader::setRunning(bool on) {
    if (on == m_want) return;
    m_want = on;
    if (on) start(); else stop();
    emit runningChanged();
}

void CavaReader::setConfig(const QString &c) {
    if (c == m_config) return;
    m_config = c;
    emit configChanged();
    if (m_want) { stop(); start(); }
}

void CavaReader::setProgram(const QString &p) {
    if (p == m_program) return;
    m_program = p;
    emit programChanged();
}

void CavaReader::setArguments(const QStringList &a) {
    if (a == m_args) return;
    m_args = a;
    emit argumentsChanged();
}

void CavaReader::setBars(int n) {
    n = qBound(1, n, 512);
    if (n == m_bars) return;
    m_bars = n;
    m_buf.clear();
    m_values = QList<qreal>(m_bars, 0.0);
    emit barsChanged();
    emit valuesChanged();
}

void CavaReader::start() {
    if (m_proc.state() != QProcess::NotRunning) return;
    m_buf.clear();
    QStringList args = m_args;
    if (args.isEmpty() && !m_config.isEmpty()) args = { QStringLiteral("-p"), m_config };
    m_proc.start(m_program, args, QIODevice::ReadOnly);
}

void CavaReader::stop() {
    if (m_proc.state() != QProcess::NotRunning) {
        m_proc.terminate();
        if (!m_proc.waitForFinished(300)) m_proc.kill();
    }
    clear();
}

void CavaReader::clear() {
    m_buf.clear();
    bool any = false;
    for (qreal v : std::as_const(m_values)) if (v != 0.0) { any = true; break; }
    if (!any) return;
    m_values = QList<qreal>(m_bars, 0.0);
    emit valuesChanged();
}

void CavaReader::onReadyRead() {
    m_buf.append(m_proc.readAllStandardOutput());
    const int frame = m_bars * 2;                 // 16 bits a bar
    if (m_buf.size() < frame) return;
    // the newest complete frame; anything older is skipped
    const int frames = int(m_buf.size() / frame);
    const auto *p = reinterpret_cast<const unsigned char *>(m_buf.constData()) + (frames - 1) * frame;
    QList<qreal> out(m_bars);
    for (int i = 0; i < m_bars; ++i) {
        const unsigned int v = unsigned(p[2 * i]) | (unsigned(p[2 * i + 1]) << 8);   // little-endian
        out[i] = v * 100.0 / 65535.0;
    }
    m_buf.remove(0, frames * frame);
    m_values = out;
    emit valuesChanged();
}
