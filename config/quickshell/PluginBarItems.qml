import QtQuick
import Quickshell
import "lib/models.mjs" as Models

// Enabled plugins' bar items for one side of the bar, each in a group like
// the bar's own.  A plugin that can't be loaded is switched off for now and
// its error shown in Settings, Plugins; the rest of the bar carries on.
Repeater {
    id: rep
    property var app
    property string side: "right"

    model: ScriptModel { values: Models.keyed(app ? app.pluginBarItems(side) : [], p => p.id); objectProp: "_key" }

    delegate: Item {
        id: host
        required property var modelData
        property Item inner: null
        visible: inner !== null
        implicitWidth: inner ? Math.max(28, inner.implicitWidth + 20) : 0
        implicitHeight: 28

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(rep.app.cFg.r, rep.app.cFg.g, rep.app.cFg.b, hov.hovered ? 0.12 : 0.07)
            Behavior on color { ColorAnimation { duration: rep.app.animQuick } }
        }
        HoverHandler { id: hov }

        PluginApi { id: api; app: rep.app; pluginId: host.modelData.id; dir: host.modelData.dir }

        Component.onCompleted: {
            const c = Qt.createComponent("file://" + modelData.dir + "/" + modelData.file)
            if (c.status !== Component.Ready) {
                rep.app.pluginFailed(modelData.id, c.status === Component.Error ? c.errorString() : "its bar item didn't load")
                return
            }
            const o = c.createObject(host, { ether: api })
            if (!o) { rep.app.pluginFailed(modelData.id, "its bar item couldn't be created"); return }
            o.anchors.centerIn = host
            inner = o
        }
        Component.onDestruction: if (inner) inner.destroy()
    }
}
