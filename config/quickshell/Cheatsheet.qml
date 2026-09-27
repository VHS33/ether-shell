import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// ============================================================
//   KEYBIND CHEATSHEET  (SUPER + /)
//   Reads `hyprctl binds -j` each time it opens, so it can never
//   drift from the real config.  Binds are grouped (shell.qml sorts
//   them from their descriptions), shown with a keycap per key,
//   and a search box filters as you type.  Esc or a click outside
//   closes it.
// ============================================================
Variants {
    property var app
    model: Quickshell.screens

    // Built only for the main screen.  A copy per monitor used to be
    // made and hidden on the others, doubling the shell's memory and
    // background work (and causing doubled drawers); the other monitors'
    // loaders now stay empty.
    LazyLoader {
        id: perScreen
        required property var modelData
        // Built the first time it's opened, then kept for instant opening:
        // nothing sits in memory for a panel that's never used.
        property bool used: false
        active: modelData.name === app.mainScreen && (used || app.cheatShown)
        onActiveChanged: if (active) used = true

    PanelWindow {
        id: winK
        readonly property var modelData: perScreen.modelData
        screen: modelData
        // Stays mapped and animates itself: mapping a new surface on each
        // open lagged, and Hyprland's own layer fade fought the shell's.
        // Closed, nothing shows and the mask lets every click through.
        visible: modelData.name === app.mainScreen
        readonly property bool open: app.cheatShown
        // (built because it was just opened, it still runs its opening
        // setup: the change to open counts as it's created)

        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        property Region shownMask: Region { width: winK.width; height: winK.height }
        property Region hiddenMask: Region { width: 0; height: 0 }
        mask: open ? shownMask : hiddenMask

        readonly property var order: ["Apps", "Windows", "Workspaces", "Shell", "Screenshots", "Media"]
        readonly property string q: search.text.trim().toLowerCase()
        // the binds that match the search, grouped in order, as plain values
        readonly property var groups: {
            const out = []
            for (const g of order) {
                const items = app.cheatBinds.filter(b => b.group === g && (q === ""
                    || b.label.toLowerCase().indexOf(q) !== -1
                    || b.keys.join(" ").toLowerCase().indexOf(q) !== -1))
                if (items.length) out.push({ name: g, items: items })
            }
            return out
        }
        // masonry: each group goes into whichever column is shortest, so
        // a short group never leaves a hole beside a tall one
        readonly property var columns: {
            const cols = [[], [], []], h = [0, 0, 0]
            for (const g of groups) {
                const i = h.indexOf(Math.min(...h))
                cols[i].push(g)
                h[i] += g.items.length + 2      // rows, plus the heading
            }
            return cols
        }

        onOpenChanged: if (open) { search.text = ""; search.forceActiveFocus() }

        // the dimmed backdrop fades with the panel
        Rectangle {
            anchors.fill: parent
            color: app.scrim(0.55)
            opacity: winK.open ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: app.cheatShown = false
        }

        Rectangle {
            anchors.centerIn: parent
            opacity: winK.open ? 1 : 0
            scale: winK.open ? 1 : 0.95
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            width: Math.min(parent.width - 160, 1080)
            height: Math.min(parent.height - 140, main.implicitHeight + 44)
            radius: 28
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.55)

            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: main
                anchors.fill: parent
                anchors.margins: 22
                spacing: 14

                // ---- title and search ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 21
                        color: app.cBlue
                        Text {
                            anchors.centerIn: parent
                            text: "keyboard"
                            color: app.cOnAccent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(20)
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: "Keybinds"
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(20)
                            font.bold: true
                        }
                        Text {
                            text: "Read live from Hyprland, so this is always what's really bound"
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(11)
                        }
                    }
                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: 320
                        implicitHeight: 40
                        radius: 20
                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                        border.width: search.activeFocus ? 1 : 0
                        border.color: app.cBlue
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 8
                            Text {
                                text: "search"
                                color: app.cFaint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(14)
                            }
                            TextInput {
                                id: search
                                Layout.fillWidth: true
                                color: app.cFg
                                selectionColor: app.cBlue
                                font.family: "Inter"
                                font.pixelSize: app.fs(13)
                                clip: true
                                Keys.onEscapePressed: {
                                    if (text !== "") text = ""
                                    else app.cheatShown = false
                                }
                                Text {
                                    visible: !search.text
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Search binds"
                                    color: app.cFaint
                                    font: search.font
                                }
                            }
                        }
                    }
                }

                // ---- the groups, in columns ----
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: flow.implicitHeight
                    // room for "No binds match" when a search finds nothing
                    Layout.minimumHeight: 80
                    contentWidth: width
                    contentHeight: flow.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    RowLayout {
                        id: flow
                        width: parent.width
                        spacing: 10

                        Repeater {
                            model: winK.columns
                            delegate: ColumnLayout {
                                id: colItem
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.alignment: Qt.AlignTop
                                spacing: 10

                                Repeater {
                                    model: colItem.modelData
                                    delegate: Rectangle {
                                        id: grp
                                        required property var modelData
                                        Layout.fillWidth: true
                                        implicitHeight: gCol.implicitHeight + 22
                                        radius: 18
                                        color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)

                                        ColumnLayout {
                                            id: gCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 13
                                            spacing: 6

                                            Text {
                                                text: grp.modelData.name
                                                color: app.cBlue
                                                font.family: "Inter"
                                                font.pixelSize: app.fs(13)
                                                font.bold: true
                                            }

                                            Repeater {
                                                model: grp.modelData.items
                                                delegate: RowLayout {
                                                    id: bindRow
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    spacing: 8

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: bindRow.modelData.label
                                                        color: app.cFg
                                                        font.family: "Inter"
                                                        font.pixelSize: app.fs(12)
                                                        elide: Text.ElideRight
                                                    }

                                                    // one keycap per key
                                                    Row {
                                                        spacing: 4
                                                        Repeater {
                                                            model: bindRow.modelData.keys
                                                            delegate: Rectangle {
                                                                required property var modelData
                                                                implicitWidth: Math.max(22, capT.implicitWidth + 12)
                                                                implicitHeight: 22
                                                                radius: 6
                                                                color: app.cCard
                                                                border.width: 1
                                                                border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.9)
                                                                // a thicker bottom edge, like a real key
                                                                Rectangle {
                                                                    anchors.left: parent.left
                                                                    anchors.right: parent.right
                                                                    anchors.bottom: parent.bottom
                                                                    anchors.margins: 1
                                                                    height: 2
                                                                    radius: 5
                                                                    color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)
                                                                }
                                                                Text {
                                                                    id: capT
                                                                    anchors.centerIn: parent
                                                                    anchors.verticalCenterOffset: -1
                                                                    text: modelData
                                                                    color: app.cFg
                                                                    font.family: app.font
                                                                    font.pixelSize: app.fs(10)
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: winK.groups.length === 0
                        text: app.cheatBinds.length ? "No binds match \u201c" + search.text + "\u201d" : "Reading binds\u2026"
                        color: app.cFaint
                        font.family: "Inter"
                        font.pixelSize: app.fs(13)
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: -4
                    text: "Type to search.  Esc or a click outside closes."
                    color: app.cFaint
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                }
            }
        }
    }
    }
}
