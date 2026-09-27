#include "audiobars.h"
#include "spectrum.h"

#include <QMetaObject>
#include <QPointer>

#include <algorithm>
#include <cmath>

#ifdef ETHER_HAVE_PIPEWIRE
#include <pipewire/pipewire.h>
#include <spa/param/audio/format-utils.h>
#include <spa/pod/builder.h>
#endif

namespace {
constexpr int kRate = 48000;       // PipeWire converts to this for us
constexpr int kChannels = 2;
}

#ifdef ETHER_HAVE_PIPEWIRE
namespace {
struct Hook { spa_hook listener; AudioBars *owner; pw_stream *stream; };

// PipeWire's real-time thread: take the buffer, mix to mono, hand it over
void onProcess(void *data) {
    auto *h = static_cast<Hook *>(data);
    pw_buffer *b = pw_stream_dequeue_buffer(h->stream);
    if (!b) return;
    spa_buffer *buf = b->buffer;
    if (buf->n_datas > 0 && buf->datas[0].data && buf->datas[0].chunk) {
        const auto *src = reinterpret_cast<const float *>(
            static_cast<const char *>(buf->datas[0].data) + buf->datas[0].chunk->offset);
        const int frames = int(buf->datas[0].chunk->size / (sizeof(float) * kChannels));
        float mono[4096];
        for (int done = 0; done < frames;) {
            const int n = std::min(frames - done, 4096);
            for (int i = 0; i < n; ++i) mono[i] = 0.5f * (src[(done + i) * 2] + src[(done + i) * 2 + 1]);
            h->owner->feed(mono, n);
            done += n;
        }
    }
    pw_stream_queue_buffer(h->stream, b);
}

void onStateChanged(void *data, pw_stream_state, pw_stream_state state, const char *) {
    if (state == PW_STREAM_STATE_ERROR) static_cast<Hook *>(data)->owner->streamFailed();
}

const pw_stream_events kEvents = [] {
    pw_stream_events e{};
    e.version = PW_VERSION_STREAM_EVENTS;
    e.state_changed = onStateChanged;
    e.process = onProcess;
    return e;
}();
}
#endif

AudioBars::AudioBars(QObject *parent) : QObject(parent) {
#ifdef ETHER_HAVE_PIPEWIRE
    static bool inited = false;
    if (!inited) { pw_init(nullptr, nullptr); inited = true; }
#else
    m_available = false;
#endif
    m_frame.setInterval(33);                     // 30 frames a second, as cava ran
    connect(&m_frame, &QTimer::timeout, this, &AudioBars::frame);
    m_values = QList<qreal>(m_bars, 0.0);
}

AudioBars::~AudioBars() { stop(); }

void AudioBars::setRunning(bool on) {
    if (on == m_running) return;
    m_running = on;
    emit runningChanged();
    if (on) start(); else stop();
}

void AudioBars::setBars(int n) {
    n = std::clamp(n, 4, 128);
    if (n == m_bars) return;
    m_bars = n;
    emit barsChanged();
    if (m_running) { stop(); start(); }
    m_values = QList<qreal>(m_bars, 0.0);
    emit valuesChanged();
}

void AudioBars::feed(const float *mono, int n) {
    std::lock_guard lk(m_mutex);
    m_pending.insert(m_pending.end(), mono, mono + n);
    if (m_pending.size() > size_t(Spectrum::N) * 2)             // keep only what one frame can use
        m_pending.erase(m_pending.begin(), m_pending.end() - Spectrum::N);
}

void AudioBars::streamFailed() {
    QPointer<AudioBars> self(this);
    QMetaObject::invokeMethod(this, [self] {
        if (!self || !self->m_available) return;
        self->m_available = false;
        emit self->availableChanged();
    }, Qt::QueuedConnection);
}

void AudioBars::frame() {
    std::vector<float> take;
    { std::lock_guard lk(m_mutex); take.swap(m_pending); }
    if (!take.empty()) m_spectrum->push(take.data(), int(take.size()));
    m_spectrum->update();
    QList<qreal> v;
    v.reserve(m_bars);
    // 0-100, the scale cava's reader uses and the media views draw from
    for (double x : m_spectrum->bars()) v.append(std::round(x * 1000.0) / 10.0);
    if (v != m_values) { m_values = v; emit valuesChanged(); }
}

void AudioBars::start() {
    m_spectrum = std::make_unique<Spectrum>(m_bars, kRate);
    { std::lock_guard lk(m_mutex); m_pending.clear(); }
#ifdef ETHER_HAVE_PIPEWIRE
    m_loop = pw_thread_loop_new("ether-visualiser", nullptr);
    if (!m_loop || pw_thread_loop_start(m_loop) < 0) { streamFailed(); return; }
    pw_thread_loop_lock(m_loop);
    pw_properties *props = pw_properties_new(
        PW_KEY_MEDIA_TYPE, "Audio",
        PW_KEY_MEDIA_CATEGORY, "Capture",
        PW_KEY_MEDIA_ROLE, "Music",
        PW_KEY_STREAM_CAPTURE_SINK, "true",           // what the speakers play, not a microphone
        PW_KEY_NODE_NAME, "ether-shell-visualiser",
        PW_KEY_NODE_DESCRIPTION, "Ether Shell visualiser",
        PW_KEY_APP_NAME, "Ether Shell",
        nullptr);
    auto *hook = new Hook{};
    hook->owner = this;
    m_stream = pw_stream_new_simple(pw_thread_loop_get_loop(m_loop), "Ether Shell visualiser", props, &kEvents, hook);
    hook->stream = m_stream;
    m_hook = hook;
    if (!m_stream) { pw_thread_loop_unlock(m_loop); streamFailed(); return; }
    uint8_t podBuf[1024];
    spa_pod_builder b = SPA_POD_BUILDER_INIT(podBuf, sizeof podBuf);
    spa_audio_info_raw info{};
    info.format = SPA_AUDIO_FORMAT_F32;
    info.rate = kRate;
    info.channels = kChannels;
    info.position[0] = SPA_AUDIO_CHANNEL_FL;
    info.position[1] = SPA_AUDIO_CHANNEL_FR;
    const spa_pod *params[1] = { spa_format_audio_raw_build(&b, SPA_PARAM_EnumFormat, &info) };
    const int rc = pw_stream_connect(m_stream, PW_DIRECTION_INPUT, PW_ID_ANY,
        pw_stream_flags(PW_STREAM_FLAG_AUTOCONNECT | PW_STREAM_FLAG_MAP_BUFFERS | PW_STREAM_FLAG_RT_PROCESS),
        params, 1);
    pw_thread_loop_unlock(m_loop);
    if (rc < 0) { streamFailed(); return; }
#endif
    m_frame.start();
}

void AudioBars::stop() {
    m_frame.stop();
#ifdef ETHER_HAVE_PIPEWIRE
    if (m_loop) {
        pw_thread_loop_lock(m_loop);
        if (m_stream) { pw_stream_destroy(m_stream); m_stream = nullptr; }
        pw_thread_loop_unlock(m_loop);
        pw_thread_loop_stop(m_loop);
        pw_thread_loop_destroy(m_loop);
        m_loop = nullptr;
    }
    delete static_cast<Hook *>(m_hook);
    m_hook = nullptr;
#endif
    bool any = false;
    for (qreal x : m_values) if (x != 0) { any = true; break; }
    if (any) { m_values = QList<qreal>(m_bars, 0.0); emit valuesChanged(); }
}
