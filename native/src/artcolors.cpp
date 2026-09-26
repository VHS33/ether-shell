#include "artcolors.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <cmath>

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
    if (m_cache.contains(m_source)) {
        const QColor c = m_cache.value(m_source);
        m_lightness = m_lightCache.value(m_source, -1);
        if (c.isValid()) apply(c); else clear();
        emit analyzed();
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
    QImage img;
    if (scheme == "data") {
        const int comma = m_source.indexOf(',');
        if (comma > 0) img = QImage::fromData(QByteArray::fromBase64(m_source.mid(comma + 1).toLatin1()));
    } else {
        img.load(scheme == "file" ? url.toLocalFile() : m_source);
    }
    useImage(img, m_source);
}

void ArtColors::useImage(const QImage &img, const QString &forSource) {
    const QColor seed = img.isNull() ? QColor() : seedOf(img);
    const double light = img.isNull() ? -1 : lightnessOf(img);
    if (m_cache.size() > 64) { m_cache.clear(); m_lightCache.clear(); }
    m_cache.insert(forSource, seed);
    m_lightCache.insert(forSource, light);
    if (forSource != m_source) return;        // the song changed meanwhile
    m_lightness = light;
    if (seed.isValid()) apply(seed); else clear();
    emit analyzed();
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
