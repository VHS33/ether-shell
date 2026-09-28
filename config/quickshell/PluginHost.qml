import QtQuick

// One part of a plugin (a desktop widget, or its settings), loaded from its
// folder with its toolkit, `ether` (PluginApi.qml).  A part that can't be
// loaded is reported (app.pluginFailed: set aside, its error shown in
// Settings, Plugins) instead of breaking what it sits in.
//
//   fill: the part takes the host's width (settings pages); otherwise the
//   host takes the part's own size (widgets)
Item {
    id: host
    property var app
    property string pluginId
    property string dir
    property string file
    property string part: "part"            // for the error: "desktop widget", "settings"
    property bool fill: false
    property Item inner: null

    implicitWidth: inner ? inner.implicitWidth : 0
    implicitHeight: inner ? (fill ? Math.max(inner.implicitHeight, inner.height) : inner.implicitHeight) : 0

    PluginApi { id: api; app: host.app; pluginId: host.pluginId; dir: host.dir }

    Component.onCompleted: {
        const c = Qt.createComponent("file://" + dir + "/" + file)
        if (c.status !== Component.Ready) {
            app.pluginFailed(pluginId, c.status === Component.Error ? c.errorString() : "its " + part + " didn't load")
            return
        }
        const o = c.createObject(host, { ether: api })
        if (!o) { app.pluginFailed(pluginId, "its " + part + " couldn't be created"); return }
        if (fill) o.width = Qt.binding(() => host.width)
        inner = o
    }
    Component.onDestruction: if (inner) inner.destroy()
}
