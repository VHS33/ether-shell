// The visualiser's bars from raw audio: what cava computes, done in-process.
//
//   Spectrum s(28, 48000);
//   s.push(samples, n);          // mono float samples, as they arrive
//   s.update();                  // once a frame: s.bars() are 0..1
//
// A 4096-point FFT (Hann window) of the newest audio (fine enough that a
// bass note lights a few bars, not a dozen, for one frame more of lag); 28 bands from 50 Hz to
// 10 kHz, spaced by pitch (each band the same musical width, as cava does),
// so bass, voices and cymbals each get their share; each band's strength on
// a linear scale, lifted with pitch (music has far less energy up high), so
// a strong note stands far taller than its neighbours and the bars jump;
// each band evened out against its own recent peaks (within limits), so a
// bass-heavy track still shows its cymbals and a bright one its bass;
// automatic sensitivity as cava does it (bars
// may hit the top; it eases off only while they keep overshooting, and
// creeps back up through quiet passages); and smoothing like cava's: a quick
// rise, and a fall that speeds up the longer a bar drops (its "gravity").
// Tuned against cava itself, live, on the same music: bars swing about three
// times as much as with the log scale this replaced (more than cava's own),
// with less flicker, and bass, mids and treble all stay alive whatever the
// music's balance.
#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <vector>

class Spectrum {
public:
    static constexpr int N = 4096;   // fine enough for the bass bars (11.7 Hz a bin)

    Spectrum(int bars, double rate) : m_bars(bars), m_rate(rate), m_ring(N, 0.f), m_level(bars, 0.0),
                                      m_peak(bars, 0.0), m_fall(bars, 0.0), m_edges(bars + 1, 0) {
        for (int i = 0; i < N; ++i) m_window[i] = 0.5 - 0.5 * std::cos(2 * M_PI * i / (N - 1));
        // band edges, spaced by pitch between 50 Hz and 10 kHz, in FFT bins
        const double lo = 50.0, hi = 10000.0, binHz = rate / N;
        for (int b = 0; b <= bars; ++b) {
            const double f = lo * std::pow(hi / lo, double(b) / bars);
            m_edges[b] = std::max(1, int(std::lround(f / binHz)));
        }
        // at least one bin per band (the low bands are narrow)
        for (int b = 1; b <= bars; ++b) if (m_edges[b] <= m_edges[b - 1]) m_edges[b] = m_edges[b - 1] + 1;
    }

    void push(const float *mono, int n) {
        for (int i = 0; i < n; ++i) { m_ring[m_pos] = mono[i]; m_pos = (m_pos + 1) % N; }
    }

    // one frame: the bars from the newest N samples
    void update() {
        // window, oldest first
        std::vector<std::complex<double>> x(N);
        double energy = 0;
        for (int i = 0; i < N; ++i) {
            const float v = m_ring[(m_pos + i) % N];
            energy += double(v) * v;
            x[i] = v * m_window[i];
        }
        fft(x);
        const bool silent = energy / N < 1e-9;       // below -90 dBFS: nothing playing
        std::vector<double> raw(m_bars, 0.0);
        double frameMax = 0;
        for (int b = 0; b < m_bars; ++b) {
            double sum = 0;
            for (int k = m_edges[b]; k < m_edges[b + 1] && k < N / 2; ++k) sum += std::norm(x[k]);
            const int w = std::max(1, m_edges[b + 1] - m_edges[b]);
            // linear strength (as cava measures): a note ten times stronger
            // than its neighbours stands ten times taller, which is what makes
            // the bars jump; lifted with pitch (cava's equaliser does the
            // same), since treble carries far less energy than bass
            const double centre = (m_edges[b] + m_edges[b + 1]) * 0.5 * m_rate / N;
            raw[b] = silent ? 0 : std::sqrt(sum / w) * std::pow(centre, 0.8);
            frameMax = std::max(frameMax, raw[b]);
        }
        // adapt to the music's own balance: each band's long-run peak, evened
        // out against the others (at most 3x lifted, or halved), so a
        // bass-heavy track still shows its cymbals and a bright one its bass
        if (!silent) {
            double meanPeak = 0;
            for (int b = 0; b < m_bars; ++b) { m_bandPeak[b] = std::max(raw[b], m_bandPeak[b] * 0.997); meanPeak += m_bandPeak[b]; }
            meanPeak /= m_bars;
            frameMax = 0;
            for (int b = 0; b < m_bars; ++b) {
                if (m_bandPeak[b] > 0) raw[b] *= std::clamp(meanPeak / m_bandPeak[b], 0.5, 3.0);
                frameMax = std::max(frameMax, raw[b]);
            }
        }
        // automatic sensitivity, as cava does it: bars may hit the top (that's
        // the punch); only while they keep overshooting does it ease off, and
        // through quiet passages it creeps back up.  The first sound sets it.
        if (!silent && frameMax > 0) {
            if (m_gain <= 0) m_gain = 0.8 / frameMax;
            else if (frameMax * m_gain > 1.0) m_gain *= 0.98;
            else m_gain *= 1.004;
        }
        for (int b = 0; b < m_bars; ++b) {
            double v = std::min(1.0, raw[b] * m_gain);
            // smoothing: rise at once, fall with gravity
            if (v >= m_level[b]) { m_level[b] = v; m_fall[b] = 0; }
            else {
                m_fall[b] += 1.0;
                m_level[b] = std::max(v, m_level[b] - 0.0028 * m_fall[b] * m_fall[b]);
            }
            // cava's "integral" smoothing: a little of the last frame kept
            m_peak[b] = 0.65 * m_peak[b] + 0.35 * m_level[b];
            if (silent) { m_level[b] *= 0.8; m_peak[b] *= 0.8; if (m_peak[b] < 1e-3) m_peak[b] = 0; }
        }
    }

    const std::vector<double> &bars() const { return m_peak; }
    const std::vector<int> &edges() const { return m_edges; }

private:
    static void fft(std::vector<std::complex<double>> &a) {
        const size_t n = a.size();
        for (size_t i = 1, j = 0; i < n; ++i) {
            size_t bit = n >> 1;
            for (; j & bit; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) std::swap(a[i], a[j]);
        }
        for (size_t len = 2; len <= n; len <<= 1) {
            const double ang = -2 * M_PI / double(len);
            const std::complex<double> wl(std::cos(ang), std::sin(ang));
            for (size_t i = 0; i < n; i += len) {
                std::complex<double> w(1);
                for (size_t k = 0; k < len / 2; ++k) {
                    const auto u = a[i + k], v = a[i + k + len / 2] * w;
                    a[i + k] = u + v; a[i + k + len / 2] = u - v;
                    w *= wl;
                }
            }
        }
    }

    int m_bars;
    double m_rate;
    std::array<double, N> m_window{};
    std::vector<float> m_ring;
    int m_pos = 0;
    std::vector<double> m_level, m_peak, m_fall;
    std::vector<int> m_edges;
    double m_gain = 0;
    std::vector<double> m_bandPeak = std::vector<double>(64, 0.0);
};
