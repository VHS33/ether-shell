import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.services

// ============================================================
//   CLIPBOARD  (SUPER + V)
//   Its own panel, sliding in from the right edge and filling that side
//   of the screen under the bar, the mirror of the assistant on the left.
//   Search as you type; All / Text / Images; copied pictures show as
//   thumbnails.  Click or Enter copies an entry back and closes;
//   Delete removes it; Esc, SUPER + V or its close button closes.  Like
//   the drawers it doesn't block the rest of the screen.
//
//   History is app.clipItems ({ id, preview }, plain values, from
//   cliphist); thumbnails are decoded by the shell into
//   ~/.cache/ether/clip/ and reused.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // Built the first time it's opened, kept while it's in use, and
        // released 3 minutes after it closes (the Timer in its window).
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.clipShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: cw

        // Released 3 minutes after it closes: its memory back.  Opening it
        // again builds it afresh, a moment's work.
        Timer {
            interval: 180000
            running: !app.clipShown
            onTriggered: Qt.callLater(() => { perScreen.used = false })
        }
        readonly property var modelData: perScreen.modelData
        screen: modelData
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.clipShown
        // (built because it was just opened, it still runs its opening
        // setup: the change to open counts as it's created)

        anchors { top: true; bottom: true; right: true }
        margins { top: app.barBottom + app.gap; bottom: app.gap; right: app.gap }
        implicitWidth: 460
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // The keyboard, as the launcher's: held from the moment it opens, so
        // you can type straight away wherever the mouse is, until the mouse
        // has been over it and gone off again; then it follows the mouse.
        // Clicks outside go to your apps and don't close it.
        property bool hoverSeen: false
        property bool keysFreed: false
        WlrLayershell.keyboardFocus: !open ? WlrKeyboardFocus.None
                                    : keysFreed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

        // the Wired look (Settings > Theme > Look)
        readonly property bool wired: app.wiredLook
        readonly property color wPaper: "#eceef2"
        readonly property color wDim: Qt.rgba(0.6, 0.62, 0.65, 1)
        readonly property color wFaint: Qt.rgba(0.38, 0.4, 0.44, 1)
        readonly property color wInk: "#0a0c0e"
        readonly property string wJp: ["IPAexGothic", "Noto Sans CJK JP", "Noto Sans JP", "Source Han Sans JP", "IPAGothic"]
                                      .find(f => Qt.fontFamilies().indexOf(f) >= 0) || ""
        readonly property string uiFamily: wired ? Theme.font : Theme.uiFont

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
            hoverSeen = clipHover.hovered
            keysFreed = false
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
            radius: cw.wired ? 0 : app.rr(26)
            color: cw.wired ? Qt.rgba(0.035, 0.043, 0.051, 0.92) : app.cBg
            border.width: 1
            border.color: cw.wired ? Qt.rgba(1, 1, 1, 0.36) : Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.45)

            // ---- the Wired look's title bar: CLIP, how many, CLEAR, the boxes close it ----
            Rectangle {
                visible: cw.wired
                width: parent.width; height: 22
                color: Qt.rgba(0.93, 0.94, 0.95, 0.9)
                Row {
                    x: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text { text: "CLIPBOARD"; color: cw.wInk; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 13 }
                    Text { visible: cw.wJp !== ""; text: "履歴"; color: cw.wInk; font.family: cw.wJp; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }
                Row {
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ("00" + Math.min(999, app.clipItems.length)).slice(-3) + " ITEMS"
                        color: Qt.rgba(0.24, 0.25, 0.27, 1); font.family: Theme.font; font.pixelSize: 12
                    }
                    // clear everything: a second click to be sure
                    Rectangle {
                        visible: app.clipItems.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: wClrT.implicitWidth + 12; height: 16
                        color: cw.confirmClear ? app.cRed : "transparent"
                        border.width: cw.confirmClear ? 0 : 1
                        border.color: cw.wInk
                        Text { id: wClrT; anchors.centerIn: parent; text: cw.confirmClear ? "CLEAR ALL?" : "CLEAR"; color: cw.wInk; font.family: Theme.font; font.weight: Font.Bold; font.pixelSize: 10 }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (cw.confirmClear) { app.clipWipe(); cw.confirmClear = false }
                                else { cw.confirmClear = true; clearReset.restart() }
                            }
                        }
                    }
                    Item {
                        width: wBoxes.width; height: 16
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: wBoxes
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Repeater { model: 3; delegate: Rectangle { width: 7; height: 7; color: "transparent"; border.width: 1; border.color: cw.wInk } }
                        }
                        MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: app.clipShown = false }
                    }
                }
            }
            Rectangle {
                visible: cw.wired
                anchors.fill: parent; anchors.margins: 3; anchors.topMargin: 25
                color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.1)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: cw.wired ? 22 + 14 : 16
                spacing: 12

                // ---- header ----
                RowLayout {
                    visible: !cw.wired
                    Layout.fillWidth: true
                    spacing: 10
                    Rectangle {
                        implicitWidth: 38
                        implicitHeight: 38
                        radius: app.rr(14)
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
                            font.family: Theme.uiFont
                            font.weight: Font.DemiBold
                            font.pixelSize: app.fs(15)
                        }
                        Text {
                            text: app.clipItems.length === 1 ? "1 item" : app.clipItems.length + " items"
                            color: app.cDim
                            font.family: Theme.uiFont
                            font.pixelSize: app.fs(11)
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // clear everything: a second click to be sure
                    Rectangle {
                        visible: app.clipItems.length > 0
                        implicitWidth: cw.confirmClear ? clrT.implicitWidth + 24 : 34
                        implicitHeight: 34
                        radius: app.rr(12)
                        color: cw.confirmClear ? app.cRed
                             : clrHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1) : "transparent"
                        Behavior on implicitWidth { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                        HoverHandler { id: clrHov }
                        Text {
                            id: clrT
                            anchors.centerIn: parent
                            text: cw.confirmClear ? "Clear all?" : "delete_sweep"
                            color: cw.confirmClear ? app.cOnAccent : app.cDim
                            font.family: cw.confirmClear ? Theme.uiFont : "Material Symbols Rounded"
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
                        radius: app.rr(12)
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
                    implicitHeight: cw.wired ? 40 : 46
                    radius: cw.wired ? 0 : app.rr(23)
                    color: cw.wired ? "transparent" : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                    border.width: cw.wired ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, 0.3)
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 10
                        Text {
                            text: cw.wired ? ">" : "search"
                            color: cw.wired ? app.cBlue : app.cDim
                            font.family: cw.wired ? Theme.font : "Material Symbols Rounded"
                            font.weight: cw.wired ? Font.Bold : Font.Normal
                            font.pixelSize: app.fs(cw.wired ? 15 : 19)
                        }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: cw.wired ? cw.wPaper : app.cFg
                            selectionColor: app.cBlue
                            selectedTextColor: cw.wired ? cw.wInk : app.cOnAccent
                            font.family: cw.uiFamily
                            font.pixelSize: app.fs(14)
                            clip: true
                            onTextChanged: cw.sel = 0
                            Text {
                                visible: !search.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: cw.wired ? "search your clipboard" : "Search your clipboard"
                                color: cw.wired ? cw.wFaint : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.4)
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
                            implicitHeight: cw.wired ? 26 : 30
                            radius: cw.wired ? 0 : app.rr(15)
                            color: cw.wired ? (on ? app.cBlue : chipHov.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                 : on ? app.cPrimC
                                 : chipHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.11)
                                 : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                            border.width: cw.wired && !on ? 1 : 0
                            border.color: Qt.rgba(1, 1, 1, 0.3)
                            HoverHandler { id: chipHov }
                            Text {
                                id: chipT
                                anchors.centerIn: parent
                                text: cw.wired ? chip.modelData.label.toUpperCase() : chip.modelData.label
                                color: cw.wired ? (chip.on ? cw.wInk : cw.wPaper) : chip.on ? app.cOnPrimC : app.cDim
                                font.family: cw.uiFamily
                                font.weight: cw.wired ? Font.Bold : Font.Medium
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
                        radius: cw.wired ? 0 : app.rr(16)
                        color: cw.wired ? (current ? app.cBlue : Qt.rgba(1, 1, 1, 0.03))
                             : current ? app.cPrimC
                             : eHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.1)
                             : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.06)
                        border.width: cw.wired && !current ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.14)
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
                            color: cw.wired ? (entry.current ? cw.wInk : cw.wPaper) : entry.current ? app.cOnPrimC : app.cFg
                            font.family: cw.uiFamily
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
                                radius: cw.wired ? 0 : app.rr(10)
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                border.width: cw.wired ? 1 : 0
                                border.color: entry.current ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(1, 1, 1, 0.3)
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
                                    text: cw.wired ? "IMAGE" : "Image"
                                    color: cw.wired ? (entry.current ? cw.wInk : cw.wPaper) : entry.current ? app.cOnPrimC : app.cFg
                                    font.family: cw.uiFamily
                                    font.weight: Font.DemiBold
                                    font.pixelSize: app.fs(12)
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: [entry.modelData.ext.toUpperCase(),
                                           entry.modelData.size.replace("x", " \u00d7 "),
                                           entry.modelData.bytes].filter(x => x).join("  \u2022  ")
                                    color: cw.wired ? (entry.current ? Qt.rgba(0.04, 0.05, 0.06, 0.72) : cw.wDim)
                                         : entry.current ? Qt.rgba(app.cOnPrimC.r, app.cOnPrimC.g, app.cOnPrimC.b, 0.7) : app.cDim
                                    font.family: cw.uiFamily
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
                            radius: cw.wired ? 0 : app.rr(10)
                            opacity: eHov.hovered ? 1 : 0
                            color: dHov.hovered ? (cw.wired ? app.cRed : Qt.rgba(app.cRed.r, app.cRed.g, app.cRed.b, 0.2)) : "transparent"
                            border.width: cw.wired && !dHov.hovered ? 1 : 0
                            border.color: entry.current ? Qt.rgba(0, 0, 0, 0.4) : Qt.rgba(1, 1, 1, 0.3)
                            HoverHandler { id: dHov }
                            Text {
                                anchors.centerIn: parent
                                text: cw.wired ? "X" : "delete"
                                color: cw.wired ? (dHov.hovered || entry.current ? cw.wInk : cw.wDim)
                                     : dHov.hovered ? app.cRed : (entry.current ? app.cOnPrimC : app.cDim)
                                font.family: cw.wired ? Theme.font : "Material Symbols Rounded"
                                font.weight: cw.wired ? Font.Bold : Font.Normal
                                font.pixelSize: app.fs(cw.wired ? 12 : 16)
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
                        color: cw.wired ? cw.wFaint : app.cFaint
                        font.family: cw.uiFamily
                        font.pixelSize: app.fs(13)
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Enter copies  \u2022  Delete removes  \u2022  Tab switches the filter"
                    color: cw.wired ? cw.wFaint : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.35)
                    font.family: cw.uiFamily
                    font.pixelSize: app.fs(10)
                }
            }
        }

        // the mouse over the panel: once it has been on it and gone off,
        // the keyboard follows the mouse (above).  It only watches.
        Item {
            x: panel.x; y: panel.y; width: panel.width; height: panel.height
            HoverHandler {
                id: clipHover
                onHoveredChanged: {
                    if (!cw.open) return
                    if (hovered) cw.hoverSeen = true
                    else if (cw.hoverSeen) cw.keysFreed = true
                }
            }
        }
    }
    }
}
