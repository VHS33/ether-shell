// FileIndex: every file and folder in your home (hidden ones and build or
// cache folders left out), in memory, kept live as files change, with a
// fuzzy search for the launcher.
//
//   FileIndex { id: files; query: "q3 rep" }     // files.results: best first
//
// The first scan runs on a background thread at start-up; after that,
// inotify reports changes as they happen (folders beyond the kernel's watch
// budget are caught by a quiet rescan every 30 minutes).  Searches run on a
// background thread too, so typing never waits; a newer query simply
// replaces an older one.
#pragma once

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include <QTimer>
#include <atomic>
#include <cstdint>
#include <memory>
#include <shared_mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

class QSocketNotifier;

class FileIndex : public QObject {
    Q_OBJECT
    QML_ELEMENT
    // what to search for; several words must all match
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY queryChanged)
    // how many results at most (default 30)
    Q_PROPERTY(int limit READ limit WRITE setLimit NOTIFY limitChanged)
    // [{ path, name, parent, dir, kind, modified }], best first; kind is
    // folder, image, video, audio, pdf, code, archive, document or file
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    // the query the results are for (a newer one may still be searching)
    Q_PROPERTY(QString resultsFor READ resultsFor NOTIFY resultsChanged)
    // the index is built (the first scan has finished), and its size
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    // off: no scanning, no memory (Settings can turn file search off)
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)

public:
    explicit FileIndex(QObject *parent = nullptr);
    ~FileIndex() override;

    QString query() const { return m_query; }
    void setQuery(const QString &q);
    int limit() const { return m_limit; }
    void setLimit(int n);
    QVariantList results() const { return m_results; }
    QString resultsFor() const { return m_resultsFor; }
    bool ready() const { return m_ready; }
    int count() const;
    bool enabled() const { return m_enabled; }
    void setEnabled(bool on);

    // for tests and the rescan timer
    Q_INVOKABLE void rescan();

    // exposed for testing: the score of a name against a query word, 0 = no match
    static int matchScore(std::string_view nameLower, std::string_view word, bool *inName);

signals:
    void queryChanged();
    void limitChanged();
    void resultsChanged();
    void readyChanged();
    void countChanged();
    void enabledChanged();

private:
    // 16 bytes a node; its name (as on disk, then in lower case, for
    // matching) lives in one shared block of text, the arena
    struct Node {
        int32_t parent;            // index of the parent folder, -1 for a root
        int32_t mtimeDays;         // last modified, in days since 1970
        uint32_t off;              // where its name starts in the arena
        uint16_t len;              // its length (the lower-case copy follows it)
        uint8_t dir = 0;
        uint8_t gone = 0;          // deleted (kept as a tombstone until the next rescan)
    };
    struct Index {
        std::vector<Node> nodes;
        std::string arena;
        std::string_view name(int32_t n) const { return { arena.data() + nodes[n].off, nodes[n].len }; }
        std::string_view lower(int32_t n) const { return { arena.data() + nodes[n].off + nodes[n].len, nodes[n].len }; }
        void add(int32_t parent, int32_t mtimeDays, std::string_view name, bool dir);
        std::vector<std::string> roots;                 // root paths, by node index of each root
        std::unordered_map<int, int32_t> watchToNode;   // inotify watch -> folder node
        std::unordered_map<int32_t, int> nodeToWatch;
        size_t live = 0;
    };

    void startScan();
    void scanDone(std::shared_ptr<Index> idx);
    void runSearch();
    void onInotify();
    std::string pathOf(const Index &idx, int32_t n) const;
    // fd: the inotify instance the index's watches belong to
    void addSubtree(Index &idx, int32_t dirNode, const std::string &path, int fd);
    void watchDir(Index &idx, int32_t node, const std::string &path, int fd);

    QString m_query;
    int m_limit = 30;
    QVariantList m_results;
    QString m_resultsFor;
    bool m_ready = false;
    bool m_enabled = true;

    mutable std::shared_mutex m_lock;          // guards m_index
    std::shared_ptr<Index> m_index;
    std::atomic<uint64_t> m_generation{0};     // newest query; older searches drop their results
    std::atomic<bool> m_scanning{false};

    int m_inotify = -1;
    QSocketNotifier *m_notifier = nullptr;
    int m_watchBudget = 0;
    QTimer m_rescanTimer;
    QTimer m_searchSoon;                        // runs a search after live changes, at most every 300 ms
};
