import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// ============================================================
//   CLIPBOARD  (SUPER + V)
//   Its own panel, sliding in from the right edge and filling that side
//   of the screen under the bar, the mirror of the assistant on the left.
//   Search as you type; All / Text / Images; copied pictures show as
//   thumbnails.  Click or Enter copies an entry back and closes;
//   Delete removes it; Esc, SUPER + V or a click outside closes.
//
//   History is app.clipItems ({ id, preview }, plain values, from
//   cliphist); thumbnails are decoded by the shell into
//   ~/.cache/ether/clip/ and reused.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    PanelWindow {
        id: cw
        required property var modelData
        screen: modelData
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.clipShown

        anchors { top: true; bottom: true; right: true }
        margins { top: app.barBottom + app.gap; bottom: app.gap; right: app.gap }
        implicitWidth: 460
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        property Region shownMask: Region { item: panel }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        // ---- what's listed ----
        property string filter: "all"                  // all, text, images
        property int sel: 0
        property bool confirmClear: false
        readonly property string q: search.text.trim().toLowerCase()
        readonly property var items: {
            const out = []
            for (const c of app.clipItems) {
                const img = app.clipImageInfo(c.preview)
                if (filter === "text" && img) continue
                if (filter === "images" && !img) continue
                if (q !== "" && (img ? ("image picture " + img.ext) : c.preview.toLowerCase()).indexOf(q) === -1) continue
                out.push({ id: c.id, text: c.preview, img: img !== null,
                           ext: img ? img.ext : "", size: img ? img.size : "", bytes: img ? img.bytes : "" })
                if (out.length >= 150) break
            }
            return out
        }
        onItemsChanged: if (sel >= items.length) sel = Math.max(0, items.length - 1)

        onOpenChanged: {
            if (open) {
                search.text = ""
                filter = "all"
                sel = 0
                confirmClear = false
                search.forceActiveFocus()
            }
        }

        function copyAt(i) {
            const it = items[i]
            if (it) app.clipCopy(it.id)          // copies and closes the panel
        }
        function deleteAt(i) {
            const it = items[i]
            if (it) app.clipDelete(it.id)
        }

        Rectangle {
            id: panel
            width: parent.width
            height: parent.height
            x: cw.open ? 0 : width + 24
            opacity: cw.open ? 1 : 0
            visible: opacity > 0
            Behavior on x { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: app.animNormal } }
            radius: 26
            color: app.cBg
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.45)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ---- header ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: 14
                        color: app.cPrimC
                        Text {
                            anchors.centerIn: parent
                            text: "content_paste"
                            color: app.cOnPrimC
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(20)
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Clipboard"
                            color: app.cFg
                            font.family: "Inter"
                            font.weight: Font.DemiBold
                            font.pixelSize: app.fs(15)
                        }
                        Text {
                            text: app.clipItems.length === 1 ? "1 item" : app.clipItems.length + " items"
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(11)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // clear everything: a second click to be sure
                    Rectangle {
                        visible: app.clipItems.length > 0
                        implicitWidth: cw.confirmClear ? clrT.implicitWidth + 24 : 34
                        implicitHeight: 34
                        radius: 12
                        color: cw.confirmClear ? app.cRed
                             : clrHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                        Behavior on implicitWidth { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                        HoverHandler { id: clrHov }
                        Text {
                            id: clrT
                            anchors.centerIn: parent
                            text: cw.confirmClear ? "Clear all?" : "delete_sweep"
                            color: cw.confirmClear ? app.cOnAccent : app.cDim
                            font.family: cw.confirmClear ? "Inter" : "Material Symbols Rounded"
                            font.weight: cw.confirmClear ? Font.DemiBold : Font.Normal
                            font.pixelSize: app.fs(cw.confirmClear ? 12 : 19)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (cw.confirmClear) { app.clipWipe(); cw.confirmClear = false }
                                else { cw.confirmClear = true; clearReset.restart() }
                            }
                        }
                        Timer { id: clearReset; interval: 3000; onTriggered: cw.confirmClear = false }
                    }
                    Rectangle {
                        implicitWidth: 34
                        implicitHeight: 34
                        radius: 12
                        color: xHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                        HoverHandler { id: xHov }
                        Text {
                            anchors.centerIn: parent
                            text: "close"
                            color: app.cDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(19)
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: app.clipShown = false
                        }
                    }
                }

                // ---- search ----
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 46
                    radius: 23
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10
                        Text {
                            text: "search"
                            color: app.cDim
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(19)
                        }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: app.cFg
                            selectionColor: app.cBlue
                            selectedTextColor: app.cOnAccent
                            font.family: "Inter"
                            font.pixelSize: app.fs(14)
                            clip: true
                            onTextChanged: cw.sel = 0
                            Text {
                                visible: !search.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search your clipboard"
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
                                font: search.font
                            }
                            Keys.onPressed: e => {
                                const n = cw.items.length
                                if (e.key === Qt.Key_Escape) {
                                    if (search.text !== "") search.text = ""
                                    else app.clipShown = false
                                } else if (e.key === Qt.Key_Down) {
                                    cw.sel = Math.min(n - 1, cw.sel + 1)
                                } else if (e.key === Qt.Key_Up) {
                                    cw.sel = Math.max(0, cw.sel - 1)
                                } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                                    cw.copyAt(cw.sel)
                                } else if (e.key === Qt.Key_Delete) {
                                    cw.deleteAt(cw.sel)
                                } else if (e.key === Qt.Key_Tab) {
                                    const order = ["all", "text", "images"]
                                    cw.filter = order[(order.indexOf(cw.filter) + 1) % 3]
                                    cw.sel = 0
                                } else return
                                e.accepted = true
                            }
                        }
                    }
                }

                // ---- all, text or pictures ----
                Row {
                    spacing: 6
                    Repeater {
                        model: [
                            { f: "all",    label: "All" },
                            { f: "text",   label: "Text" },
                            { f: "images", label: "Images" }
                        ]
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool on: cw.filter === modelData.f
                            implicitWidth: chipT.implicitWidth + 24
                            implicitHeight: 30
                            radius: 15
                            color: on ? app.cPrimC
                                 : chipHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
                                 : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                            HoverHandler { id: chipHov }
                            Text {
                                id: chipT
                                anchors.centerIn: parent
                                text: chip.modelData.label
                                color: chip.on ? app.cOnPrimC : app.cDim
                                font.family: "Inter"
                                font.weight: Font.Medium
                                font.pixelSize: app.fs(12)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { cw.filter = chip.modelData.f; cw.sel = 0; search.forceActiveFocus() }
                            }
                        }
                    }
                }

                // ---- the history ----
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 6
                    boundsBehavior: Flickable.StopAtBounds
                    model: cw.items
                    currentIndex: cw.sel
                    highlightFollowsCurrentItem: false
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        id: entry
                        required property var modelData
                        required property int index
                        readonly property bool current: index === cw.sel
                        width: ListView.view.width
                        implicitHeight: modelData.img ? 150 : Math.max(52, entryText.implicitHeight + 26)
                        radius: 16
                        color: current ? app.cPrimC
                             : eHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                        Behavior on color { ColorAnimation { duration: app.animQuick } }
                        HoverHandler { id: eHov; onHoveredChanged: if (hovered) cw.sel = entry.index }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cw.copyAt(entry.index)
                        }

                        // text: up to three lines of it
                        Text {
                            id: entryText
                            visible: !entry.modelData.img
                            anchors.left: parent.left
                            anchors.right: delBtn.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 14
                            anchors.rightMargin: 8
                            text: entry.modelData.text
                            color: entry.current ? app.cOnPrimC : app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }

                        // a picture: its thumbnail, and what it is
                        Item {
                            visible: entry.modelData.img
                            anchors.fill: parent
                            anchors.margins: 8
                            Rectangle {
                                id: thumbBox
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: height * 1.6
                                radius: 10
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: entry.modelData.img
                                        ? "file://" + app.clipThumbDir + "/" + entry.modelData.id + "." + entry.modelData.ext
                                          + "?v=" + app.clipThumbVer
                                        : ""
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    sourceSize.width: 320
                                    cache: false
                                }
                            }
                            ColumnLayout {
                                anchors.left: thumbBox.right
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 12
                                anchors.rightMargin: 34
                                spacing: 2
                                Text {
                                    text: "Image"
                                    color: entry.current ? app.cOnPrimC : app.cFg
                                    font.family: "Inter"
                                    font.weight: Font.DemiBold
                                    font.pixelSize: app.fs(12)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: [entry.modelData.ext.toUpperCase(),
                                           entry.modelData.size.replace("x", " \u00d7 "),
                                           entry.modelData.bytes].filter(x => x).join("  \u2022  ")
                                    color: entry.current ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.7) : app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(11)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        // remove this one
                        Rectangle {
                            id: delBtn
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            width: 28
                            height: 28
                            radius: 10
                            opacity: eHov.hovered ? 1 : 0
                            color: dHov.hovered ? Qt.rgba(app.cRed.r, app.cRed.g, app.cRed.b, 0.2) : "transparent"
                            HoverHandler { id: dHov }
                            Text {
                                anchors.centerIn: parent
                                text: "delete"
                                color: dHov.hovered ? app.cRed : (entry.current ? app.cOnPrimC : app.cDim)
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(16)
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: eHov.hovered
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cw.deleteAt(entry.index)
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: cw.items.length === 0
                        text: app.clipItems.length === 0 ? "Nothing copied yet"
                            : cw.filter === "images" ? "No images" : "Nothing matches"
                        color: app.cFaint
                        font.family: "Inter"
                        font.pixelSize: app.fs(13)
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Enter copies  \u2022  Delete removes  \u2022  Tab switches the filter"
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.35)
                    font.family: "Inter"
                    font.pixelSize: app.fs(10)
                }
            }
        }
    }
}
