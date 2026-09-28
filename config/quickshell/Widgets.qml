import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris

// ============================================================
//   DESKTOP WIDGETS
//   One transparent full-screen layer per monitor on Hyprland's
//   bottom layer: above the wallpaper, below every window.
//
//   Arrange mode (app.widgetEdit) lifts the layer to the top,
//   dims the screen and lets the widgets be dragged; positions
//   are saved to settings.json on release.  Esc or Done drops
//   them back behind the windows.
//
//   The model is app.widgets: plain values only.
// ============================================================
Variants {
    id: rootV
    property var app
    model: Quickshell.screens

    // One layer of widgets.  Each screen gets two: `editLayer: false`
    // sits on the bottom layer and shows normally; `editLayer: true` sits
    // on top and only appears while arranging.  Two fixed windows rather
    // than one that changes layer, so nothing depends on moving a live
    // surface between layers.
    component Layer: PanelWindow {
        id: winW
        property var app
        property bool editLayer: false
        readonly property string scr: screen ? screen.name : ""
        readonly property var mine: app.widgets.filter(w => (w.screen || app.mainScreen) === scr)

        visible: editLayer ? app.widgetEdit : (!app.widgetEdit && mine.length > 0)
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        WlrLayershell.layer: editLayer ? WlrLayer.Top : WlrLayer.Bottom
        WlrLayershell.keyboardFocus: editLayer ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // ---------------- arrange mode ----------------
        Rectangle {
            anchors.fill: parent
            visible: app.widgetEdit
            color: app.scrim(0.45)
        }

        Item {
            anchors.fill: parent
            focus: app.widgetEdit
            Keys.onEscapePressed: app.widgetEdit = false
        }

        // instructions and Done, top centre
        Rectangle {
            visible: app.widgetEdit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: app.barBottom + 24
            z: 10
            implicitWidth: tbRow.implicitWidth + 24
            implicitHeight: 52
            radius: 26
            color: app.cCard
            border.width: 1
            border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.6)

            RowLayout {
                id: tbRow
                anchors.centerIn: parent
                spacing: 14
                Text {
                    Layout.leftMargin: 8
                    text: winW.mine.length
                          ? "Drag widgets to move them. The \u00d7 removes one."
                          : "No widgets on this screen. Add some in Settings, Widgets."
                    color: app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(13)
                }
                Rectangle {
                    implicitWidth: doneT.implicitWidth + 32
                    implicitHeight: 36
                    radius: 18
                    color: doneHov.hovered ? Qt.lighter(app.cBlue, 1.1) : app.cBlue
                    HoverHandler { id: doneHov }
                    Text {
                        id: doneT
                        anchors.centerIn: parent
                        text: "Done"
                        color: app.cOnAccent
                        font.family: "Inter"
                        font.pixelSize: app.fs(13)
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.widgetEdit = false
                    }
                }
            }
        }

        // ---------------- the widgets ----------------
        Repeater {
            model: winW.mine

            delegate: Item {
                id: wd
                required property var modelData
                property bool dragging: false

                width: body.item ? body.item.implicitWidth : 0
                height: body.item ? body.item.implicitHeight : 0
                // the size, for automatic placement
                onWidthChanged: app.noteWidgetSize(modelData.id, width, height)
                onHeightChanged: app.noteWidgetSize(modelData.id, width, height)
                x: Math.max(0, Math.min(winW.width - width, modelData.x))
                y: Math.max(0, Math.min(winW.height - height, modelData.y))
                // moved by automatic placement: glide there (not while dragging)
                Behavior on x { enabled: !wd.dragging; NumberAnimation { duration: app.animSlow; easing.type: Easing.InOutCubic } }
                Behavior on y { enabled: !wd.dragging; NumberAnimation { duration: app.animSlow; easing.type: Easing.InOutCubic } }
                z: dragging ? 5 : 1

                Loader {
                    id: body
                    sourceComponent: ({
                        clock: clockC, weather: weatherC, calendar: calendarC,
                        system: systemC, media: mediaC, note: noteC
                    })[wd.modelData.type] ?? (String(wd.modelData.type).startsWith("plugin:") ? pluginC : null)
                    property var entry: wd.modelData
                }

                // arrange mode: outline, drag anywhere, × to remove
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    visible: app.widgetEdit
                    radius: 28
                    color: "transparent"
                    border.width: 2
                    border.color: wd.dragging ? app.cBlue
                                : Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.55)
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: app.widgetEdit
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    property real ox: 0
                    property real oy: 0
                    onPressed: m => {
                        const p = mapToItem(null, m.x, m.y)
                        ox = p.x - wd.x
                        oy = p.y - wd.y
                        wd.dragging = true
                    }
                    onPositionChanged: m => {
                        if (!pressed) return
                        const p = mapToItem(null, m.x, m.y)
                        wd.x = Math.max(0, Math.min(winW.width - wd.width, p.x - ox))
                        wd.y = Math.max(0, Math.min(winW.height - wd.height, p.y - oy))
                    }
                    onReleased: {
                        wd.dragging = false
                        // snap to an 8 px grid and save
                        app.updateWidget(wd.modelData.id, {
                            x: Math.round(wd.x / 8) * 8,
                            y: Math.round(wd.y / 8) * 8
                        })
                    }
                }

                Rectangle {
                    visible: app.widgetEdit
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: -12
                    width: 28; height: 28; radius: 14
                    color: rmHov.hovered ? app.cRed : Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.8)
                    HoverHandler { id: rmHov }
                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        color: rmHov.hovered ? app.cOnAccent : app.cFg
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: app.fs(14)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: app.removeWidget(wd.modelData.id)
                    }
                }
            }
        }

        // =====================================================
        //   widget bodies
        // =====================================================

        // clock
        Component {
            id: clockC
            Rectangle {
                implicitWidth: 360
                implicitHeight: clCol.implicitHeight + 36
                radius: 24
                color: app.cCard
                border.width: 1
                border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
                ColumnLayout {
                    id: clCol
                    anchors.centerIn: parent
                    spacing: -4
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8
                        Text {
                            id: clT
                            text: app.cfg.clock24h === true
                                  ? Qt.formatDateTime(app.now, "HH:mm")
                                  : Qt.formatDateTime(app.now, "h:mm AP").split(" ")[0]
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(72)
                            font.weight: Font.Light
                        }
                        Text {
                            visible: app.cfg.clock24h !== true
                            anchors.baseline: clT.baseline
                            text: Qt.formatDateTime(app.now, "AP")
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(20)
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDateTime(app.now, "dddd, d MMMM")
                        color: app.cDim
                        font.family: "Inter"
                        font.pixelSize: app.fs(15)
                    }
                }
            }
        }

        // weather
        Component {
            id: weatherC
            Rectangle {
                implicitWidth: 320
                implicitHeight: 136
                radius: 24
                color: app.cCard
                border.width: 1
                border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16
                    Text {
                        text: app.wxOk ? app.wxSymbol(app.wxCond, app.wxDay) : "cloud_off"
                        color: app.cYellow
                        font.family: "Material Symbols Rounded"
                        font.pixelSize: app.fs(54)
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            text: app.wxOk ? app.wxTemp : "\u2014"
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(34)
                            font.weight: Font.Light
                        }
                        Text {
                            Layout.fillWidth: true
                            text: app.wxOk ? app.wxCond : (app.wxHasPlace ? "No weather yet" : "Set a location in Settings, Weather")
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(13)
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: app.wxPlace + (app.wxOk ? ", feels " + app.wxFeel : "")
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(11)
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // calendar: always this month
        Component {
            id: calendarC
            Rectangle {
                id: calW
                readonly property var cells: {
                    const n = app.now
                    const y = n.getFullYear(), mo = n.getMonth()
                    const lead = (new Date(y, mo, 1).getDay() - app.calWeekStart + 7) % 7
                    const days = new Date(y, mo + 1, 0).getDate()
                    const pad = v => (v < 10 ? "0" : "") + v
                    const out = []
                    for (let i = 0; i < lead; i++) out.push({ d: "", key: "" })
                    for (let d = 1; d <= days; d++) {
                        const key = y + "-" + pad(mo + 1) + "-" + pad(d)
                        out.push({ d: d, key: key, today: d === n.getDate(), hol: app.holidayOn(key) !== "" })
                    }
                    return out
                }
                implicitWidth: 320
                implicitHeight: calCol.implicitHeight + 36
                radius: 24
                color: app.cCard
                border.width: 1
                border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
                ColumnLayout {
                    id: calCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 8
                    Text {
                        text: Qt.formatDateTime(app.now, "MMMM yyyy")
                        color: app.cFg
                        font.family: "Inter"
                        font.pixelSize: app.fs(15)
                        font.bold: true
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 7
                        rowSpacing: 2
                        columnSpacing: 2
                        Repeater {
                            model: 7
                            delegate: Text {
                                required property int index
                                readonly property int dow: (index + app.calWeekStart) % 7
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: ["S", "M", "T", "W", "T", "F", "S"][dow]
                                color: (dow === 0 || dow === 6) ? app.cPeach : app.cDim
                                font.family: "Inter"
                                font.pixelSize: app.fs(11)
                                font.bold: true
                            }
                        }
                        Repeater {
                            model: calW.cells
                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 15
                                color: modelData.today ? app.cBlue
                                     : modelData.hol ? Qt.rgba(app.cPeach.r, app.cPeach.g, app.cPeach.b, 0.18)
                                     : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData.d
                                    color: parent.modelData.today ? app.cOnAccent
                                         : parent.modelData.hol ? app.cPeach : app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                    font.bold: parent.modelData.today === true
                                }
                            }
                        }
                    }
                }
            }
        }

        // system
        Component {
            id: systemC
            Rectangle {
                implicitWidth: 320
                implicitHeight: sysCol.implicitHeight + 36
                radius: 24
                color: app.cCard
                border.width: 1
                border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
                ColumnLayout {
                    id: sysCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 10
                    Repeater {
                        // four fixed rows that read their own live values; handing
                        // the values in the list remade all four every 2 seconds
                        model: ["cpu", "mem", "gpu", "gtemp"]
                        delegate: ColumnLayout {
                            id: sysRow
                            required property string modelData
                            readonly property var row: modelData === "cpu"
                                ? { k: "CPU", v: app.cpuPct, t: app.cpuPct + "%", c: "green", show: true }
                                : modelData === "mem"
                                ? { k: "Memory", v: app.memPct, t: app.memPct + "%", c: "peach", show: true }
                                : modelData === "gpu"
                                ? { k: "GPU", v: app.gpuPct, t: app.gpuPct + "%", c: "mauve", show: app.gpuOk }
                                : { k: "GPU temp", v: Math.min(100, app.gpuTemp), t: app.gpuTemp + "\u00b0C", c: "teal", show: app.gpuOk }
                            readonly property color tint: ({
                                green: app.cGreen, peach: app.cPeach, mauve: app.cMauve, teal: app.cTeal
                            })[sysRow.row.c]
                            visible: sysRow.row.show
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    Layout.fillWidth: true
                                    text: sysRow.row.k
                                    color: app.cDim
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                }
                                Text {
                                    text: sysRow.row.t
                                    color: app.cFg
                                    font.family: "Inter"
                                    font.pixelSize: app.fs(12)
                                    font.bold: true
                                }
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 8
                                radius: 4
                                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, sysRow.row.v / 100))
                                    height: parent.height
                                    radius: 4
                                    color: sysRow.tint
                                    Behavior on width { NumberAnimation { duration: app.animSlow; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }
                }
            }
        }

        // media
        Component {
            id: mediaC
            Rectangle {
                id: medW
                readonly property bool playing: app.player?.playbackState === MprisPlaybackState.Playing
                implicitWidth: 400
                implicitHeight: 124
                radius: 24
                color: app.cCard
                border.width: 1
                border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    // rounded album art
                    Item {
                        implicitWidth: 92
                        implicitHeight: 92
                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                            Text {
                                anchors.centerIn: parent
                                visible: !artImg.source.toString()
                                text: "music_note"
                                color: app.cFaint
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: app.fs(30)
                            }
                        }
                        Image {
                            id: artImg
                            anchors.fill: parent
                            // the media widget shows it small
                            sourceSize.width: 320
                            sourceSize.height: 320
                            source: app.player?.trackArtUrl ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            visible: false
                        }
                        Item {
                            id: artMask
                            anchors.fill: parent
                            layer.enabled: true
                            visible: false
                            Rectangle { anchors.fill: parent; radius: 16; color: "black" }
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: artImg
                            maskEnabled: true
                            maskSource: artMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                            visible: artImg.status === Image.Ready
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: app.player?.trackTitle || "Nothing playing"
                            color: app.cFg
                            font.family: "Inter"
                            font.pixelSize: app.fs(15)
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: text !== ""
                            text: app.player?.trackArtist ?? ""
                            color: app.cDim
                            font.family: "Inter"
                            font.pixelSize: app.fs(12)
                            elide: Text.ElideRight
                        }
                        RowLayout {
                            Layout.topMargin: 6
                            spacing: 6
                            visible: app.player !== null
                            Repeater {
                                model: [
                                    { g: "skip_previous", a: "prev" },
                                    { g: "",          a: "play" },
                                    { g: "skip_next", a: "next" }
                                ]
                                delegate: Rectangle {
                                    id: mb
                                    required property var modelData
                                    readonly property bool isPlay: modelData.a === "play"
                                    implicitWidth: isPlay ? 38 : 32
                                    implicitHeight: implicitWidth
                                    radius: implicitWidth / 2
                                    color: isPlay ? app.cBlue : mbHov.hovered ? Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.12) : "transparent"
                                    HoverHandler { id: mbHov }
                                    Text {
                                        anchors.centerIn: parent
                                        text: mb.isPlay ? (medW.playing ? "pause" : "play_arrow") : mb.modelData.g
                                        color: mb.isPlay ? app.cOnAccent : app.cFg
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: app.fs(mb.isPlay ? 17 : 15)
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: !app.widgetEdit
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const p = app.player
                                            if (!p) return
                                            if (mb.modelData.a === "prev") p.previous()
                                            else if (mb.modelData.a === "next") p.next()
                                            else if (p.canTogglePlaying) p.togglePlaying()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // note: its entry carries the text
        Component {
            id: pluginC
            // a plugin's widget: in the same card as the built-in ones, the
            // plugin drawing only what's inside; nothing at all while its
            // plugin is off (or couldn't load it)
            Rectangle {
                id: pcard
                readonly property var info: app.pluginWidgetInfo(parent ? parent.entry?.type : "")
                visible: phl.item !== null && phl.item.inner !== null
                implicitWidth: visible ? phl.item.implicitWidth + 36 : 0
                implicitHeight: visible ? phl.item.implicitHeight + 36 : 0
                radius: 24
                color: app.cCard
                border.width: 1
                border.color: Qt.rgba(app.cBorder.r, app.cBorder.g, app.cBorder.b, 0.5)
                Loader {
                    id: phl
                    anchors.centerIn: parent
                    active: pcard.info !== null
                    sourceComponent: PluginHost {
                        app: rootV.app
                        pluginId: pcard.info.id
                        dir: pcard.info.dir
                        file: pcard.info.file
                        part: "desktop widget"
                    }
                }
            }
        }
        Component {
            id: noteC
            Rectangle {
                implicitWidth: 280
                implicitHeight: Math.max(120, noteT.implicitHeight + 40)
                radius: 20
                color: Qt.rgba(app.cYellow.r, app.cYellow.g, app.cYellow.b, 0.22)
                border.width: 1
                border.color: Qt.rgba(app.cYellow.r, app.cYellow.g, app.cYellow.b, 0.45)
                Text {
                    id: noteT
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    text: parent.parent.entry?.text || ""
                    color: app.cFg
                    font.family: "Inter"
                    font.pixelSize: app.fs(14)
                    wrapMode: Text.WordWrap
                    lineHeight: 1.2
                }
            }
        }
    }

    // per screen: the everyday layer and the arrange layer
    Scope {
        id: pair
        required property var modelData
        Layer { app: rootV.app; screen: pair.modelData; editLayer: false }
        Layer { app: rootV.app; screen: pair.modelData; editLayer: true }
    }
}
