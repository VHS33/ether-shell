#include "fileindex.h"

#include <QDir>
#include <QFileInfo>
#include <QMetaObject>
#include <QPointer>
#include <QRegularExpression>
#include <QSocketNotifier>
#include <QtConcurrent/QtConcurrent>

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstring>
#include <ctime>
#include <dirent.h>
#include <fcntl.h>
#include <queue>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {
constexpr size_t kMaxNodes = 500000;     // a safety cap; a normal home is far below it

// folders that are never your own files: dependencies, caches, game internals
bool skipDirName(const char *n) {
    static const char *skip[] = { "node_modules", "__pycache__", "venv", "site-packages", "Trash",
                                  "drive_c", "dosdevices", "compatdata", "shadercache", "steamapps",
                                  "CMakeFiles", "bower_components", nullptr };
    for (int i = 0; skip[i]; ++i) if (!std::strcmp(n, skip[i])) return true;
    return false;
}
// the standard marker for cache folders (Rust's target/, many tools' caches)
bool isCacheDir(const std::string &path) {
    struct stat st;
    return ::stat((path + "/CACHEDIR.TAG").c_str(), &st) == 0;
}
std::string lowerOf(std::string_view s) {
    std::string o(s);
    for (char &c : o) c = char(std::tolower(static_cast<unsigned char>(c)));
    return o;
}
int32_t daysOf(time_t t) { return int32_t(t / 86400); }
bool isWordChar(char c) { return std::isalnum(static_cast<unsigned char>(c)); }

QString kindOf(std::string_view name, bool dir) {
    if (dir) return QStringLiteral("folder");
    const auto dot = name.rfind('.');
    if (dot == std::string::npos) return QStringLiteral("file");
    const std::string e = lowerOf(name.substr(dot + 1));
    auto in = [&](std::initializer_list<const char *> l) { for (auto x : l) if (e == x) return true; return false; };
    if (in({ "png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "tif", "tiff", "heic", "avif", "raw", "cr2", "nef", "psd", "kra", "xcf" }))
        return QStringLiteral("image");
    if (in({ "mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv" })) return QStringLiteral("video");
    if (in({ "mp3", "flac", "wav", "ogg", "opus", "m4a", "aac", "wma" })) return QStringLiteral("audio");
    if (in({ "pdf" })) return QStringLiteral("pdf");
    if (in({ "zip", "tar", "gz", "xz", "zst", "7z", "rar", "bz2", "tgz", "iso" })) return QStringLiteral("archive");
    if (in({ "c", "cc", "cpp", "h", "hpp", "rs", "py", "js", "ts", "tsx", "jsx", "qml", "go", "java", "kt", "lua", "sh",
             "fish", "zsh", "rb", "php", "cs", "swift", "zig", "json", "toml", "yaml", "yml", "xml", "html", "css", "scss", "sql" }))
        return QStringLiteral("code");
    if (in({ "txt", "md", "doc", "docx", "odt", "rtf", "xls", "xlsx", "ods", "csv", "ppt", "pptx", "odp", "epub", "tex" }))
        return QStringLiteral("document");
    return QStringLiteral("file");
}
}

void FileIndex::Index::add(int32_t parent, int32_t mtimeDays, std::string_view nm, bool dir) {
    Node n;
    n.parent = parent; n.mtimeDays = mtimeDays;
    n.off = uint32_t(arena.size());
    n.len = uint16_t(std::min<size_t>(nm.size(), 65535));
    n.dir = dir ? 1 : 0; n.gone = 0;
    arena.append(nm.data(), n.len);
    arena.append(lowerOf(nm.substr(0, n.len)));
    nodes.push_back(n);
    live++;
}

// ---------------------------------------------------------------------------
FileIndex::FileIndex(QObject *parent) : QObject(parent) {
    // stay well inside the kernel's inotify budget, which other programs share
    int maxWatches = 8192;
    if (FILE *f = std::fopen("/proc/sys/fs/inotify/max_user_watches", "r")) {
        if (std::fscanf(f, "%d", &maxWatches) != 1) maxWatches = 8192;
        std::fclose(f);
    }
    m_watchBudget = std::clamp(maxWatches / 2, 1000, 100000);

    m_rescanTimer.setInterval(30 * 60 * 1000);
    connect(&m_rescanTimer, &QTimer::timeout, this, &FileIndex::rescan);
    m_searchSoon.setSingleShot(true);
    m_searchSoon.setInterval(300);
    connect(&m_searchSoon, &QTimer::timeout, this, &FileIndex::runSearch);
    // start once QML has set the properties
    QMetaObject::invokeMethod(this, [this] { if (m_enabled) startScan(); }, Qt::QueuedConnection);
}

FileIndex::~FileIndex() {
    m_generation++;
    if (m_inotify >= 0) ::close(m_inotify);
}

int FileIndex::count() const {
    std::shared_lock lk(m_lock);
    return m_index ? int(m_index->live) : 0;
}

void FileIndex::setQuery(const QString &q) {
    if (q == m_query) return;
    m_query = q;
    emit queryChanged();
    runSearch();
}
void FileIndex::setLimit(int n) {
    n = std::clamp(n, 1, 500);
    if (n == m_limit) return;
    m_limit = n;
    emit limitChanged();
    runSearch();
}
void FileIndex::setEnabled(bool on) {
    if (on == m_enabled) return;
    m_enabled = on;
    emit enabledChanged();
    if (on) { startScan(); return; }
    // off: drop everything
    m_rescanTimer.stop();
    m_generation++;
    { std::unique_lock lk(m_lock); m_index.reset(); }
    delete m_notifier; m_notifier = nullptr;
    if (m_inotify >= 0) { ::close(m_inotify); m_inotify = -1; }
    m_ready = false; emit readyChanged(); emit countChanged();
    m_results.clear(); emit resultsChanged();
}
void FileIndex::rescan() { if (m_enabled) startScan(); }

// ---------------------------------------------------------------------------
//   Scanning
// ---------------------------------------------------------------------------
void FileIndex::watchDir(Index &idx, int32_t node, const std::string &path, int fd) {
    if (fd < 0 || int(idx.watchToNode.size()) >= m_watchBudget) return;
    const int wd = inotify_add_watch(fd, path.c_str(),
                                     IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO | IN_CLOSE_WRITE | IN_ONLYDIR);
    if (wd >= 0) { idx.watchToNode[wd] = node; idx.nodeToWatch[node] = wd; }
}

// everything under dirNode (at path), breadth first, so the watch budget
// goes to the shallower folders you're more likely to use
void FileIndex::addSubtree(Index &idx, int32_t dirNode, const std::string &path, int fd) {
    std::queue<std::pair<int32_t, std::string>> todo;
    todo.push({ dirNode, path });
    while (!todo.empty()) {
        auto [node, dpath] = todo.front();
        todo.pop();
        watchDir(idx, node, dpath, fd);
        DIR *d = ::opendir(dpath.c_str());
        if (!d) continue;
        const int dfd = ::dirfd(d);
        while (dirent *e = ::readdir(d)) {
            if (e->d_name[0] == '.') continue;                       // hidden, and . and ..
            if (idx.nodes.size() >= kMaxNodes) break;
            struct stat st;
            if (::fstatat(dfd, e->d_name, &st, AT_SYMLINK_NOFOLLOW) != 0) continue;
            if (S_ISLNK(st.st_mode)) continue;                        // no loops, no duplicates
            const bool isDir = S_ISDIR(st.st_mode);
            if (!isDir && !S_ISREG(st.st_mode)) continue;
            std::string child = dpath + "/" + e->d_name;
            if (isDir && (skipDirName(e->d_name) || isCacheDir(child))) continue;
            idx.add(node, daysOf(st.st_mtime), e->d_name, isDir);
            if (isDir) todo.push({ int32_t(idx.nodes.size() - 1), std::move(child) });
        }
        ::closedir(d);
    }
}

void FileIndex::startScan() {
    if (m_scanning.exchange(true)) return;
    // a fresh inotify instance for the fresh index (the old one, and all its
    // watches, go when the new index replaces it)
    const int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    const QString home = QDir::homePath();
    auto future = QtConcurrent::run([this, fd, home] {
        auto idx = std::make_shared<Index>();
        const std::string root = home.toStdString();
        struct stat st;
        idx->add(-1, ::stat(root.c_str(), &st) == 0 ? daysOf(st.st_mtime) : 0, root, true);
        idx->roots.push_back(root);
        addSubtree(*idx, 0, root, fd);          // watches go on the new instance
        idx->nodes.shrink_to_fit();
        idx->arena.shrink_to_fit();
        return idx;
    });
    auto *w = new QFutureWatcher<std::shared_ptr<Index>>(this);
    connect(w, &QFutureWatcher<std::shared_ptr<Index>>::finished, this, [this, w, fd] {
        auto idx = w->result();
        w->deleteLater();
        // swap in the new index and its inotify instance
        delete m_notifier; m_notifier = nullptr;
        if (m_inotify >= 0) ::close(m_inotify);
        m_inotify = fd;
        if (fd >= 0) {
            m_notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
            connect(m_notifier, &QSocketNotifier::activated, this, &FileIndex::onInotify);
        }
        scanDone(idx);
    });
    w->setFuture(future);
}

void FileIndex::scanDone(std::shared_ptr<Index> idx) {
    { std::unique_lock lk(m_lock); m_index = std::move(idx); }
    m_scanning = false;
    if (!m_ready) { m_ready = true; emit readyChanged(); }
    emit countChanged();
    m_rescanTimer.start();
    runSearch();
}

// ---------------------------------------------------------------------------
//   Live changes
// ---------------------------------------------------------------------------
void FileIndex::onInotify() {
    alignas(inotify_event) char buf[64 * 1024];
    bool changed = false, overflow = false;
    for (;;) {
        const ssize_t len = ::read(m_inotify, buf, sizeof buf);
        if (len <= 0) break;
        std::unique_lock lk(m_lock);
        if (!m_index) continue;
        Index &idx = *m_index;
        for (char *p = buf; p < buf + len;) {
            auto *ev = reinterpret_cast<inotify_event *>(p);
            p += sizeof(inotify_event) + ev->len;
            if (ev->mask & IN_Q_OVERFLOW) { overflow = true; continue; }
            if (!ev->len || ev->name[0] == '.') continue;
            auto it = idx.watchToNode.find(ev->wd);
            if (it == idx.watchToNode.end()) continue;
            const int32_t dirNode = it->second;
            if (idx.nodes[dirNode].gone) continue;
            const std::string name = ev->name;
            auto findChild = [&]() -> int32_t {
                for (size_t i = idx.nodes.size(); i-- > 0;)
                    if (idx.nodes[i].parent == dirNode && !idx.nodes[i].gone && idx.name(int32_t(i)) == name) return int32_t(i);
                return -1;
            };
            if (ev->mask & (IN_DELETE | IN_MOVED_FROM)) {
                const int32_t c = findChild();
                if (c >= 0) {
                    // the node, and everything under it
                    std::vector<char> dead(idx.nodes.size(), 0);
                    dead[c] = 1;
                    for (size_t i = size_t(c) + 1; i < idx.nodes.size(); ++i)
                        if (idx.nodes[i].parent >= 0 && dead[idx.nodes[i].parent]) dead[i] = 1;
                    for (size_t i = 0; i < idx.nodes.size(); ++i)
                        if (dead[i] && !idx.nodes[i].gone) { idx.nodes[i].gone = 1; idx.live--; }
                    changed = true;
                }
            }
            if (ev->mask & (IN_CREATE | IN_MOVED_TO)) {
                if (findChild() >= 0) continue;
                const std::string dpath = pathOf(idx, dirNode);
                const std::string path = dpath + "/" + name;
                struct stat st;
                if (::lstat(path.c_str(), &st) != 0 || S_ISLNK(st.st_mode)) continue;
                const bool isDir = S_ISDIR(st.st_mode);
                if (!isDir && !S_ISREG(st.st_mode)) continue;
                if (isDir && (skipDirName(name.c_str()) || isCacheDir(path))) continue;
                if (idx.nodes.size() >= kMaxNodes) continue;
                idx.add(dirNode, daysOf(st.st_mtime), name, isDir);
                if (isDir) addSubtree(idx, int32_t(idx.nodes.size() - 1), path, m_inotify);   // a folder moved or unpacked in
                changed = true;
            }
            if (ev->mask & IN_CLOSE_WRITE) {
                const int32_t c = findChild();
                if (c >= 0) { idx.nodes[c].mtimeDays = daysOf(std::time(nullptr)); changed = true; }
            }
        }
    }
    if (overflow) { rescan(); return; }
    if (changed) {
        emit countChanged();
        if (!m_query.trimmed().isEmpty() && !m_searchSoon.isActive()) m_searchSoon.start();
    }
}

std::string FileIndex::pathOf(const Index &idx, int32_t n) const {
    std::vector<std::string_view> parts;
    while (n >= 0) { parts.push_back(idx.name(n)); n = idx.nodes[n].parent; }
    std::string out;
    for (size_t i = parts.size(); i-- > 0;) { if (!out.empty()) out += '/'; out += parts[i]; }
    return out;
}

// ---------------------------------------------------------------------------
//   Matching
//
//   A word against a name, best first:
//     the whole name, or the name without its extension          1000
//     the start of the name                                        700
//     the start of a word inside it ("rep" in "q3-report")         550
//     anywhere inside it                                           400
//     its letters in order ("q3rp" in "q3-report"), scored on how
//     many land on word starts and how tightly they sit           ~100-300
//   A word that isn't in the name but is in a folder above it counts too,
//   for less (60), so "invoice 2025" finds 2025/march/invoice.pdf.
// ---------------------------------------------------------------------------
int FileIndex::matchScore(std::string_view name, std::string_view w, bool *inName) {
    *inName = true;
    if (w.empty()) return 0;
    if (name == w) return 1000;
    const auto dot = name.rfind('.');
    if (dot != std::string_view::npos && dot > 0 && dot == w.size() && name.substr(0, dot) == w) return 1000;
    const auto pos = name.find(w);
    if (pos == 0) return 700 - int(std::min<size_t>(100, name.size() - w.size()));
    if (pos != std::string_view::npos) {
        // a later occurrence might start a word even if the first doesn't
        for (size_t p = pos; p != std::string_view::npos; p = name.find(w, p + 1))
            if (!isWordChar(name[p - 1]) || (std::isdigit(static_cast<unsigned char>(name[p - 1])) != std::isdigit(static_cast<unsigned char>(name[p]))))
                return 550 - int(std::min<size_t>(100, name.size() - w.size()));
        return 400 - int(std::min<size_t>(100, name.size() - w.size()));
    }
    if (w.size() < 2) { *inName = false; return 0; }
    // letters in order
    size_t i = 0, last = std::string_view::npos;
    int starts = 0, gaps = 0, runs = 0;
    for (size_t k = 0; k < name.size() && i < w.size(); ++k) {
        if (name[k] != w[i]) continue;
        const bool start = k == 0 || !isWordChar(name[k - 1])
                           || (std::isdigit(static_cast<unsigned char>(name[k - 1])) != std::isdigit(static_cast<unsigned char>(name[k])));
        if (start) starts++;
        if (last != std::string_view::npos) { if (k == last + 1) runs++; else gaps += int(k - last - 1); }
        last = k;
        i++;
    }
    if (i < w.size()) { *inName = false; return 0; }
    const int s = 120 + 45 * starts + 20 * runs - 2 * std::min(gaps, 60);
    return std::max(40, std::min(s, 380));
}

void FileIndex::runSearch() {
    const uint64_t gen = ++m_generation;
    const QString q = m_query.trimmed().toLower();
    if (q.isEmpty() || !m_ready) {
        if (!m_results.isEmpty() || m_resultsFor != m_query) { m_results.clear(); m_resultsFor = m_query; emit resultsChanged(); }
        return;
    }
    const QString forQuery = m_query;
    std::vector<std::string> words;
    for (const QString &part : q.split(QRegularExpression(QStringLiteral("[\\s/]+")), Qt::SkipEmptyParts))
        words.push_back(part.toStdString());
    const int limit = m_limit;
    QPointer<FileIndex> self(this);
    (void)QtConcurrent::run([this, self, gen, words, limit, forQuery] {
        struct Hit { double score; int32_t node; };
        auto cmp = [](const Hit &a, const Hit &b) { return a.score > b.score; };   // min-heap of the best
        std::vector<Hit> heap;
        QVariantList out;
        {
            std::shared_lock lk(m_lock);
            if (!m_index || gen != m_generation) return;
            const Index &idx = *m_index;
            const int32_t today = daysOf(std::time(nullptr));
            std::vector<char> inPath;
            for (size_t n = 1; n < idx.nodes.size(); ++n) {
                const Node &nd = idx.nodes[n];
                if (nd.gone) continue;
                if ((n & 0x3fff) == 0 && gen != m_generation) return;   // a newer query: stop
                double total = 0;
                bool ok = true, anyInName = false;
                for (const std::string &w : words) {
                    bool inName = false;
                    int s = matchScore(idx.lower(int32_t(n)), w, &inName);
                    if (s > 0) { anyInName = true; total += s; continue; }
                    // in a folder above it?
                    bool found = false;
                    for (int32_t p = nd.parent; p > 0; p = idx.nodes[p].parent)
                        if (idx.lower(p).find(w) != std::string_view::npos) { found = true; break; }
                    if (!found) { ok = false; break; }
                    total += 60;
                }
                if (!ok || !anyInName) continue;
                // depth: files deep in trees are less likely what you want
                int depth = 0;
                for (int32_t p = nd.parent; p > 0; p = idx.nodes[p].parent) depth++;
                total -= 6.0 * std::max(0, depth - 2);
                // recently changed: up to +80, fading over about a month
                const int age = std::max(0, today - nd.mtimeDays);
                total += 80.0 * std::exp(-age / 30.0);
                if (nd.dir) total += 15;
                if (int(heap.size()) < limit) { heap.push_back({ total, int32_t(n) }); std::push_heap(heap.begin(), heap.end(), cmp); }
                else if (total > heap.front().score) {
                    std::pop_heap(heap.begin(), heap.end(), cmp);
                    heap.back() = { total, int32_t(n) };
                    std::push_heap(heap.begin(), heap.end(), cmp);
                }
            }
            std::sort(heap.begin(), heap.end(), [](const Hit &a, const Hit &b) { return a.score > b.score; });
            const std::string home = idx.roots.empty() ? std::string() : idx.roots.front();
            for (const Hit &h : heap) {
                const Node &nd = idx.nodes[h.node];
                const std::string path = pathOf(idx, h.node);
                std::string parent = pathOf(idx, nd.parent);
                if (!home.empty() && parent.compare(0, home.size(), home) == 0) parent = "~" + parent.substr(home.size());
                out.append(QVariantMap{
                    { "path", QString::fromStdString(path) },
                    { "name", QString::fromUtf8(idx.name(h.node).data(), qsizetype(idx.name(h.node).size())) },
                    { "parent", QString::fromStdString(parent) },
                    { "dir", bool(nd.dir) },
                    { "kind", kindOf(idx.name(h.node), nd.dir) },
                    { "modified", double(nd.mtimeDays) * 86400.0 * 1000.0 },
                    { "score", h.score } });
            }
        }
        QMetaObject::invokeMethod(self.data(), [self, gen, out, forQuery] {
            if (!self || gen != self->m_generation) return;
            self->m_results = out;
            self->m_resultsFor = forQuery;
            emit self->resultsChanged();
        }, Qt::QueuedConnection);
    });
}
