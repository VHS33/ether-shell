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
#include <cmath>
#include <vector>

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
    // A vivid subject colour in a mostly dark or grey picture (red poppies
    // in the gloom): Auto style mustn't call it monochrome or neutral and
    // throw that colour away.  One colour, so content if it's most of the
    // picture's colour; tonal spot otherwise.
    if (sm.seed.isValid() && sm.why != QLatin1String("no strong colour")
            && (r.scheme == QLatin1String("scheme-monochrome") || r.scheme == QLatin1String("scheme-neutral"))) {
        const Lab o = toOklab(sm.seed.rgb());
        if (std::hypot(o.A, o.B) >= 0.06)
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
    // average relative luminance (linear light), then CIE L*
    auto lin = [](double c) { c /= 255.0; return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4); };
    double sum = 0; int n = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QRgb p = line[x];
            sum += 0.2126 * lin(qRed(p)) + 0.7152 * lin(qGreen(p)) + 0.0722 * lin(qBlue(p));
            ++n;
        }
    }
    if (!n) return -1;
    const double Y = sum / n;
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
//     2. the subject: detail (edges, blurred into regions) and colour that
//        stands out from the average mark where the eye goes;
//     3. skin: a narrow band of warm, modest colour counts for less, so a
//        portrait's theme comes from hair, eyes, clothes or light;
//     4. colour families: a hue histogram of the coloured pixels, weighted
//        by importance; each peak's average colour is a candidate, scored on
//        area and vividness, then raised or lowered by how much it is the
//        subject (in full only for vivid colours, so dull silhouettes don't
//        win on detail alone);
//     5. no real colour: the picture's own tint (a greyish seed), unless a
//        small vivid colour is clearly the subject (a red cape on white).
//   Tested against matugen on 40 real wallpapers (portraits, anime,
//   landscapes, cities, flowers, paintings) before it went in.
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
    std::vector<double> sal(N), weight(N);
    for (size_t i = 0; i < N; ++i) { sal[i] = 0.5 * nd[i] + 0.5 * ns[i]; weight[i] = keep[i] ? 0.3 + sal[i] : 0; }
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
    // L/A/B/C: the whole family (what it's chosen on, as tested);
    // vL/vA/vB: its vivid core, the most saturated 30% of it by importance
    // (what it's shown as): shadowed and muddy pixels don't average a vivid
    // colour down to brown, so a red poppy stays red
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
        const double base = 0.55 * std::pow(std::min(1.0, share / 0.30), 0.7) + 0.45 * std::min(1.0, cC / 0.14);
        const double vivid = std::min(1.0, cC / 0.10);
        const double mult = 1.0 + (std::min(1.5, std::max(0.6, subj)) - 1.0) * vivid;
        // a dull yellow-green (khaki, olive) reads as a muddy green in a
        // palette (Material avoids them too): it only leads if nothing else
        // represents the picture
        const double dislike = (centre >= 90 && centre <= 125 && cC < 0.10) ? 0.6 : 1.0;
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
        cands.push_back({ centre, share, cL, cA, cB, cC, subj, base * mult * dislike, vl / vw, va / vw, vb / vw });
    }
    std::stable_sort(cands.begin(), cands.end(), [](const Cand &a, const Cand &b) { return a.score > b.score; });
    std::vector<Cand> merged;
    for (const Cand &c : cands) {
        bool far = true;
        for (const Cand &m : merged) if (hueDist(c.hue, m.hue) < 25) { far = false; break; }
        if (far) merged.push_back(c);
    }
    const double colourShare = colW / std::max(1e-9, total);
    bool vividSubject = false;
    for (const Cand &c : merged) if (c.C >= 0.06 && c.subj >= 1.3 && c.share >= 0.004) vividSubject = true;
    // 5. no real colour
    if (merged.empty() || (colourShare < 0.03 && !vividSubject)) {
        res.seed = fromOklab(mL, mA, mB);
        res.second = res.third = res.seed;
        res.why = QStringLiteral("no strong colour");
        return res;
    }
    const Cand &p = merged.front();
    res.seed = fromOklab(p.vL, p.vA, p.vB);
    // second and third: the picture's other colour families (each clearly a
    // different colour, not a trace), then its own neutral tone
    std::vector<const Cand *> picks;
    for (size_t i = 1; i < merged.size() && picks.size() < 2; ++i) {
        const Cand &c = merged[i];
        if (c.share < 0.02 || c.C < 0.04 || hueDist(c.hue, p.hue) < 35) continue;
        bool apart = true;
        for (const Cand *q : picks) if (hueDist(c.hue, q->hue) < 35) apart = false;
        if (apart) picks.push_back(&c);
    }
    double nw = 0, nl = 0, na = 0, nb = 0;
    for (size_t i = 0; i < N; ++i)
        if (keep[i] && C[i] < 0.035 && L[i] > 0.25) { nw += weight[i]; nl += weight[i] * L[i]; na += weight[i] * A[i]; nb += weight[i] * B[i]; }
    const QColor neutral = nw > 0 ? fromOklab(nl / nw, na / nw, nb / nw) : fromOklab(mL, mA, mB);
    res.second = picks.size() > 0 ? fromOklab(picks[0]->vL, picks[0]->vA, picks[0]->vB) : neutral;
    res.third = picks.size() > 1 ? fromOklab(picks[1]->vL, picks[1]->vA, picks[1]->vB) : neutral;
    res.why = p.subj > 1.15 ? QStringLiteral("the subject") : p.subj < 0.85 ? QStringLiteral("the backdrop")
                            : QStringLiteral("the whole picture");
    return res;
}
