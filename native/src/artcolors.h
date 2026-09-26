#pragma once
// Colours from album art.
//
// Loads the art (a file, a file:// or data: URL, or http(s), as MPRIS gives
// it), shrinks it, finds its most vivid colour family (greys, blacks and
// whites don't count) and turns that into a small matching set: an accent,
// text on the accent, a container and text on the container, tuned for a
// dark or light theme.  Art with no real colour gives valid = false, and
// the shell keeps its own colours.  Results are cached per image.
#include <QColor>
#include <QHash>
#include <QImage>
#include <QObject>
#include <QPointer>
#include <QtQml/qqmlregistration.h>

class QNetworkAccessManager;
class QNetworkReply;

class ArtColors : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString source READ source WRITE setSource NOTIFY sourceChanged)
    Q_PROPERTY(bool dark READ dark WRITE setDark NOTIFY darkChanged)
    Q_PROPERTY(bool valid READ valid NOTIFY colorsChanged)
    Q_PROPERTY(QColor seed READ seed NOTIFY colorsChanged)
    Q_PROPERTY(QColor accent READ accent NOTIFY colorsChanged)
    Q_PROPERTY(QColor onAccent READ onAccent NOTIFY colorsChanged)
    Q_PROPERTY(QColor container READ container NOTIFY colorsChanged)
    Q_PROPERTY(QColor onContainer READ onContainer NOTIFY colorsChanged)
    // how light the image looks, 0 (black) to 100 (white): CIE L* of its
    // average luminance, as the eye judges it.  -1 until one is read.
    Q_PROPERTY(double lightness READ lightness NOTIFY analyzed)

public:
    explicit ArtColors(QObject *parent = nullptr);
    ~ArtColors() override;

    QString source() const { return m_source; }
    void setSource(const QString &s);
    bool dark() const { return m_dark; }
    void setDark(bool d);
    bool valid() const { return m_valid; }
    QColor seed() const { return m_seed; }
    QColor accent() const { return m_accent; }
    QColor onAccent() const { return m_onAccent; }
    QColor container() const { return m_container; }
    QColor onContainer() const { return m_onContainer; }
    double lightness() const { return m_lightness; }
    static double lightnessOf(const QImage &img);

    // the seed colour of an image, or an invalid colour (exposed for tests)
    static QColor seedOf(const QImage &img);

signals:
    void sourceChanged();
    void darkChanged();
    void colorsChanged();
    // every time an image has been read (lightness is set), colour or not
    void analyzed();

private:
    void load();
    void useImage(const QImage &img, const QString &forSource);
    void apply(const QColor &seed);
    void clear();

    QString m_source;
    bool m_dark = true;
    bool m_valid = false;
    QColor m_seed, m_accent, m_onAccent, m_container, m_onContainer;
    QHash<QString, QColor> m_cache;          // source -> seed (invalid: no colour)
    QHash<QString, double> m_lightCache;     // source -> lightness
    double m_lightness = -1;
    QNetworkAccessManager *m_net = nullptr;
    QPointer<QNetworkReply> m_reply;
};
