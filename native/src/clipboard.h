// ClipboardHistory: your clipboard history, kept by talking to the
// compositor's clipboard directly (the wlr data-control protocol, which
// Hyprland supports), instead of wl-paste watchers feeding cliphist.
//
//   ClipboardHistory { id: clip }
//   clip.items       // [{ id, preview, ext }], newest first (images: ext
//                    //  is png, jpg...; their file is the thumbnail)
//   clip.copy(id)    // put an entry back on the clipboard
//   clip.remove(id); clip.clear()
//
// - Every copy is seen as it happens.  Text is stored as text; pictures are
//   saved as image files straight away (they're the panel's thumbnails).
// - Copies a password manager marks secret (x-kde-passwordManagerHint) are
//   never stored.
// - Copying something that's already there moves it to the top.
// - When the app you copied from closes (on Wayland its copy goes with it),
//   your last copy is put back, as wl-clip-persist does.
// - The history lives in ~/.local/share/ether-shell/clipboard/ (readable
//   only by you); the first time, cliphist's history is brought over.
// - available is false when the compositor doesn't offer the protocol (or
//   the plugin was built without Wayland support): the shell then starts
//   the wl-paste and cliphist watchers as before.
//
// The compositor connection runs on its own thread with one poll loop (its
// messages, incoming data and outgoing data), so a slow app can't freeze
// the shell, and copying from our own history never waits on itself.
#pragma once

#include <QObject>
#include <QByteArray>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <atomic>
#include <memory>
#include <thread>

class ClipWorker;

class ClipboardHistory : public QObject {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QString directory READ directory CONSTANT)
    Q_PROPERTY(int limit READ limit WRITE setLimit NOTIFY limitChanged)
    // put your last copy back when the app it came from closes
    Q_PROPERTY(bool persist READ persist WRITE setPersist NOTIFY persistChanged)

public:
    explicit ClipboardHistory(QObject *parent = nullptr);
    ~ClipboardHistory() override;

    bool available() const { return m_available; }
    QVariantList items() const { return m_items; }
    QString directory() const { return m_dir; }
    int limit() const { return m_limit; }
    void setLimit(int n);
    bool persist() const { return m_persist; }
    void setPersist(bool on);

    Q_INVOKABLE void copy(const QString &id);
    Q_INVOKABLE void remove(const QString &id);
    Q_INVOKABLE void clear();

    // from the worker (queued onto the main thread)
    void gotData(const QByteArray &data, const QString &mime);
    void gotCleared();
    void setAvailable(bool on);

signals:
    void availableChanged();
    void itemsChanged();
    void limitChanged();
    void persistChanged();

private:
    struct Entry { QString id, kind, ext, preview, hash; qint64 time; };
    void load();
    void save();
    void publish();
    void trim();
    void importCliphist();
    QString fileOf(const Entry &e) const;
    static QString previewOfText(const QByteArray &text);

    bool m_available = false;
    bool m_persist = true;
    int m_limit = 250;
    QString m_dir;
    qint64 m_nextId = 1;
    QList<Entry> m_entries;          // newest first
    QVariantList m_items;
    ClipWorker *m_worker = nullptr;
    std::thread m_thread;
};
