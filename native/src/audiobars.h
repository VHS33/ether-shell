// AudioBars: the visualiser's bars from what your speakers are playing,
// captured from PipeWire directly (no cava).
//
//   AudioBars { running: drawerOpen; bars: 28; onValuesChanged: ... }
//
// While running, a PipeWire stream captures the default output's monitor
// (the sound going to your speakers), mixed to mono; 30 times a second the
// Spectrum turns the newest audio into bars, 0-100 (as cava's reader gives
// them, and as the media views draw them).  Stopped, the stream is
// gone entirely.  available is false when PipeWire can't be reached (or the
// plugin was built without it): the shell uses cava then.
#pragma once

#include <QObject>
#include <QList>
#include <QTimer>
#include <QtQml/qqmlregistration.h>
#include <memory>
#include <mutex>
#include <vector>

class Spectrum;
struct pw_thread_loop;
struct pw_stream;

class AudioBars : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool running READ running WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(int bars READ bars WRITE setBars NOTIFY barsChanged)
    Q_PROPERTY(QList<qreal> values READ values NOTIFY valuesChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)

public:
    explicit AudioBars(QObject *parent = nullptr);
    ~AudioBars() override;

    bool running() const { return m_running; }
    void setRunning(bool on);
    int bars() const { return m_bars; }
    void setBars(int n);
    QList<qreal> values() const { return m_values; }
    bool available() const { return m_available; }

    // PipeWire's thread hands captured audio over here (mono)
    void feed(const float *mono, int n);
    void streamFailed();

signals:
    void runningChanged();
    void barsChanged();
    void valuesChanged();
    void availableChanged();

private:
    void start();
    void stop();
    void frame();

    bool m_running = false;
    bool m_available = true;
    int m_bars = 28;
    QList<qreal> m_values;
    QTimer m_frame;
    std::unique_ptr<Spectrum> m_spectrum;
    std::mutex m_mutex;
    std::vector<float> m_pending;             // audio since the last frame
    pw_thread_loop *m_loop = nullptr;
    pw_stream *m_stream = nullptr;
    void *m_hook = nullptr;                   // the stream's listener (spa_hook)
};
