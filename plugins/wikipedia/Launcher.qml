import QtQuick

// Wikipedia: an example Ether Shell launcher part.
//
// The launcher sets `query` as you type (here, what follows "!w"), and shows
// whatever is in `results`, whenever it arrives: each is { title, subtitle,
// icon, open | copy | run }.  So a plugin can look things up (the web, a
// command through ether.read) without holding the launcher up.
Item {
    id: wiki
    property var ether                     // given by Ether Shell
    property string query: ""
    property var results: []

    // (the tests point this somewhere else)
    property string endpoint: "https://en.wikipedia.org/w/api.php?action=opensearch&namespace=0&limit=8&format=json&search="

    // wait for a pause in typing, rather than asking at every key
    onQueryChanged: {
        if (query.trim() === "") { results = []; pause.stop(); if (request) request.abort(); return }
        pause.restart()
    }
    Timer { id: pause; interval: 300; onTriggered: wiki.fetch(wiki.query.trim()) }

    property var request: null
    function fetch(q) {
        if (request) request.abort()              // an older search: no longer wanted
        const x = new XMLHttpRequest()
        request = x
        x.onreadystatechange = () => {
            if (x.readyState !== XMLHttpRequest.DONE || x !== wiki.request) return
            wiki.request = null
            if (q !== wiki.query.trim()) return   // the answer to an earlier search
            try {
                // [what was searched, [titles], [descriptions], [links]]
                const r = JSON.parse(x.responseText)
                wiki.results = r[1].map((t, i) => ({
                    title: t,
                    subtitle: r[2][i] || "",       // (the launcher adds "Wikipedia" itself)
                    icon: "menu_book",
                    open: r[3][i]
                }))
            } catch (e) {
                wiki.results = [{ title: "Wikipedia didn't answer", subtitle: "Check your connection", icon: "cloud_off" }]
            }
        }
        x.open("GET", endpoint + encodeURIComponent(q))
        x.send()
    }
}
