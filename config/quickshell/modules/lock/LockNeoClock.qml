import QtQuick
import qs.services

// The Neo lock screen's centre (Settings > Lock screen > Style): the date,
// the clock with its digits rolling over as they change, a hairline that
// sweeps through each minute, the greeting, and a quiet line of live
// readouts, framed by four thin corner brackets that draw themselves in as
// the screen locks.  In the theme's main colour, square or round to match
// Settings > Bar > Corners.
Item {
    id: neo
    property var app
    property real enter: 0                  // 0 = your desktop, 1 = locked (LockView)
    property bool square: false
    property string greeting: ""
    property real clockSize: 160
    readonly property color accent: app.cBlue
    readonly property real settle: Math.max(0, Math.min(1, (enter - 0.35) / 0.65))

    implicitWidth: Math.max(col.implicitWidth, 460) + 140
    implicitHeight: col.implicitHeight + 96

    // ---- the corner brackets ----
    Repeater {
        model: 4
        delegate: Item {
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            readonly property real len: 34
            readonly property real inset: (1 - neo.settle) * 26
            width: len; height: len
            x: atRight ? neo.width - len - inset : inset
            y: atBottom ? neo.height - len - inset : inset
            opacity: 0.75 * neo.settle
            Rectangle {
                x: 0; width: parent.len; height: 2
                y: parent.atBottom ? parent.len - 2 : 0
                radius: neo.square ? 0.5 : 1
                color: neo.accent
            }
            Rectangle {
                y: 0; width: 2; height: parent.len
                x: parent.atRight ? parent.len - 2 : 0
                radius: neo.square ? 0.5 : 1
                color: neo.accent
            }
        }
    }

    // one character of the clock: rolls up to the new one when it changes
    component Roll: Item {
        id: roll
        property string ch: ""
        property string prev: ""
        property real size: 160
        property real progress: 1
        width: ch === ":" || ch === "." ? colonMetrics.advanceWidth : digitMetrics.advanceWidth
        height: digitMetrics.height
        clip: true
        TextMetrics { id: digitMetrics; font: cur.font; text: "0" }
        TextMetrics { id: colonMetrics; font: cur.font; text: ":" }
        onChChanged: { rollAnim.stop(); progress = 0; rollAnim.start() }
        NumberAnimation {
            id: rollAnim
            target: roll; property: "progress"; from: 0; to: 1
            duration: 520; easing.type: Easing.OutCubic
            onStopped: roll.prev = roll.ch
        }
        Text {
            id: old
            visible: roll.progress < 1 && roll.prev !== ""
            text: roll.prev
            y: -roll.progress * roll.height
            opacity: 1 - roll.progress
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"
            font: cur.font
        }
        Text {
            id: cur
            text: roll.ch
            y: (1 - roll.progress) * roll.height
            opacity: roll.progress
            anchors.horizontalCenter: parent.horizontalCenter
            color: "white"
            font.family: Theme.uiFont
            font.weight: Font.ExtraLight
            font.pixelSize: roll.size
            font.features: { "tnum": 1 }
        }
    }

    Column {
        id: col
        anchors.centerIn: parent
        spacing: 6

        // the date, spaced out
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(neo.app.now, "dddd  ·  d MMMM").toUpperCase()
            color: Qt.rgba(1, 1, 1, 0.78)
            font.family: Theme.uiFont
            font.weight: Font.Medium
            font.pixelSize: neo.app.fs(14)
            font.letterSpacing: 4
            opacity: neo.settle
        }

        // the clock
        Row {
            id: clockRow
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0
            readonly property string time: neo.app.cfg.clock24h === true ? Qt.formatTime(neo.app.now, "HH:mm")
                                                                        : Qt.formatTime(neo.app.now, "h:mm AP").split(" ")[0]
            Repeater {
                model: clockRow.time.length
                delegate: Roll {
                    required property int index
                    ch: clockRow.time.charAt(index)
                    size: neo.clockSize
                }
            }
            Text {
                visible: neo.app.cfg.clock24h !== true
                anchors.bottom: parent.bottom
                anchors.bottomMargin: neo.clockSize * 0.2
                leftPadding: 12
                text: Qt.formatTime(neo.app.now, "AP")
                color: neo.accent
                font.family: Theme.uiFont
                font.weight: Font.Medium
                font.pixelSize: Math.round(neo.clockSize * 0.16)
                font.letterSpacing: 2
            }
        }

        // a hairline sweeping through the minute, a bright point at its head
        Item {
            id: sweep
            anchors.horizontalCenter: parent.horizontalCenter
            width: clockRow.width
            height: 6
            readonly property real frac: neo.app.now.getSeconds() / 60
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width; height: 1
                color: Qt.rgba(1, 1, 1, 0.14)
            }
            Rectangle {
                id: fill
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * sweep.frac * neo.settle
                height: 2
                radius: 1
                color: neo.accent
                // glides through the minute, snaps back at its turn
                Behavior on width {
                    enabled: sweep.frac > 0.02
                    NumberAnimation { duration: 950; easing.type: Easing.Linear }
                }
            }
            Rectangle {
                x: fill.width - width / 2
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6
                radius: neo.square ? 1 : 3
                color: neo.accent
                opacity: neo.settle
                Rectangle {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    radius: neo.square ? 3 : 8
                    color: Qt.rgba(neo.accent.r, neo.accent.g, neo.accent.b, 0.25)
                }
            }
        }

        Item { width: 1; height: 8 }

        // the greeting, quietly
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: neo.greeting !== ""
            text: neo.greeting.toUpperCase()
            color: Qt.rgba(1, 1, 1, 0.72)
            font.family: Theme.uiFont
            font.pixelSize: neo.app.fs(13)
            font.letterSpacing: 3
            opacity: neo.settle
        }

        // live readouts, typed out as the lock settles
        Text {
            id: readout
            anchors.horizontalCenter: parent.horizontalCenter
            readonly property var parts: {
                const p = ["CPU " + neo.app.cpuPct + "%", "MEM " + neo.app.memPct + "%"]
                if (neo.app.gpuOk) p.push("GPU " + neo.app.gpuTemp + "°")
                if (Battery.present) p.push("BAT " + Battery.percent + "%")
                if (neo.app.uptimeText) p.push("UP " + String(neo.app.uptimeText).replace(/^\s*up\s+/i, "").toUpperCase())
                return p
            }
            readonly property string full: parts.join("   /   ")
            text: full.substring(0, Math.round(full.length * Math.max(0, Math.min(1, (neo.enter - 0.55) / 0.45))))
            color: Qt.rgba(1, 1, 1, 0.5)
            font.family: Theme.font
            font.pixelSize: neo.app.fs(11)
            font.letterSpacing: 1.5
        }
    }
}
