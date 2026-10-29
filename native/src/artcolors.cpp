#include "artcolors.h"

#include <QFutureWatcher>
#include <QImageReader>
#include <QNetworkAccessManager>
#include <QtConcurrent/QtConcurrent>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QVariantMap>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <vector>
#include <queue>

// colour helpers (OKLab), used by the smart colour and Auto style
namespace {
struct Lab { double L, A, B; };
inline double toLinear(double c) { c /= 255.0; return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); }
inline Lab toOklab(QRgb p) {
    const double r = toLinear(qRed(p)), g = toLinear(qGreen(p)), b = toLinear(qBlue(p));
    const double l = std::cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const double m = std::cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const double s = std::cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return { 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
             1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
             0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s };
}
inline QColor fromOklab(double L, double A, double B) {
    const double l = std::pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
    const double m = std::pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
    const double s = std::pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
    auto enc = [](double x) { x = std::clamp(x, 0.0, 1.0); return x <= 0.0031308 ? 12.92 * x : 1.055 * std::pow(x, 1 / 2.4) - 0.055; };
    auto ch = [&](double v) { return int(std::lround(enc(v) * 255)); };
    return QColor(ch(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                  ch(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                  ch(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s));
}
// a box blur with the edges clamped, radius r, on a w x h grid
std::vector<double> boxBlur(const std::vector<double> &a, int w, int h, int r) {
    std::vector<double> tmp(a.size()), out(a.size());
    const double k = 2 * r + 1;
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            double s = 0;
            for (int d = -r; d <= r; ++d) s += a[size_t(y) * w + std::clamp(x + d, 0, w - 1)];
            tmp[size_t(y) * w + x] = s / k;
        }
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            double s = 0;
            for (int d = -r; d <= r; ++d) s += tmp[size_t(std::clamp(y + d, 0, h - 1)) * w + x];
            out[size_t(y) * w + x] = s / k;
        }
    return out;
}
double percentile(std::vector<double> v, double p) {
    if (v.empty()) return 0;
    std::sort(v.begin(), v.end());
    const double idx = p / 100.0 * (v.size() - 1);
    const size_t lo = size_t(std::floor(idx)), hi = std::min(v.size() - 1, lo + 1);
    return v[lo] + (v[hi] - v[lo]) * (idx - lo);
}
inline double hueDist(double a, double b) { return std::fabs(std::fmod(a - b + 540.0, 360.0) - 180.0); }
}


ArtColors::ArtColors(QObject *parent) : QObject(parent) {}

ArtColors::~ArtColors() {
    if (m_reply) m_reply->abort();
}

void ArtColors::setSource(const QString &s) {
    if (s == m_source) return;
    m_source = s;
    emit sourceChanged();
    load();
}

void ArtColors::setDark(bool d) {
    if (d == m_dark) return;
    m_dark = d;
    emit darkChanged();
    if (m_valid) apply(m_seed);
}

void ArtColors::clear() {
    if (!m_valid) return;
    m_valid = false;
    emit colorsChanged();
}

void ArtColors::load() {
    if (m_reply) { m_reply->abort(); m_reply = nullptr; }
    if (m_source.isEmpty()) { clear(); return; }
    if (m_cache.contains(m_source)) {                // seen before: all of it, as it was
        setResult(m_cache.value(m_source));
        return;
    }
    const QUrl url(m_source);
    const QString scheme = url.scheme().toLower();
    if (scheme == "http" || scheme == "https") {
        if (!m_net) m_net = new QNetworkAccessManager(this);
        QNetworkRequest req(url);
        req.setTransferTimeout(6000);
        m_reply = m_net->get(req);
        const QString forSource = m_source;
        connect(m_reply, &QNetworkReply::finished, this, [this, reply = m_reply, forSource] {
            if (!reply) return;
            reply->deleteLater();
            if (reply->error() != QNetworkReply::NoError) { if (forSource == m_source) clear(); return; }
            useImage(QImage::fromData(reply->readAll()), forSource);
        });
        return;
    }
    if (scheme == "data") {
        const int comma = m_source.indexOf(',');
        QImage img;
        if (comma > 0) img = QImage::fromData(QByteArray::fromBase64(m_source.mid(comma + 1).toLatin1()));
        useImage(img, m_source);
        return;
    }
    // a file: decoded on a background thread, at a reduced size (a 4K
    // wallpaper decoded whole took a noticeable moment, and stalled the
    // shell while it did).  JPEGs decode straight to the smaller size.
    const QString path = scheme == "file" ? url.toLocalFile() : m_source;
    const QString forSource = m_source;
    auto *watcher = new QFutureWatcher<QImage>(this);
    connect(watcher, &QFutureWatcher<QImage>::finished, this, [this, watcher, forSource] {
        useImage(watcher->result(), forSource);
        watcher->deleteLater();
    });
    watcher->setFuture(QtConcurrent::run([path] {
        QImageReader reader(path);
        reader.setAutoTransform(true);
        const QSize full = reader.size();
        if (full.isValid() && std::max(full.width(), full.height()) > 480)
            reader.setScaledSize(full.scaled(480, 480, Qt::KeepAspectRatio));
        return reader.read();
    }));
}

ArtColors::Result ArtColors::analyse(const QImage &img) {
    Result r;
    if (img.isNull()) return r;                        // nothing: every field says so
    r.seed = seedOf(img);
    r.lightness = lightnessOf(img);
    double sat = 0;
    colourStats(img, &r.colourfulness, &r.hueFocus, &sat);
    r.scheme = schemeFor(r.colourfulness, r.hueFocus, sat);
    r.detail = detailOf(img);
    const Smart sm = smartAnalyse(img);
    r.smartSeed = sm.seed; r.smartSecond = sm.second; r.smartThird = sm.third; r.why = sm.why; r.skin = sm.skin;
    r.smart = sm;
    // A clear subject colour in a mostly dark or grey picture (red poppies
    // in the gloom): Auto style mustn't call it monochrome or neutral and
    // throw that colour away.  One colour, so content if it's most of the
    // picture's colour; tonal spot otherwise.
    if (sm.seed.isValid() && sm.why != QLatin1String("no strong colour")
            && (r.scheme == QLatin1String("scheme-monochrome") || r.scheme == QLatin1String("scheme-neutral"))) {
        const Lab o = toOklab(sm.seed.rgb());
        // judged against its lightness: a deep green or purple is plainly
        // coloured even though, being dark, it has little colour to measure
        const double c = std::hypot(o.A, o.B);
        if (c >= 0.06 || (c >= 0.03 && c / std::max(0.05, o.L) >= 0.15))
            r.scheme = r.hueFocus > 0.6 ? QStringLiteral("scheme-content") : QStringLiteral("scheme-tonal-spot");
    }
    r.aspect = double(img.width()) / std::max(1, img.height());
    return r;
}

void ArtColors::setResult(const Result &r) {
    m_lightness = r.lightness;
    m_colourfulness = r.colourfulness;
    m_hueFocus = r.hueFocus;
    m_scheme = r.scheme;
    m_smartSeed = r.smartSeed;
    m_smartSecond = r.smartSecond;
    m_smartThird = r.smartThird;
    m_smartWhy = r.why;
    m_skinShare = r.skin;
    m_smart = r.smart;
    m_detail = r.detail;
    m_aspect = r.aspect;
    if (r.seed.isValid()) apply(r.seed); else clear();
    emit analyzed();
}

void ArtColors::useImage(const QImage &img, const QString &forSource) {
    const Result r = analyse(img);
    if (m_cache.size() > 64) m_cache.clear();
    m_cache.insert(forSource, r);
    if (forSource != m_source) return;        // the source changed meanwhile
    setResult(r);
}

void ArtColors::colourStats(const QImage &src, double *colourfulness, double *hueFocus, double *saturation) {
    const QImage img = src.scaled(96, 96, Qt::IgnoreAspectRatio, Qt::FastTransformation)
                          .convertToFormat(QImage::Format_ARGB32);
    // Hasler and Susstrunk: spread and strength of the red-green and
    // yellow-blue opponent channels
    double srg = 0, syb = 0, srg2 = 0, syb2 = 0; int n = 0;
    double hueW[12] = {0}; double totalW = 0; double satSum = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QRgb p = line[x];
            const double r = qRed(p), g = qGreen(p), b = qBlue(p);
            const double rg = std::fabs(r - g), yb = std::fabs(0.5 * (r + g) - b);
            srg += rg; syb += yb; srg2 += rg * rg; syb2 += yb * yb; ++n;
            // hue families, weighted by how coloured each pixel is
            const QColor c(p);
            const double s = c.hsvSaturationF(), v = c.valueF();
            satSum += v > 0.12 ? s : 0;
            if (c.hsvHue() >= 0 && s > 0.15 && v > 0.12) {
                const double w = s * v;
                hueW[(c.hsvHue() / 30) % 12] += w;
                totalW += w;
            }
        }
    }
    const double mrg = srg / n, myb = syb / n;
    const double drg = std::sqrt(std::max(0.0, srg2 / n - mrg * mrg));
    const double dyb = std::sqrt(std::max(0.0, syb2 / n - myb * myb));
    *colourfulness = std::sqrt(drg * drg + dyb * dyb) + 0.3 * std::sqrt(mrg * mrg + myb * myb);
    // the share of all colour in the strongest family and its neighbours
    double best = 0;
    for (int i = 0; i < 12; ++i)
        best = std::max(best, hueW[i] + 0.5 * (hueW[(i + 11) % 12] + hueW[(i + 1) % 12]));
    *hueFocus = totalW > 0 ? std::min(1.0, best / totalW) : 0;
    *saturation = n ? satSum / n : 0;
}

QString ArtColors::schemeFor(double colourfulness, double hueFocus, double saturation) {
    const bool vivid = colourfulness >= 45 || saturation > 0.4;            // rich colour, even if flat
    if (colourfulness < 12 && saturation < 0.12) return QStringLiteral("scheme-monochrome");  // black and white
    if (!vivid && colourfulness < 35) return QStringLiteral("scheme-neutral");                // muted and pastel
    // one bold colour: content, which keeps the main colour as faithful as
    // fidelity but takes its third accent from a neighbouring hue; fidelity
    // takes the opposite one (teal for an orange wallpaper, blue for red),
    // a colour that usually isn't in the picture at all
    if (hueFocus > 0.72 && vivid) return QStringLiteral("scheme-content");
    return QStringLiteral("scheme-tonal-spot");                                               // colourful and varied
}

// edge detail on a 160 x 90 grid: the difference between neighbours, so a
// smooth gradient (a sky) is calm while texture and outlines are busy
QImage ArtColors::detailOf(const QImage &src) {
    const QImage g = src.scaled(160, 90, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                        .convertToFormat(QImage::Format_Grayscale8);
    QImage d(g.size(), QImage::Format_Grayscale8);
    d.fill(0);
    for (int y = 1; y < g.height() - 1; ++y) {
        const uchar *u = g.constScanLine(y - 1), *m = g.constScanLine(y), *l = g.constScanLine(y + 1);
        uchar *o = d.scanLine(y);
        for (int x = 1; x < g.width() - 1; ++x) {
            // Sobel
            const int gx = (u[x + 1] + 2 * m[x + 1] + l[x + 1]) - (u[x - 1] + 2 * m[x - 1] + l[x - 1]);
            const int gy = (l[x - 1] + 2 * l[x] + l[x + 1]) - (u[x - 1] + 2 * u[x] + u[x + 1]);
            o[x] = uchar(std::min(255.0, std::sqrt(double(gx * gx + gy * gy)) / 4.0));
        }
    }
    return d;
}

QVariantList ArtColors::calmSpots(const QVariantList &sizes, int screenW, int screenH,
                                  int top, int bottom, int margin) const {
    QVariantList out;
    if (m_detail.isNull() || screenW <= 0 || screenH <= 0) return out;
    const int gw = m_detail.width(), gh = m_detail.height();
    // the wallpaper covers the screen: scaled to fill, centred, cropped.  Work
    // on a grid over the screen, each cell sampling the part of the image
    // shown there.
    const int cw = 96, ch = int(std::round(96.0 * screenH / screenW));
    // the grid is a fixed 160 x 90 whatever the image's shape, so the crop is
    // worked out from the image's own shape, as a share of the grid
    const double imgAspect = m_aspect, scrAspect = double(screenW) / screenH;
    double sx0 = 0, sy0 = 0, sw = gw, sh = gh;              // the visible part of the image
    if (imgAspect > scrAspect) { sw = gw * scrAspect / imgAspect; sx0 = (gw - sw) / 2; }
    else { sh = gh * imgAspect / scrAspect; sy0 = (gh - sh) / 2; }
    std::vector<double> busy(size_t(cw) * ch);
    for (int y = 0; y < ch; ++y)
        for (int x = 0; x < cw; ++x) {
            const int ix = std::min(gw - 1, int(sx0 + (x + 0.5) * sw / cw));
            const int iy = std::min(gh - 1, int(sy0 + (y + 0.5) * sh / ch));
            busy[size_t(y) * cw + x] = m_detail.constScanLine(iy)[ix];
        }
    // summed-area table for fast window sums
    std::vector<double> sat(size_t(cw + 1) * (ch + 1), 0.0);
    for (int y = 0; y < ch; ++y)
        for (int x = 0; x < cw; ++x)
            sat[size_t(y + 1) * (cw + 1) + x + 1] = busy[size_t(y) * cw + x]
                + sat[size_t(y) * (cw + 1) + x + 1] + sat[size_t(y + 1) * (cw + 1) + x] - sat[size_t(y) * (cw + 1) + x];
    auto sum = [&](int x0, int y0, int x1, int y1) {       // [x0, x1) x [y0, y1)
        return sat[size_t(y1) * (cw + 1) + x1] - sat[size_t(y0) * (cw + 1) + x1]
             - sat[size_t(y1) * (cw + 1) + x0] + sat[size_t(y0) * (cw + 1) + x0];
    };
    const double px = double(cw) / screenW;                // grid cells per screen pixel
    std::vector<QRect> taken;
    for (const QVariant &sv : sizes) {
        const QVariantList wh = sv.toList();
        const int w = wh.value(0).toInt(), h = wh.value(1).toInt();
        const int ww = std::max(1, int(std::ceil(w * px))), wh2 = std::max(1, int(std::ceil(h * px)));
        const int xMin = int(std::ceil(margin * px)), xMax = cw - int(std::ceil(margin * px)) - ww;
        const int yMin = int(std::ceil(top * px)), yMax = ch - int(std::ceil(bottom * px)) - wh2;
        double bestScore = 1e18; int bx = -1, by = -1;
        for (int y = yMin; y <= yMax; ++y)
            for (int x = xMin; x <= xMax; ++x) {
                const QRect r(int(x / px), int(y / px), w, h);
                bool clash = false;
                for (const QRect &t : taken)
                    if (r.adjusted(-24, -24, 24, 24).intersects(t)) { clash = true; break; }
                if (clash) continue;
                // the widget's own area, plus a ring around it at half weight,
                // so it isn't pressed right up against something busy
                const int rx0 = std::max(0, x - 2), ry0 = std::max(0, y - 2);
                const int rx1 = std::min(cw, x + ww + 2), ry1 = std::min(ch, y + wh2 + 2);
                const double inner = sum(x, y, x + ww, y + wh2) / double(ww * wh2);
                const double ringArea = double((rx1 - rx0) * (ry1 - ry0) - ww * wh2);
                const double ring = ringArea > 0 ? (sum(rx0, ry0, rx1, ry1) - sum(x, y, x + ww, y + wh2)) / ringArea : inner;
                const double score = inner + 0.5 * ring;
                if (score < bestScore) { bestScore = score; bx = x; by = y; }
            }
        if (bx < 0) { out.append(QVariant()); continue; }   // no room left
        const QRect placed(int(std::round(bx / px)), int(std::round(by / px)), w, h);
        taken.push_back(placed);
        // how busy the spot is, 0 (flat) to 255: the shell only moves a
        // widget to somewhere genuinely calm
        out.append(QVariantMap{ { "x", placed.x() }, { "y", placed.y() }, { "busy", bestScore / 1.5 } });
    }
    return out;
}

double ArtColors::lightnessOf(const QImage &src) {
    const QImage img = src.scaled(64, 64, Qt::IgnoreAspectRatio, Qt::FastTransformation)
                          .convertToFormat(QImage::Format_ARGB32);
    // average relative luminance (linear light), then CIE L*.  The strip
    // along the top, where the bar sits, counts for more (a third of the
    // answer): a bright sky behind a dark bar looks wrong even when the
    // rest of the picture is dark.
    auto lin = [](double c) { c /= 255.0; return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); };
    double sum = 0, top = 0; int n = 0, nt = 0;
    const int strip = std::max(1, img.height() / 10);
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QRgb p = line[x];
            const double v = 0.2126 * lin(qRed(p)) + 0.7152 * lin(qGreen(p)) + 0.0722 * lin(qBlue(p));
            sum += v; ++n;
            if (y < strip) { top += v; ++nt; }
        }
    }
    if (!n) return -1;
    const double Y = nt ? (2.0 / 3.0) * (sum / n) + (1.0 / 3.0) * (top / nt) : sum / n;
    return Y > 0.008856 ? 116.0 * std::cbrt(Y) - 16.0 : 903.3 * Y;
}

QColor ArtColors::seedOf(const QImage &src) {
    const QImage img = src.scaled(64, 64, Qt::IgnoreAspectRatio, Qt::FastTransformation)
                          .convertToFormat(QImage::Format_ARGB32);
    // 36 hue families, 10 degrees each: weight, and weighted colour sums
    double weight[36] = {0}, sr[36] = {0}, sg[36] = {0}, sb[36] = {0};
    double total = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QRgb p = line[x];
            if (qAlpha(p) < 128) continue;
            ++total;
            const QColor c(p);
            const double s = c.hsvSaturationF(), v = c.valueF();
            if (s < 0.18 || v < 0.14) continue;                  // greys and near-black
            // rich and mid-bright counts most: what the eye picks out
            const double w = s * s * (1.0 - std::fabs(v - 0.7));
            const int h = c.hsvHue();
            if (h < 0) continue;
            const int b = (h / 10) % 36;
            weight[b] += w;
            sr[b] += w * qRed(p); sg[b] += w * qGreen(p); sb[b] += w * qBlue(p);
        }
    }
    if (total <= 0) return QColor();
    // the strongest family, with its neighbours (a hue near an edge)
    int best = 0;
    double bestW = -1;
    for (int b = 0; b < 36; ++b) {
        const double w = weight[(b + 35) % 36] * 0.5 + weight[b] + weight[(b + 1) % 36] * 0.5;
        if (w > bestW) { bestW = w; best = b; }
    }
    // too little colour to be worth using: keep the theme's own
    if (weight[best] / total < 0.012) return QColor();
    const double w = weight[best];
    return QColor(int(sr[best] / w), int(sg[best] / w), int(sb[best] / w));
}

void ArtColors::apply(const QColor &seed) {
    const float h = seed.hslHueF() < 0 ? 0.f : seed.hslHueF();
    const float s = qBound(0.30f, seed.hslSaturationF(), 0.85f);
    auto hsl = [h](float sat, float light) { return QColor::fromHslF(h, qBound(0.f, sat, 1.f), qBound(0.f, light, 1.f)); };
    if (m_dark) {
        m_accent      = hsl(qMin(s, 0.72f), 0.74f);
        m_onAccent    = hsl(s * 0.55f, 0.14f);
        m_container   = hsl(s * 0.55f, 0.28f);
        m_onContainer = hsl(s * 0.45f, 0.90f);
    } else {
        m_accent      = hsl(qMin(s, 0.75f), 0.40f);
        m_onAccent    = hsl(s * 0.25f, 0.98f);
        m_container   = hsl(s * 0.65f, 0.86f);
        m_onContainer = hsl(s * 0.60f, 0.16f);
    }
    m_seed = seed;
    m_valid = true;
    emit colorsChanged();
}


// ---------------------------------------------------------------------------
//   The colour a theme should be built from.
//
//   matugen (Material's own scoring) weighs how much of the picture a colour
//   covers and how vivid it is.  It can't tell a subject from its backdrop, so
//   a blue flower among leaves gives a green theme and pink blossoms against
//   the sky a teal one; it counts skin like anything else; and when there's
//   no colour at all it falls back to a stock blue.  This does, in OKLab
//   (perceptual colour):
//     1. the frame: uniform bands at the edges (letterboxing) don't count;
//     2. the subject: detail (edges, blurred into regions), colour that
//        stands out from the average, and how walled off a place is from the
//        picture's edges (a backdrop runs to them in one smooth piece) mark
//        where the eye goes;
//     3. skin: a narrow band of warm, modest colour counts for less, so a
//        portrait's theme comes from hair, eyes, clothes or light;
//     4. colour families: a hue histogram of the coloured pixels, weighted
//        by importance, says whether the picture has real colour at all;
//     5. no real colour: the picture's own faint tint, gently, or greys of
//        different lightness, unless a small vivid colour is clearly the
//        subject (a red cape on white).  Near-black and deep shadow don't
//        count against colour: a dark city with lit windows themes from the
//        windows, not the night;
//     6. the colours: the coloured pixels grouped into clusters, each shown
//        as its vivid core and scored on area, strength and how much it is
//        the subject (a quiet, dull backdrop counts for less, a vivid one
//        doesn't); the best is the main colour, the rest are offered to the
//        palette as the second and third.
//   Tested against matugen on 40 real wallpapers (portraits, anime,
//   landscapes, cities, flowers, paintings) before it went in; since then
//   against pywal, wallust and matugen on 47 more, and checked on 51 it was
//   never tuned on, by numbers and by a blind side-by-side.
// ---------------------------------------------------------------------------
ArtColors::Smart ArtColors::smartAnalyse(const QImage &src) {
    Smart res;
    if (src.isNull()) return res;
    // 384 pixels wide: small bright details (a few red poppies in a dark
    // scene) keep their colour instead of blending into their surroundings
    const int W = 384, Hh = std::max(1, int(std::lround(double(W) * src.height() / src.width())));
    const QImage img = src.scaled(W, Hh, Qt::IgnoreAspectRatio, Qt::SmoothTransformation).convertToFormat(QImage::Format_RGB32);
    const size_t N = size_t(W) * Hh;
    std::vector<double> L(N), A(N), B(N), C(N), Hue(N);
    for (int y = 0; y < Hh; ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < W; ++x) {
            const Lab o = toOklab(line[x]);
            const size_t i = size_t(y) * W + x;
            L[i] = o.L; A[i] = o.A; B[i] = o.B;
            C[i] = std::hypot(o.A, o.B);
            Hue[i] = std::fmod(std::atan2(o.B, o.A) * 180.0 / M_PI + 360.0, 360.0);
        }
    }
    // 1. the frame
    std::vector<char> keep(N, 1);
    auto stdOf = [&](bool row, int k) {
        const int n = row ? W : Hh; double s = 0, s2 = 0;
        for (int j = 0; j < n; ++j) { const double v = row ? L[size_t(k) * W + j] : L[size_t(j) * W + k]; s += v; s2 += v * v; }
        const double m = s / n; return std::sqrt(std::max(0.0, s2 / n - m * m));
    };
    {
        int i = 0; while (i < Hh / 4 && stdOf(true, i) < 0.012) ++i;
        int j = Hh - 1; while (j > 3 * Hh / 4 && stdOf(true, j) < 0.012) --j;
        for (int y = 0; y < Hh; ++y) if (y < i || y > j) for (int x = 0; x < W; ++x) keep[size_t(y) * W + x] = 0;
        i = 0; while (i < W / 4 && stdOf(false, i) < 0.012) ++i;
        j = W - 1; while (j > 3 * W / 4 && stdOf(false, j) < 0.012) --j;
        for (int x = 0; x < W; ++x) if (x < i || x > j) for (int y = 0; y < Hh; ++y) keep[size_t(y) * W + x] = 0;
    }
    // 2. the subject
    std::vector<double> grad(N);
    for (int y = 0; y < Hh; ++y)
        for (int x = 0; x < W; ++x) {
            auto at = [&](int xx, int yy) { return L[size_t(yy) * W + xx]; };
            const double gx = x == 0 ? at(1, y) - at(0, y) : x == W - 1 ? at(W - 1, y) - at(W - 2, y) : (at(x + 1, y) - at(x - 1, y)) / 2;
            const double gy = y == 0 ? at(x, std::min(1, Hh - 1)) - at(x, 0) : y == Hh - 1 ? at(x, Hh - 1) - at(x, Hh - 2) : (at(x, y + 1) - at(x, y - 1)) / 2;
            grad[size_t(y) * W + x] = std::hypot(gx, gy);
        }
    const int r = std::max(2, W / 32);
    const std::vector<double> detail = boxBlur(grad, W, Hh, r);
    double kc = 0, mA = 0, mB = 0, mL = 0;
    for (size_t i = 0; i < N; ++i) if (keep[i]) { kc++; mA += A[i]; mB += B[i]; mL += L[i]; }
    if (kc <= 0) return res;
    mA /= kc; mB /= kc; mL /= kc;
    std::vector<double> standRaw(N);
    for (size_t i = 0; i < N; ++i)
        standRaw[i] = std::sqrt((A[i] - mA) * (A[i] - mA) + (B[i] - mB) * (B[i] - mB) + 0.3 * (L[i] - mL) * (L[i] - mL));
    const std::vector<double> stand = boxBlur(standRaw, W, Hh, r);
    auto normed = [&](const std::vector<double> &x) {
        std::vector<double> v; v.reserve(N);
        for (size_t i = 0; i < N; ++i) if (keep[i]) v.push_back(x[i]);
        const double lo = percentile(v, 5), hi = percentile(v, 97);
        std::vector<double> out(N);
        for (size_t i = 0; i < N; ++i) out[i] = std::clamp((x[i] - lo) / std::max(1e-6, hi - lo), 0.0, 1.0);
        return out;
    };
    const std::vector<double> nd = normed(detail), ns = normed(stand);
    // How cut off each place is from the picture's edges: a backdrop (sky,
    // wall, sea) runs to the edges in one smooth piece, while a subject is
    // walled off from them by its own outline.  On a 4x coarser grid, the
    // cheapest path to any edge, where each step costs how much the colour
    // changes (less a little, so grain and texture are free).  Lightbulbs on
    // a smooth grey-blue wall: the wall reaches the edges for nothing, the
    // glowing filaments only across the glass.
    std::vector<double> geo(N, 0.0);
    {
        const int gw = std::max(2, W / 4), gh = std::max(2, Hh / 4);
        const size_t G = size_t(gw) * gh;
        std::vector<double> gl(G, 0), ga(G, 0), gb(G, 0), gn(G, 0);
        for (int y = 0; y < Hh; ++y)
            for (int x = 0; x < W; ++x) {
                const size_t i = size_t(y) * W + x;
                if (!keep[i]) continue;
                const size_t g = size_t(std::min(gh - 1, y * gh / Hh)) * gw + std::min(gw - 1, x * gw / W);
                gl[g] += L[i]; ga[g] += A[i]; gb[g] += B[i]; gn[g] += 1;
            }
        std::vector<char> live(G, 0);
        for (size_t g = 0; g < G; ++g) if (gn[g] > 0) { gl[g] /= gn[g]; ga[g] /= gn[g]; gb[g] /= gn[g]; live[g] = 1; }
        std::vector<double> dist(G, 1e9);
        using QE = std::pair<double, size_t>;
        std::priority_queue<QE, std::vector<QE>, std::greater<QE>> q;
        // the edges: live cells on the grid's border or next to the frame
        for (int y = 0; y < gh; ++y)
            for (int x = 0; x < gw; ++x) {
                const size_t g = size_t(y) * gw + x;
                if (!live[g]) continue;
                bool edge = x == 0 || y == 0 || x == gw - 1 || y == gh - 1;
                if (!edge) edge = !live[g - 1] || !live[g + 1] || !live[g - gw] || !live[g + gw];
                if (edge) { dist[g] = 0; q.push({ 0, g }); }
            }
        while (!q.empty()) {
            const auto [d, g] = q.top(); q.pop();
            if (d > dist[g]) continue;
            const int x = int(g % gw), y = int(g / gw);
            const int nx[4] = { x - 1, x + 1, x, x }, ny[4] = { y, y, y - 1, y + 1 };
            for (int k = 0; k < 4; ++k) {
                if (nx[k] < 0 || ny[k] < 0 || nx[k] >= gw || ny[k] >= gh) continue;
                const size_t h = size_t(ny[k]) * gw + nx[k];
                if (!live[h]) continue;
                const double dl = gl[h] - gl[g], da = ga[h] - ga[g], db = gb[h] - gb[g];
                const double step = std::max(0.0, std::sqrt(dl * dl + 2 * (da * da + db * db)) - 0.015);
                if (d + step < dist[h]) { dist[h] = d + step; q.push({ d + step, h }); }
            }
        }
        std::vector<double> dv;
        for (size_t g = 0; g < G; ++g) if (live[g]) dv.push_back(dist[g]);
        const double hi = std::max(1e-6, percentile(dv, 95));
        for (int y = 0; y < Hh; ++y)
            for (int x = 0; x < W; ++x) {
                const size_t g = size_t(std::min(gh - 1, y * gh / Hh)) * gw + std::min(gw - 1, x * gw / W);
                geo[size_t(y) * W + x] = live[g] ? std::min(1.0, dist[g] / hi) : 0;
            }
    }
    std::vector<double> sal(N), weight(N);
    for (size_t i = 0; i < N; ++i) {
        sal[i] = 0.35 * nd[i] + 0.35 * ns[i] + 0.30 * geo[i];
        weight[i] = keep[i] ? 0.3 + sal[i] : 0;
    }
    // 3. skin
    double wsum = 0, skinW = 0;
    for (size_t i = 0; i < N; ++i) {
        const bool skin = Hue[i] > 25 && Hue[i] < 85 && C[i] > 0.025 && C[i] < 0.13 && L[i] > 0.45 && L[i] < 0.92;
        wsum += weight[i]; if (skin) skinW += weight[i];
        if (skin) weight[i] *= 0.3;
    }
    res.skin = skinW / std::max(1e-9, wsum);
    // 4. colour families
    double total = 0, salTotal = 0, colW = 0;
    std::vector<char> coloured(N);
    const int bins = 72;
    std::vector<double> hist(bins, 0.0);
    for (size_t i = 0; i < N; ++i) {
        coloured[i] = C[i] > 0.03 && (L[i] > 0.2 || C[i] > 0.05);
        total += weight[i]; salTotal += weight[i] * sal[i];
        if (coloured[i]) { colW += weight[i]; hist[(int(Hue[i]) * bins / 360) % bins] += weight[i] * std::sqrt(C[i]); }
    }
    std::vector<double> sm(bins);
    const double kw[5] = { 1, 2, 3, 2, 1 };
    for (int i = 0; i < bins; ++i) { double s = 0; for (int d = -2; d <= 2; ++d) s += kw[d + 2] * hist[(i + d + bins) % bins]; sm[i] = s / 9.0; }
    // L/A/B/C: the whole family; vL/vA/vB: its vivid core, the most
    // saturated 30% of it by importance (what it's shown as): shadowed and
    // muddy pixels don't average a vivid colour down to brown, so a red
    // poppy stays red.  (The main colour itself comes from the clusters in
    // step 6; the families decide whether there's colour, and stand in when
    // there are no clusters.)
    struct Cand { double hue, share, L, A, B, C, subj, score, vL, vA, vB; };
    std::vector<Cand> cands;
    const double meanSal = salTotal / std::max(1e-9, total);
    for (int i = 0; i < bins; ++i) {
        if (sm[i] <= 0 || sm[i] < sm[(i + bins - 1) % bins] || sm[i] < sm[(i + 1) % bins]) continue;
        const double centre = (i + 0.5) * 360.0 / bins;
        double w = 0, wl = 0, wa = 0, wb = 0, wsal = 0;
        std::vector<std::pair<double, double>> members;        // (chroma, weight)
        for (size_t k = 0; k < N; ++k) {
            if (!coloured[k] || hueDist(Hue[k], centre) >= 22) continue;
            w += weight[k]; wl += weight[k] * L[k]; wa += weight[k] * A[k]; wb += weight[k] * B[k]; wsal += weight[k] * sal[k];
            members.emplace_back(C[k], weight[k]);
        }
        const double share = w / std::max(1e-9, total);
        if (share < 0.004 || w <= 0) continue;
        const double cL = wl / w, cA = wa / w, cB = wb / w, cC = std::hypot(cA, cB);
        const double subj = (wsal / w) / std::max(1e-9, meanSal);
        // the vivid core: members at or above the chroma where the most
        // saturated 30% (by weight) begins
        std::sort(members.begin(), members.end(), [](auto &a, auto &b) { return a.first > b.first; });
        double cum = 0, cut = members.empty() ? 0 : members.back().first;
        for (const auto &m : members) { cum += m.second; if (cum / w >= 0.30) { cut = m.first; break; } }
        double vw = 0, vl = 0, va = 0, vb = 0;
        for (size_t k = 0; k < N; ++k) {
            if (!coloured[k] || C[k] < cut || hueDist(Hue[k], centre) >= 22) continue;
            vw += weight[k]; vl += weight[k] * L[k]; va += weight[k] * A[k]; vb += weight[k] * B[k];
        }
        if (vw <= 0) { vw = w; vl = wl; va = wa; vb = wb; }
        // How strong the family looks: its average and its vivid core
        // together.  A glowing filament in grey glass, or a red sign on a
        // dusty street, is judged by its glow, not by the grey around it.
        const double strength = 0.5 * cC + 0.5 * std::hypot(va / vw, vb / vw);
        const double base = 0.55 * std::pow(std::min(1.0, share / 0.30), 0.7) + 0.45 * std::min(1.0, strength / 0.14);
        const double vivid = std::min(1.0, strength / 0.10);
        // standing out counts for up to twice as much, if it's a real colour;
        // sitting quietly behind everything counts against a dull colour (a
        // plain wall loses to the lights hanging in front of it, though with
        // nothing in front of it, it still leads); a vivid backdrop (a violet
        // night sky) is the picture's colour, and keeps its place
        const double mult = subj >= 1.0 ? 1.0 + (std::min(2.0, subj) - 1.0) * vivid
                                        : 1.0 - (1.0 - std::sqrt(std::max(0.4, subj))) * (1.0 - std::clamp((strength - 0.06) / 0.08, 0.0, 1.0));
        // a dull yellow-green (khaki, olive) reads as a muddy green in a
        // palette (Material avoids them too): it only leads if nothing else
        // represents the picture
        const double dislike = (centre >= 90 && centre <= 125 && strength < 0.10) ? 0.6 : 1.0;
        cands.push_back({ centre, share, cL, cA, cB, std::max(cC, strength), subj, base * mult * dislike, vl / vw, va / vw, vb / vw });
    }
    std::stable_sort(cands.begin(), cands.end(), [](const Cand &a, const Cand &b) { return a.score > b.score; });
    std::vector<Cand> merged;
    for (const Cand &c : cands) {
        bool far = true;
        for (const Cand &m : merged) if (hueDist(c.hue, m.hue) < 25) { far = false; break; }
        if (far) merged.push_back(c);
    }
    // the share of colour among what can carry colour: deep shadow and
    // near-black (a night sky, a dark room) can't, so a dark picture with
    // lit windows or neon counts those as most of its colour, instead of
    // its gloom outvoting them and the theme coming out black
    double canW = 0;
    for (size_t i = 0; i < N; ++i) if (coloured[i] || L[i] >= 0.22) canW += weight[i];
    const double colourShare = colW / std::max(1e-9, canW);
    bool vividSubject = false;
    for (const Cand &c : merged) if (c.C >= 0.06 && c.subj >= 1.3 && c.share >= 0.004) vividSubject = true;
    // 5. the backdrop's tone: the hue the large, quiet parts of the picture
    // lean to (a cream wall, a navy sky, a green forest), and how strongly.
    // Weighted towards the calm areas (the subject is the accent's job) and
    // by how coloured each pixel is, so a faint lean still shows.  A palette
    // from the picture tints its surfaces with it.
    {
        const int hb = 36;
        std::vector<double> bh(hb, 0.0);
        double bw = 0;
        for (size_t i = 0; i < N; ++i) {
            if (!keep[i]) continue;
            const double w = 1.2 - sal[i];
            bw += w;
            if (C[i] > 0.012) bh[(int(Hue[i]) * hb / 360) % hb] += w * C[i];
        }
        int peak = -1; double best = 0;
        for (int i = 0; i < hb; ++i) {
            const double v = bh[(i + hb - 1) % hb] + 2 * bh[i] + bh[(i + 1) % hb];
            if (v > best) { best = v; peak = i; }
        }
        if (peak >= 0 && bw > 0) {
            const double centre = (peak + 0.5) * 360.0 / hb;
            double mw = 0, ma = 0, mb = 0;
            for (size_t i = 0; i < N; ++i)
                if (keep[i] && C[i] > 0.012 && hueDist(Hue[i], centre) < 25) {
                    const double w = 1.2 - sal[i]; mw += w; ma += w * A[i]; mb += w * B[i];
                }
            if (mw > 0) {
                ma /= mw; mb /= mw;
                res.baseHue = std::fmod(std::atan2(mb, ma) * 180.0 / M_PI + 360.0, 360.0);
                // a lean shared by only part of the backdrop counts for less
                res.baseChroma = std::hypot(ma, mb) * std::sqrt(std::min(1.0, (mw / bw) / 0.5));
            }
        }
    }
    res.valid = true;
    auto lch = [](double l, double c, double h) {
        return fromOklab(l, c * std::cos(h * M_PI / 180.0), c * std::sin(h * M_PI / 180.0));
    };
    // 6. no real colour.  A faint tint still counts (autumn trees in fog, a
    // warm cast on a grey photo): the theme takes it, gently, instead of
    // going grey.  Only a picture with no lean at all gets greys, told apart
    // by how light they are.
    if (merged.empty() || (colourShare < 0.03 && !vividSubject)) {
        std::vector<std::pair<double, size_t>> byC;
        for (size_t i = 0; i < N; ++i) if (keep[i] && C[i] > 0.012) byC.emplace_back(C[i], i);
        std::sort(byC.begin(), byC.end(), [](auto &a, auto &b) { return a.first > b.first; });
        // the most coloured tenth of the picture (at most), and the hue most
        // of it shares (orange trees and a blue fog mustn't average to grey)
        const size_t take = std::min(byC.size(), std::max<size_t>(1, N / 10));
        std::vector<double> th(36, 0.0);
        for (size_t k = 0; k < take; ++k) { const size_t i = byC[k].second; th[(int(Hue[i]) / 10) % 36] += weight[i] * C[i]; }
        int tp = 0;
        for (int i = 1; i < 36; ++i)
            if (th[(i + 35) % 36] + 2 * th[i] + th[(i + 1) % 36] > th[(tp + 35) % 36] + 2 * th[tp] + th[(tp + 1) % 36]) tp = i;
        double tw = 0, tl = 0, ta = 0, tb = 0;
        for (size_t k = 0; k < take; ++k) {
            const size_t i = byC[k].second;
            if (hueDist(Hue[i], tp * 10 + 5) >= 25) continue;
            tw += weight[i]; tl += weight[i] * L[i]; ta += weight[i] * A[i]; tb += weight[i] * B[i];
        }
        const double tintC = tw > 0 ? std::hypot(ta / tw, tb / tw) : 0;
        if (tw > 0 && tintC >= 0.018 && double(byC.size()) / N >= 0.02) {
            const double h = std::fmod(std::atan2(tb / tw, ta / tw) * 180.0 / M_PI + 360.0, 360.0);
            const double c = std::clamp(tintC * 1.4, 0.04, 0.08), l = std::clamp(tl / tw, 0.55, 0.8);
            // all three in that tint, at different lightness: nothing the
            // picture doesn't have (a palette spaces them, as for greys)
            res.seed = lch(l, c, h);
            res.second = lch(std::min(0.9, l + 0.12), c, h);
            res.third = lch(std::max(0.4, l - 0.12), c, h);
            res.why = QStringLiteral("a faint tint");
        } else {
            // Black and white: greys, nothing the picture doesn't have (with
            // whatever whisper of tone it has).  A palette spaces them as far
            // apart in lightness as reading allows (paletteFor).
            const double c = std::min(0.012, std::hypot(mA, mB)), h = std::atan2(mB, mA) * 180.0 / M_PI;
            res.seed = lch(0.90, c, h);
            res.second = lch(0.78, c, h);
            res.third = lch(0.66, c, h);
            res.why = QStringLiteral("no strong colour");
        }
        return res;
    }
    // Every colour the picture has, found by grouping its coloured pixels
    // into clusters (k-means in OKLab, hue weighted over lightness), so a
    // colour counts even when it shares a hue family with another (a cream
    // backdrop and a yellow square, a blue and a violet) or covers only a
    // small, striking part of the picture.  The main colour is the one that
    // matters most; the second and third follow.  (Grouping only by hue
    // used to let a cream wall borrow the strength of a yellow square in
    // front of it.)
    // its coloured pixels into clusters (k-means in OKLab, hue weighted over
    // lightness), so a colour counts even when it shares a hue family with
    // another (a cream and a red dot, a blue and a violet) or covers only a
    // small, striking part of the picture.  Each cluster is shown as its
    // vivid core, like the main colour.  They're chosen one at a time for
    // how much they matter in the picture (area, how much they stand out,
    // strength) and how different they are from what's already chosen;
    // a colour too close to one already picked doesn't count.
    // (below:) Second and third: the picture's own other colours, found by grouping
    struct Clu { double L, A, B, C, share, subj, score, hue; };
    std::vector<Clu> clus;
    {
        std::vector<size_t> idx;
        const size_t stride = std::max<size_t>(1, N / 40000);
        for (size_t i = 0; i < N; i += stride) if (coloured[i] && weight[i] > 0) idx.push_back(i);
        // starting centres: one per 30-degree sector that has any colour
        std::vector<std::array<double, 3>> ctr;
        for (int sct = 0; sct < 12; ++sct) {
            double w = 0, l = 0, a = 0, b = 0;
            for (size_t i : idx) if (int(Hue[i] / 30) % 12 == sct) { w += weight[i]; l += weight[i] * L[i]; a += weight[i] * A[i]; b += weight[i] * B[i]; }
            if (w > 0) ctr.push_back({ l / w, a / w, b / w });
        }
        const size_t K = ctr.size();
        std::vector<int> lab(idx.size(), 0);
        auto dist = [&](size_t i, const std::array<double, 3> &c) {
            const double dl = L[i] - c[0], da = A[i] - c[1], db = B[i] - c[2];
            return 0.3 * dl * dl + 4 * (da * da + db * db);
        };
        for (int it = 0; it < 10 && K > 0; ++it) {
            for (size_t n = 0; n < idx.size(); ++n) {
                int bj = 0; double bd = 1e9;
                for (size_t j = 0; j < K; ++j) { const double d = dist(idx[n], ctr[j]); if (d < bd) { bd = d; bj = int(j); } }
                lab[n] = bj;
            }
            std::vector<std::array<double, 4>> acc(K, { 0, 0, 0, 0 });
            for (size_t n = 0; n < idx.size(); ++n) {
                const size_t i = idx[n]; auto &q = acc[lab[n]];
                q[0] += weight[i]; q[1] += weight[i] * L[i]; q[2] += weight[i] * A[i]; q[3] += weight[i] * B[i];
            }
            for (size_t j = 0; j < K; ++j) if (acc[j][0] > 0) ctr[j] = { acc[j][1] / acc[j][0], acc[j][2] / acc[j][0], acc[j][3] / acc[j][0] };
        }
        double sampled = 0;
        for (size_t i = 0; i < N; i += stride) sampled += weight[i];
        for (size_t j = 0; j < K; ++j) {
            std::vector<std::pair<double, size_t>> mem;
            double w = 0, ws = 0, wa = 0, wb = 0;
            for (size_t n = 0; n < idx.size(); ++n) if (lab[n] == int(j)) { const size_t i = idx[n]; mem.emplace_back(C[i], i); w += weight[i]; ws += weight[i] * sal[i]; wa += weight[i] * A[i]; wb += weight[i] * B[i]; }
            if (w <= 0) continue;
            // its vivid core: the most saturated 30% of it
            std::sort(mem.begin(), mem.end(), [](auto &a, auto &b) { return a.first > b.first; });
            double cw = 0, l = 0, a = 0, b = 0;
            for (const auto &m : mem) {
                const size_t i = m.second;
                cw += weight[i]; l += weight[i] * L[i]; a += weight[i] * A[i]; b += weight[i] * B[i];
                if (cw >= 0.3 * w) break;
            }
            Clu c{ l / cw, a / cw, b / cw, std::hypot(a / cw, b / cw), w / std::max(1e-9, sampled),
                   (ws / w) / std::max(1e-9, meanSal), 0, std::fmod(std::atan2(b / cw, a / cw) * 180.0 / M_PI + 360.0, 360.0) };
            // scored as the hue families are (see above): area, strength (its
            // average and its vivid core together), and standing out
            const double strength = 0.5 * std::hypot(wa / w, wb / w) + 0.5 * c.C;
            const double vivid = std::min(1.0, strength / 0.10);
            const double mult = c.subj >= 1.0 ? 1.0 + (std::min(2.0, c.subj) - 1.0) * vivid
                                              : 1.0 - (1.0 - std::sqrt(std::max(0.4, c.subj))) * (1.0 - std::clamp((strength - 0.06) / 0.08, 0.0, 1.0));
            const double dislike = (c.hue >= 90 && c.hue <= 125 && strength < 0.10) ? 0.6 : 1.0;
            c.score = (0.55 * std::pow(std::min(1.0, c.share / 0.15), 0.6) + 0.45 * std::min(1.0, strength / 0.14)) * mult * dislike;
            // a real share of it, or a small, strong spot of colour that stands out
            // (the red dot on a cream-and-black logo)
            const bool real = (c.C >= 0.035 && c.share >= 0.004) || (c.C >= 0.12 && c.share >= 0.0008);
            if (real) clus.push_back(c);
            // quieter ones (a dusty blue beside a navy) only as the palette's
            // second choice, before colours the picture doesn't have
            if (real || (c.C >= 0.02 && c.share >= 0.02))
                res.others.append({ fromOklab(c.L, c.A, c.B), real ? c.score : 0.3 * c.score,
                                    std::pow(std::min(1.0, c.share / 0.15), 0.6) * std::min(1.0, strength / 0.06) });
        }
    }
    // the main colour: the cluster that matters most (the hue family's pick
    // when there are none)
    struct Main { double hue, vL, vA, vB, subj; };
    Main p{ merged.front().hue, merged.front().vL, merged.front().vA, merged.front().vB, merged.front().subj };
    {
        const Clu *top = nullptr;
        for (const Clu &c : clus) if (!top || c.score > top->score) top = &c;
        if (top) p = { top->hue, top->L, top->A, top->B, top->subj };
    }
    res.seed = fromOklab(p.vL, p.vA, p.vB);
    // how different two colours look as accents: mostly hue and strength,
    // since making them readable brings their lightness together
    auto sep = [](double l1, double a1, double b1, double l2, double a2, double b2) {
        return std::sqrt((a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2) + 0.25 * (l1 - l2) * (l1 - l2));
    };
    std::vector<std::array<double, 3>> chosen{ { p.vL, p.vA, p.vB } };
    std::vector<QColor> found;
    std::vector<double> used{ p.hue };
    while (found.size() < 2) {
        const Clu *best = nullptr; double bs = 0;
        for (const Clu &c : clus) {
            double d = 1e9;
            for (const auto &q : chosen) d = std::min(d, sep(c.L, c.A, c.B, q[0], q[1], q[2]));
            if (d < 0.08) continue;
            const double v = c.score * std::min(1.0, d / 0.14);
            if (v > bs) { bs = v; best = &c; }
        }
        if (!best) break;
        chosen.push_back({ best->L, best->A, best->B });
        found.push_back(fromOklab(best->L, best->A, best->B));
        used.push_back(std::fmod(std::atan2(best->B, best->A) * 180.0 / M_PI + 360.0, 360.0));
    }
    // Fewer than three real colours: the main colour's own neighbours on
    // the colour wheel, so the three always tell apart instead of falling
    // back to greys or copies.
    auto freeHue = [&](double h) { for (double u : used) if (hueDist(h, u) < 32) return false; return true; };
    // neighbours: 40 degrees each way, stepping past dull ochre, khaki and
    // olive, which read as mud in a palette
    const double pc = std::max(0.05, std::hypot(p.vA, p.vB));
    for (double turn : { 40.0, -40.0, 75.0, -75.0, 110.0, -110.0 }) {
        if (found.size() >= 2) break;
        const double h = std::fmod(p.hue + turn + 360.0, 360.0);
        const double c = pc * (found.empty() ? 0.85 : 0.7);
        if (!freeHue(h) || (h >= 75 && h <= 135 && c < 0.11)) continue;
        found.push_back(lch(p.vL, c, h));
        used.push_back(h);
    }
    res.second = found.size() > 0 ? found[0] : res.seed;
    res.third = found.size() > 1 ? found[1] : res.second;
    res.why = p.subj > 1.15 ? QStringLiteral("the subject") : p.subj < 0.85 ? QStringLiteral("the backdrop")
                            : QStringLiteral("the whole picture");
    return res;
}

// ---------------------------------------------------------------------------
// The whole theme from the picture (Settings > Theme > Palette: "From the
// picture").  Built on smartAnalyse's reading:
//   surfaces   in the backdrop's own tone (a cream wall gives warm greys, a
//              navy sky blue-black ones), at Material's tones for each role,
//              so every app's layout reads as before.  How strongly they're
//              tinted follows how strongly the backdrop leans, capped so a
//              surface never turns into a colour.
//   text       the same tone, nearly neutral; outlines a little stronger
//   accents    the picture's three colours, each brought just light (dark,
//              on a light theme) enough to read at 4.5:1 on the background
//              and 3:1 on the bar's raised pills, keeping its hue and as much
//              of its strength as the screen can show, then kept visibly
//              apart from each other (a graph's lines, a terminal's colours)
// Everything in OKLab, where equal steps look equal: lightening a colour
// there doesn't wash it out the way it does in HSL.
// ---------------------------------------------------------------------------
namespace {
// linear sRGB from OKLab; false when it's outside what a screen can show
bool oklabLinear(double L, double A, double B, double rgb[3]) {
    const double l = std::pow(L + 0.3963377774 * A + 0.2158037573 * B, 3);
    const double m = std::pow(L - 0.1055613458 * A - 0.0638541728 * B, 3);
    const double s = std::pow(L - 0.0894841775 * A - 1.2914855480 * B, 3);
    rgb[0] = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
    rgb[1] = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
    rgb[2] = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;
    const double e = 1e-4;
    return rgb[0] >= -e && rgb[0] <= 1 + e && rgb[1] >= -e && rgb[1] <= 1 + e && rgb[2] >= -e && rgb[2] <= 1 + e;
}
// a colour by lightness, chroma and hue, its chroma reduced (hue and
// lightness kept) until a screen can show it
QColor lchColour(double L, double C, double h) {
    L = std::clamp(L, 0.0, 1.0);
    const double ca = std::cos(h * M_PI / 180.0), sa = std::sin(h * M_PI / 180.0);
    double rgb[3];
    if (!oklabLinear(L, C * ca, C * sa, rgb)) {
        double lo = 0, hi = C;
        for (int i = 0; i < 24; ++i) { const double mid = (lo + hi) / 2; (oklabLinear(L, mid * ca, mid * sa, rgb) ? lo : hi) = mid; }
        C = lo;
    }
    return fromOklab(L, C * ca, C * sa);
}
double relLum(const QColor &c) {
    auto f = [](int v) { const double x = v / 255.0; return x <= 0.04045 ? x / 12.92 : std::pow((x + 0.055) / 1.055, 2.4); };
    return 0.2126 * f(c.red()) + 0.7152 * f(c.green()) + 0.0722 * f(c.blue());
}
double contrastOf(const QColor &a, const QColor &b) {
    const double x = relLum(a), y = relLum(b);
    return (std::max(x, y) + 0.05) / (std::min(x, y) + 0.05);
}
// Material's tones are CIE L* (0 black, 100 white): the OKLab lightness
// that gives this hue and chroma that tone
QColor atTone(double tone, double C, double h) {
    const double y = tone > 8 ? std::pow((tone + 16) / 116.0, 3) : tone / 903.3;
    double lo = 0, hi = 1;
    for (int i = 0; i < 30; ++i) { const double mid = (lo + hi) / 2; (relLum(lchColour(mid, C, h)) < y ? lo : hi) = mid; }
    return lchColour((lo + hi) / 2, C, h);
}
struct LCh { double L, C, h; };
LCh lchOf(const QColor &c) {
    const Lab o = toOklab(c.rgb());
    return { o.L, std::hypot(o.A, o.B), std::fmod(std::atan2(o.B, o.A) * 180.0 / M_PI + 360.0, 360.0) };
}
double deltaE(const QColor &a, const QColor &b) {
    const Lab x = toOklab(a.rgb()), y = toOklab(b.rgb());
    return std::sqrt((x.L - y.L) * (x.L - y.L) + (x.A - y.A) * (x.A - y.A) + (x.B - y.B) * (x.B - y.B));
}
// the colour lightened (darkened on a light theme) in steps until it reads
// at `ratio` on bg and 3:1 on raised (the bar's pills), hue kept
QColor readableOn(const QColor &c, const QColor &bg, const QColor &raised, double ratio, bool dark, double ratioRaised = 3.0) {
    const LCh o = lchOf(c);
    QColor out = lchColour(o.L, o.C, o.h);
    for (double L = o.L; L >= 0 && L <= 1; L += dark ? 0.005 : -0.005) {
        out = lchColour(L, o.C, o.h);
        if (contrastOf(out, bg) >= ratio && contrastOf(out, raised) >= ratioRaised) break;
    }
    // A colour that already reads easily but is close to the text colour
    // (deep shadow purple on a light theme, a near-white on a dark one) is
    // brought back towards the middle as far as it still reads: an accent
    // that looks like the text isn't one.
    const double far = dark ? 0.90 : 0.42;
    const LCh n = lchOf(out);
    if (dark ? n.L > far : n.L < far) {
        for (double L = far; dark ? L <= n.L : L >= n.L; L += dark ? 0.005 : -0.005) {
            const QColor t = lchColour(L, n.C, n.h);
            if (contrastOf(t, bg) >= ratio && contrastOf(t, raised) >= ratioRaised) { out = t; break; }
        }
    }
    return out;
}
}

QVariantMap ArtColors::paletteFor(const Smart &s0, bool dark, double contrast, const QVariantMap &studio) {
    QVariantMap m;
    if (!s0.valid || !s0.seed.isValid()) return m;
    // Theme Studio (Settings > Theme Studio): any of the three accents
    // picked by hand (from the picture's colours), how strong the accents
    // are, and how strongly the backgrounds are tinted.  Empty: automatic.
    auto pick = [&](const char *k) {
        const QString v = studio.value(QString::fromLatin1(k)).toString();
        return QColor::isValidColorName(v) && v.startsWith(QLatin1Char('#')) ? QColor(v) : QColor();
    };
    const QColor pickMain = pick("main"), pickSecond = pick("second"), pickThird = pick("third"), pickBase = pick("base");
    const double strength = std::clamp(studio.value(QStringLiteral("strength"), 1.0).toDouble(), 0.5, 1.6);
    const double tint = std::clamp(studio.value(QStringLiteral("tint"), 1.0).toDouble(), 0.0, 2.5);
    // stronger or softer: the same colour with its chroma scaled
    auto adj = [&](const QColor &c) {
        if (std::fabs(strength - 1.0) < 1e-3 || !c.isValid()) return c;
        const LCh o = lchOf(c);
        return lchColour(o.L, o.C * strength, o.h);
    };
    Smart s = s0;
    s.seed = adj(pickMain.isValid() ? pickMain : s0.seed);
    s.second = adj(s0.second);
    s.third = adj(s0.third);
    for (Other &o : s.others) o.colour = adj(o.colour);
    const LCh seed = lchOf(s.seed);
    // the surfaces' tone: the backdrop's, or (when it has none) a whisper
    // of the main colour, as Material does
    // (or the tone picked for them in Theme Studio)
    double baseHue = s.baseHue, baseChroma = s.baseChroma;
    if (pickBase.isValid()) { const LCh b = lchOf(pickBase); baseHue = b.h; baseChroma = b.C; }
    const bool leans = baseChroma >= 0.01;
    const double h = leans ? baseHue : seed.h;
    const double cn = std::min(0.045, tint * (leans ? std::clamp(baseChroma * (dark ? 0.30 : 0.35), 0.004, dark ? 0.020 : 0.028)
                                                    : std::min(0.006, seed.C * 0.1)));
    const double cv = std::min(0.035, cn * 1.5 + 0.004);          // the "variant" roles, a little stronger
    struct Role { const char *name; double darkTone, lightTone, chroma; };
    const Role roles[] = {
        { "surface", 6, 98, cn }, { "surface_dim", 6, 87, cn }, { "surface_bright", 24, 98, cn },
        { "surface_container_lowest", 4, 100, cn }, { "surface_container_low", 10, 96, cn },
        { "surface_container", 12, 94, cn }, { "surface_container_high", 17, 92, cn },
        { "surface_container_highest", 22, 90, cn }, { "surface_variant", 30, 90, cv },
        { "on_surface", 90, 10, cn * 0.6 }, { "on_surface_variant", 80, 30, cv },
        { "outline", 60, 50, cv }, { "outline_variant", 30, 80, cv },
        { "inverse_surface", 90, 20, cn * 0.6 }, { "inverse_on_surface", 20, 95, cn * 0.6 },
    };
    QHash<QString, QColor> col;
    // Contrast: accents read at 4.5:1 normally, from 3:1 (softer) to 7:1
    // (stronger), on the background, and half a step more on the raised
    // cards and pills, where the small labels sit (they read dim at 3:1, and
    // still a little at 4.5:1, in a blind side-by-side).  Text and
    // outlines move further from the background, or closer.
    contrast = std::clamp(contrast, -1.0, 1.0);
    const double ratio = contrast >= 0 ? 4.5 + 2.5 * contrast : 4.5 + 1.5 * contrast;
    const double ratioRaised = ratio + 0.5;     // small labels sit on the pills: a little more there
    const double push = 6 * contrast;          // tones further from (or nearer to) the background
    for (const Role &r : roles) {
        // the surfaces stay put; what sits on them moves with the contrast
        const bool onTop = std::strncmp(r.name, "on_", 3) == 0 || std::strncmp(r.name, "outline", 7) == 0;
        const double t = dark ? r.darkTone + (onTop ? push : 0) : r.lightTone - (onTop ? push : 0);
        col.insert(QString::fromLatin1(r.name), atTone(std::clamp(t, 0.0, 100.0), r.chroma, h));
    }
    const QColor bg = col.value(QStringLiteral("surface")), raised = col.value(QStringLiteral("surface_container_high"));
    const QColor fg = col.value(QStringLiteral("on_surface"));
    auto rd = [&](const QColor &c) { return readableOn(c, bg, raised, ratio, dark, ratioRaised); };
    // an accent too like the text colour (a near-white on a dark theme) reads
    // as plain text, not as a colour: it doesn't count as a second or third
    auto likeText = [&](const QColor &c) { return deltaE(c, fg) < 0.10; };
    // the three accents, readable, then apart: a colour too like one before
    // it turns away on the wheel (or, with no colour to turn, steps in
    // lightness) until it's clearly its own
    QColor acc[3] = { rd(s.seed), rd(s.second), rd(s.third) };
    // slots picked by hand in Theme Studio: kept as picked (made readable);
    // the automatic ones are chosen around them
    const bool fixedSlot[3] = { false, pickSecond.isValid(), pickThird.isValid() };
    if (fixedSlot[1]) acc[1] = rd(adj(pickSecond));
    if (fixedSlot[2]) acc[2] = rd(adj(pickThird));
    std::vector<int> filled{ 0 };
    for (int i = 1; i < 3; ++i) if (fixedSlot[i]) filled.push_back(i);
    auto isFilled = [&](int i) { return std::find(filled.begin(), filled.end(), i) != filled.end(); };
    // A black-and-white picture: three greys (its own whisper of tone); one
    // with only a faint tint: three of that tint.  As far apart in lightness
    // as the rules allow: the main colour (a pill, never text) next to the
    // text colour, the second just far enough from the text not to look like
    // it, the third as far the other way as still reads on the pills.
    const bool greys = s.why == QLatin1String("no strong colour") || s.why == QLatin1String("a faint tint");
    if (greys) {
        const LCh g = lchOf(s.seed), t = lchOf(fg);
        // the lightness where a grey stops reading (bisected)
        double lo = 0, hi = 1;
        for (int k = 0; k < 30; ++k) {
            const double mid = (lo + hi) / 2;
            const QColor c = lchColour(mid, g.C, g.h);
            const bool reads = contrastOf(c, bg) >= ratio && contrastOf(c, raised) >= ratioRaised;
            if (dark) (reads ? hi : lo) = mid; else (reads ? lo : hi) = mid;
        }
        const double edge = dark ? hi + 0.005 : lo - 0.005;           // the last lightness that reads
        const double nearText = dark ? t.L - 0.105 : t.L + 0.105;      // closest a label may come to the text
        // (the room between the text and the edge of reading fits only two
        // steps, so the main colour takes the place beside the text)
        if (!pickMain.isValid())
            acc[0] = lchColour(dark ? std::min(0.99, t.L + 0.04) : std::max(0.0, t.L - 0.04), g.C, g.h);
        if (!fixedSlot[1]) acc[1] = lchColour(nearText, g.C, g.h);
        if (!fixedSlot[2]) acc[2] = lchColour(edge, g.C, g.h);
    }
    // The second and third chosen again now the background is known: of the
    // picture's own colours, the ones that matter most and still look
    // clearly different once made readable (two blues can come out alike
    // when both are lightened).  Only when the picture has too few does a
    // neighbour of the main colour (smartAnalyse's fallback) stay.
    if (!greys) {
        // each colour's worth: half how much it matters as an accent, half how
        // much of the picture it stands for; less the more it has to change to
        // be readable (a deep teal lightened into a dull one is a poorer
        // likeness than the bright cyan beside it, shown as it is)
        std::vector<std::pair<QColor, double>> pool;
        for (const Other &o : s.others) {
            const QColor r = rd(o.colour);
            pool.emplace_back(r, (0.5 * o.score + 0.5 * o.area) / (1.0 + 4.0 * deltaE(r, o.colour)));
        }
        for (int slot = 1; slot < 3; ++slot) {
            if (isFilled(slot)) continue;
            int bi = -1; double bv = 0;
            for (size_t k = 0; k < pool.size(); ++k) {
                double d = 1e9;
                double dh = 180;
                const LCh pk = lchOf(pool[k].first);
                for (int j : filled) {
                    d = std::min(d, deltaE(pool[k].first, acc[j]));
                    const LCh aj = lchOf(acc[j]);
                    if (pk.C >= 0.03 && aj.C >= 0.03) dh = std::min(dh, hueDist(pk.h, aj.h));
                }
                if (d < 0.09 || likeText(pool[k].first)) continue;
                // a different hue counts for more than a lighter or duller
                // version of one already chosen (violet beside blue beats a
                // slate blue)
                const double v = pool[k].second * std::min(1.0, d / 0.15) * (0.45 + 0.55 * std::min(1.0, dh / 45.0));
                if (v > bv) { bv = v; bi = int(k); }
            }
            if (bi < 0) continue;
            acc[slot] = pool[size_t(bi)].first;
            filled.push_back(slot);
        }
        // a slot left over: a lighter or deeper tone of a colour already
        // chosen, as the picture itself has (a pale sky over a deep blue sea)
        for (int slot = 1; slot < 3; ++slot) {
            if (isFilled(slot)) continue;
            bool got = false;
            const std::vector<int> have = filled;
            for (int j : have) {
                if (got) break;
                const LCh o = lchOf(acc[j]);
                if (o.C < 0.06) continue;           // a pale cream's tones all look alike
                for (double step : { 0.16, -0.16, 0.24, -0.24 }) {
                    const double L = o.L + (dark ? step : -step);
                    if (dark ? (L > 0.9 || L < 0.3) : (L < 0.3 || L > 0.75)) continue;
                    const QColor t = lchColour(L, o.C, o.h);
                    bool ok = contrastOf(t, bg) >= ratio && contrastOf(t, raised) >= ratioRaised;
                    for (int k : have) if (ok && deltaE(t, acc[k]) < 0.09) ok = false;
                    if (likeText(t)) ok = false;
                    if (ok) { acc[slot] = t; got = true; break; }
                }
            }
            if (got) filled.push_back(slot);
        }
        // still left over: smartAnalyse's choice (its neighbour of the main
        // colour), made readable: the one most unlike those chosen
        std::vector<QColor> spare{ rd(s.second), rd(s.third) };
        for (int slot = 1; slot < 3; ++slot) {
            if (isFilled(slot)) continue;
            auto apart = [&](const QColor &c) { double d = 1e9; for (int j : filled) d = std::min(d, deltaE(c, acc[j])); return d; };
            const size_t bi = spare.size() > 1 && apart(spare[1]) > apart(spare[0]) ? 1 : 0;
            acc[slot] = spare[bi];
            spare.erase(spare.begin() + long(bi));
            if (spare.empty()) spare.push_back(acc[slot]);
            filled.push_back(slot);
        }
    }
    // the others for slot i: those before it, and any picked by hand
    auto others = [&](int i) { std::vector<int> v; for (int j = 0; j < 3; ++j) if (j != i && (j < i || fixedSlot[j])) v.push_back(j); return v; };
    for (int i = 1; i < 3 && !greys; ++i) {
        if (fixedSlot[i]) continue;
        const std::vector<int> ot = others(i);
        auto tooClose = [&](const QColor &c) { for (int j : ot) if (deltaE(c, acc[j]) < 0.09) return true; return false; };
        if (!tooClose(acc[i])) continue;
        const LCh o = lchOf(acc[i]);
        QColor best = acc[i];
        bool done = false;
        // first a lighter or darker version of the same colour: it stays the
        // picture's own (a darker cream, a deeper blue), where a turned one
        // wouldn't be
        {
            for (double step : { -0.14, -0.24, 0.14, 0.24 }) {
                const double L = o.L + (dark ? step : -step);
                if (dark ? L > 0.92 : L < 0.32) continue;          // not towards the text colour
                const QColor t = lchColour(L, o.C, o.h);
                if (!tooClose(t) && contrastOf(t, bg) >= ratio && contrastOf(t, raised) >= ratioRaised) { best = t; done = true; break; }
            }
        }
        if (!done && o.C >= 0.035) {
            // turned on the wheel; a pale colour (cream) also needs more
            // strength to tell its turns apart
            for (double c : { o.C, std::max(o.C, 0.09) }) {
                for (double turn : { 35.0, -35.0, 60.0, -60.0, 90.0, -90.0, 150.0 }) {
                    const QColor t = rd(lchColour(o.L, c, o.h + turn));
                    if (!tooClose(t)) { best = t; done = true; break; }
                }
                if (done) break;
            }
        }
        if (!done && o.C < 0.035) {
            for (double step : { 0.14, -0.14, 0.24, -0.24 }) {
                const double L = std::clamp(o.L + (dark ? step : -step), 0.0, 1.0);
                const QColor t = lchColour(L, o.C, o.h);
                if (!tooClose(t) && contrastOf(t, bg) >= ratio) { best = t; break; }
            }
        }
        acc[i] = best;
    }
    // last: a second or third that came out near the text colour steps back
    // towards the middle, if it can and still read and stay apart
    for (int i = 1; i < 3 && !greys; ++i) {
        if (fixedSlot[i] || !likeText(acc[i])) continue;
        const LCh o = lchOf(acc[i]);
        // (a soft colour also gains a little strength, so it can step back
        // without landing on the main colour)
        bool done = false;
        for (double c : { std::max(o.C, 0.04), std::max(o.C, 0.08) }) {
            for (double step : { 0.08, 0.14, 0.20 }) {
                const QColor t = lchColour(o.L + (dark ? -step : step), c, o.h);
                bool ok = !likeText(t) && contrastOf(t, bg) >= ratio && contrastOf(t, raised) >= ratioRaised;
                for (int j = 0; j < 3 && ok; ++j) if (j != i && deltaE(t, acc[j]) < 0.09) ok = false;
                if (ok) { acc[i] = t; done = true; break; }
            }
            if (done) break;
        }
    }
    // text on the main accent: the background or the text colour, whichever reads better
    const QColor onVivid = contrastOf(acc[0], bg) >= contrastOf(acc[0], fg) ? bg : fg;
    col.insert(QStringLiteral("vivid_value"), acc[0]);
    col.insert(QStringLiteral("on_vivid_value"), onVivid);
    col.insert(QStringLiteral("second_value"), acc[1]);
    col.insert(QStringLiteral("third_value"), acc[2]);
    // Material's softer secondary and tertiary, which the apps use widely,
    // become the picture's second and third colours, with their containers
    const char *names[2] = { "secondary", "tertiary" };
    for (int i = 0; i < 2; ++i) {
        const LCh o = lchOf(acc[i + 1]);
        const QString n = QString::fromLatin1(names[i]);
        col.insert(n, acc[i + 1]);
        col.insert(QStringLiteral("on_") + n, contrastOf(acc[i + 1], bg) >= contrastOf(acc[i + 1], fg) ? bg : fg);
        col.insert(n + QStringLiteral("_container"), atTone(dark ? 30 : 90, std::min(o.C, 0.08), o.h));
        col.insert(QStringLiteral("on_") + n + QStringLiteral("_container"), atTone(dark ? 90 : 10, std::min(o.C, 0.05), o.h));
    }
    // Material's primary family and its "fixed" colours, which the shell and
    // apps use for filled pills, active tiles and soft decorations: from the
    // three accents too, so no colour the picture doesn't have creeps in
    // (from a grey picture, Material's own make a teal out of nothing).
    // Errors stay Material's red.
    {
        const LCh a0 = lchOf(acc[0]), a1 = lchOf(acc[1]), a2 = lchOf(acc[2]);
        col.insert(QStringLiteral("primary"), acc[0]);
        col.insert(QStringLiteral("on_primary"), onVivid);
        col.insert(QStringLiteral("primary_container"), atTone(dark ? 30 : 90, std::min(a0.C, 0.08), a0.h));
        col.insert(QStringLiteral("on_primary_container"), atTone(dark ? 90 : 10, std::min(a0.C, 0.05), a0.h));
        const struct { const char *dim, *onVar; LCh c; } fixed[] = {
            { "primary_fixed_dim", "on_primary_fixed_variant", a0 },
            { "secondary_fixed_dim", "on_secondary_fixed_variant", a1 },
            { "tertiary_fixed_dim", "on_tertiary_fixed_variant", a2 },
        };
        for (const auto &f : fixed) {
            col.insert(QString::fromLatin1(f.dim), atTone(80, std::min(f.c.C, 0.10), f.c.h));
            col.insert(QString::fromLatin1(f.onVar), atTone(30, std::min(f.c.C, 0.08), f.c.h));
        }
    }
    for (auto it = col.cbegin(); it != col.cend(); ++it) m.insert(it.key(), it.value().name());
    return m;
}

QVariantList ArtColors::smartColours() const {
    QVariantList out;
    if (!m_smart.valid || !m_smart.seed.isValid()) return out;
    std::vector<QColor> list{ m_smart.seed };
    std::vector<Other> others(m_smart.others.cbegin(), m_smart.others.cend());
    std::stable_sort(others.begin(), others.end(), [](const Other &a, const Other &b) {
        return 0.5 * a.score + 0.5 * a.area > 0.5 * b.score + 0.5 * b.area;
    });
    for (const Other &o : others) list.push_back(o.colour);
    // a picture with few colours: its own lighter and deeper tones too
    if (m_smart.second.isValid()) list.push_back(m_smart.second);
    if (m_smart.third.isValid()) list.push_back(m_smart.third);
    std::vector<QColor> kept;
    for (const QColor &c : list) {
        bool near = false;
        for (const QColor &k : kept) if (deltaE(c, k) < 0.04) { near = true; break; }
        if (!near) kept.push_back(c);
        if (kept.size() >= 10) break;
    }
    for (const QColor &c : kept) out.append(c.name());
    return out;
}
