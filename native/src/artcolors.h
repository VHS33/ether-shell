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
#include <QVariantList>
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
    // how colourful the image is (Hasler and Susstrunk's measure: about 0
    // for greyscale, 15-35 muted, 45+ colourful, 80+ vivid), how much of its
    // colour belongs to its main hue family (0-1), and the matugen colour
    // style that suits it: scheme-monochrome, -neutral, -fidelity or
    // -tonal-spot.  Set with lightness.
    Q_PROPERTY(double colourfulness READ colourfulness NOTIFY analyzed)
    Q_PROPERTY(double hueFocus READ hueFocus NOTIFY analyzed)
    Q_PROPERTY(QString suggestedScheme READ suggestedScheme NOTIFY analyzed)
    // Ether Shell's own choice of the colour a theme is built from, instead
    // of matugen's: the subject over the backdrop, skin set aside, the frame
    // ignored (see smartAnalyse).  smartSecond is the picture's second
    // colour family, if it has a strong one (invalid otherwise); smartWhy is
    // "the subject", "the backdrop", "the whole picture" or "no strong colour".
    Q_PROPERTY(QColor smartSeed READ smartSeed NOTIFY analyzed)
    // the picture's second and third colours: its other colour families,
    // or its own neutral tone (cream, grey) when it has only one real colour
    // (never a colour the picture doesn't have)
    Q_PROPERTY(QColor smartSecond READ smartSecond NOTIFY analyzed)
    Q_PROPERTY(QColor smartThird READ smartThird NOTIFY analyzed)
    Q_PROPERTY(QString smartWhy READ smartWhy NOTIFY analyzed)
    Q_PROPERTY(double skinShare READ skinShare NOTIFY analyzed)

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
    double colourfulness() const { return m_colourfulness; }
    double hueFocus() const { return m_hueFocus; }
    QString suggestedScheme() const { return m_scheme; }
    QColor smartSeed() const { return m_smartSeed; }
    QColor smartSecond() const { return m_smartSecond; }
    QColor smartThird() const { return m_smartThird; }
    QString smartWhy() const { return m_smartWhy; }
    double skinShare() const { return m_skinShare; }
    struct Smart { QColor seed, second, third; QString why; double skin = 0; };
    static Smart smartAnalyse(const QImage &img);
    static void colourStats(const QImage &img, double *colourfulness, double *hueFocus, double *saturation);
    // saturation: the average colour saturation (0-1), which catches what
    // colourfulness misses: a flat, vivid single colour has no variation
    static QString schemeFor(double colourfulness, double hueFocus, double saturation);

    // Calm places for widgets.  sizes: [[w, h], ...] in screen pixels, most
    // important first.  The wallpaper is taken as covering a screenW x screenH
    // screen (scaled to fill, centred, cropped), and nothing is placed within
    // `top` of the top edge (the bar), `bottom` of the bottom (the dock), or
    // `margin` of the sides.  Gives [{x, y}, ...] in the same order: each
    // widget in the calmest spot left (least edge detail: faces, buildings
    // and foliage count as busy, skies and gradients as calm), not
    // overlapping the ones before it, with `busy` (0 flat to 255) saying how
    // calm the spot really is.  Empty until an image has been read.
    Q_INVOKABLE QVariantList calmSpots(const QVariantList &sizes, int screenW, int screenH,
                                       int top, int bottom, int margin) const;

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
    // Everything worked out from one image, kept together: an image seen
    // before gives back all of it (not just some, with the rest left over
    // from the last image read, which once gave a new wallpaper the old
    // one's smart colour)
    struct Result {
        QColor seed;                           // the album-art colour (invalid: none)
        double lightness = -1, colourfulness = -1, hueFocus = -1, skin = 0, aspect = 16.0 / 9.0;
        QString scheme, why;
        QColor smartSeed, smartSecond, smartThird;
        QImage detail;
    };
    static Result analyse(const QImage &img);
    void setResult(const Result &r);
    QHash<QString, Result> m_cache;          // source -> everything about it
    double m_lightness = -1;
    double m_colourfulness = -1, m_hueFocus = -1;
    QString m_scheme;
    QColor m_smartSeed, m_smartSecond, m_smartThird;
    QString m_smartWhy;
    double m_skinShare = 0;
    QImage m_detail;                          // edge detail of the last image read, small
    double m_aspect = 16.0 / 9.0;             // its original width / height (the grid above isn't)
    static QImage detailOf(const QImage &img);
    QNetworkAccessManager *m_net = nullptr;
    QPointer<QNetworkReply> m_reply;
};
