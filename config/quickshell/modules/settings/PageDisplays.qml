import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common.widgets

ColumnLayout {
    // what the Settings window passes in (named so nothing in Settings can
    // be mistaken for them: `win: win` could mean the page's own win)
    property var app
    property var settingsWin
    property var settingsRoot
    property var settingsKeys
    width: parent.width
    visible: settingsWin.page === 9
    readonly property int pageNo: 9
    spacing: 4

    // the confirmation, shown after Apply
    Card {
        app: settingsRoot.app
        visible: app.revertLeft > 0
        color: Qt.rgba(app.cBlue.r, app.cBlue.g, app.cBlue.b, 0.18)
        title: "Keep these display settings?"
        desc: "Reverting to the previous settings in " + app.revertLeft
              + (app.revertLeft === 1 ? " second." : " seconds.")
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Revert", "Keep"]
                current: 1
                onPicked: i => i === 1 ? app.keepDisplays() : app.revertDisplays()
            }
        ]
    }

    Card {
        app: settingsRoot.app
        visible: app.monInfo.length > 0
        title: "Arrangement"
        desc: app.monInfo.length > 1
              ? "Drag the screens to where they sit on your desk. They snap together at the edges, lining up when close."
              : "Your screen. Connect another and it appears here, to drag into place."
        MonitorLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            app: settingsRoot.app
            monitors: settingsWin.monTiles()
            selected: settingsWin.selMon
            onMoved: (name, x, y) => settingsWin.moveMon(name, x, y)
            onPicked: name => settingsWin.selMon = name
        }
    }

    Repeater {
        model: app.monInfo
        delegate: ColumnLayout {
            id: monSec
            required property var modelData
            readonly property var d: settingsWin.draft[modelData.name] ?? null
            Layout.fillWidth: true
            spacing: 4

            SectionLabel {
                app: settingsRoot.app
                text: monSec.modelData.name
                      + (monSec.modelData.name === settingsWin.mainMon ? ", main" : "")
            }

            Card {
                app: settingsRoot.app
                title: monSec.modelData.desc || monSec.modelData.name
                desc: "Running at " + monSec.modelData.w + "\u00d7" + monSec.modelData.h
                      + ", " + Math.round(monSec.modelData.hz) + " Hz, "
                      + Math.round(monSec.modelData.scale * 100) + "% scale."

                Text {
                    text: "Resolution"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    font.bold: true
                    Layout.topMargin: 4
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: settingsWin.resList(monSec.modelData)
                        delegate: Chip {
                            required property var modelData
                            app: settingsRoot.app
                            text: modelData.w + "\u00d7" + modelData.h
                            selected: monSec.d !== null && monSec.d.res === modelData.key
                            onPicked: settingsWin.setDraft(monSec.modelData.name, "res", modelData.key)
                        }
                    }
                }

                Text {
                    text: "Refresh rate"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    font.bold: true
                    Layout.topMargin: 6
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: monSec.d ? settingsWin.rateList(monSec.modelData, monSec.d.res) : []
                        delegate: Chip {
                            required property var modelData
                            app: settingsRoot.app
                            text: (Math.round(modelData.hz * 100) / 100) + " Hz"
                            selected: monSec.d !== null && monSec.d.mode === modelData.mode
                            onPicked: settingsWin.setDraft(monSec.modelData.name, "mode", modelData.mode)
                        }
                    }
                }

                Text {
                    visible: app.monBus[monSec.modelData.name] !== undefined
                    text: "Brightness"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    font.bold: true
                    Layout.topMargin: 6
                }
                Slider {
                    app: settingsRoot.app
                    visible: app.monBus[monSec.modelData.name] !== undefined
                    accent: settingsRoot.app.cYellow
                    from: 0
                    to: 100
                    step: 5
                    value: app.bright[monSec.modelData.name] ?? 0
                    label: Math.round(value) + "%"
                    onMoved: v => app.setBright(monSec.modelData.name, v)
                }

                Text {
                    text: "Scale"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    font.bold: true
                    Layout.topMargin: 6
                }
                Seg {
                    app: settingsRoot.app
                    options: settingsWin.scales.map(x => Math.round(x * 100) + "%")
                    current: monSec.d ? settingsWin.scales.findIndex(x => Math.abs(x - monSec.d.scale) < 0.01) : -1
                    onPicked: i => settingsWin.setDraft(monSec.modelData.name, "scale", settingsWin.scales[i])
                }

                Text {
                    text: "Rotation"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    font.bold: true
                    Layout.topMargin: 6
                }
                Seg {
                    app: settingsRoot.app
                    options: ["Normal", "90\u00b0", "180\u00b0", "270\u00b0"]
                    current: monSec.d ? (monSec.d.transform || 0) : 0
                    onPicked: i => settingsWin.setDraft(monSec.modelData.name, "transform", i)
                }

                Text {
                    text: "Variable refresh rate"
                    color: app.cDim
                    font.family: "Inter"
                    font.pixelSize: app.fs(11)
                    font.bold: true
                    Layout.topMargin: 6
                }
                Seg {
                    app: settingsRoot.app
                    options: ["Off", "On", "Games only"]
                    current: monSec.d ? (monSec.d.vrr || 0) : 0
                    onPicked: i => settingsWin.setDraft(monSec.modelData.name, "vrr", i)
                }
            }
        }
    }

    SectionLabel {
        app: settingsRoot.app
        visible: app.monInfo.length > 1
        text: "Main monitor"
    }

    Card {
        app: settingsRoot.app
        visible: app.monInfo.length > 1
        title: "Shell lives on"
        desc: "The monitor with the bar, dock, sidebar, notifications and panels."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: app.monInfo.map(m => m.name)
                current: app.monInfo.map(m => m.name).indexOf(app.mainScreen)
                onPicked: i => app.setting("mainScreen", app.monInfo[i].name)
            }
        ]
    }

    SectionLabel {
        app: settingsRoot.app
        visible: app.monInfo.length === 2
        text: "Arrangement"
    }

    Card {
        app: settingsRoot.app
        visible: app.revertLeft === 0
        title: settingsWin.draftDirty() ? "Ready to apply" : "No changes"
        desc: "Nothing changes until you apply. You then have 15 seconds to keep the new settings before they revert on their own."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: settingsWin.draftDirty() ? ["Undo changes", "Apply"] : ["Apply"]
                onPicked: i => {
                    if (settingsWin.draftDirty() && i === 0) settingsWin.loadDraft()
                    else if (settingsWin.draftDirty()) settingsWin.applyDraft()
                }
            }
        ]
    }

    // ---- profiles: a saved layout per set of screens ----
    SectionLabel {
        app: settingsRoot.app
        text: "Profiles"
    }

    Card {
        app: settingsRoot.app
        title: "Switch layouts by themselves"
        desc: "When a monitor is plugged in or out, use the saved profile for the screens then connected. Changes you make by hand are never undone."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.profilesAuto ? 1 : 0
                onPicked: i => app.setting("monitorProfilesAuto", i === 1)
            }
        ]
    }

    Card {
        id: saveProfileCard
        app: settingsRoot.app
        visible: app.revertLeft === 0
        property string said: ""
        Timer { id: saidClear; interval: 6000; onTriggered: saveProfileCard.said = "" }
        function save() {
            if (settingsWin.draftDirty()) { said = "Apply your changes first, then save them."; saidClear.restart(); return }
            const out = {}
            for (const n of Object.keys(settingsWin.draft)) {
                const d = settingsWin.draft[n]
                out[n] = { mode: d.mode, position: Math.round(d.x || 0) + "x" + Math.round(d.y || 0), scale: d.scale,
                           transform: d.transform || 0, vrr: d.vrr || 0 }
            }
            said = app.saveMonProfile(profileName.text, out)
            if (said.startsWith("Saved")) profileName.text = ""
            saidClear.restart()
        }
        title: "Save this layout"
        desc: said !== "" ? said
              : "As it is now, for the screens connected: " + app.screensNowList.map(x => x.name).join(", ") + "."
        trailing: [
            Rectangle {
                implicitWidth: 150
                implicitHeight: 34
                radius: 10
                color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                border.width: profileName.activeFocus ? 2 : 0
                border.color: app.cBlue
                TextInput {
                    id: profileName
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    color: app.cFg
                    selectionColor: app.cBlue
                    font.family: "Inter"
                    font.pixelSize: app.fs(12)
                    maximumLength: 30
                    clip: true
                    onAccepted: saveProfileCard.save()
                    Text {
                        visible: !profileName.text && !profileName.activeFocus
                        anchors.verticalCenter: parent.verticalCenter
                        text: "A name, like Desk"
                        color: app.cFaint
                        font: profileName.font
                    }
                }
            },
            Seg {
                app: settingsRoot.app
                options: ["Save"]
                onPicked: saveProfileCard.save()
            }
        ]
    }

    Repeater {
        model: app.monProfiles
        delegate: Card {
            id: profCard
            required property var modelData
            readonly property bool here: modelData.key === app.screensNow
            readonly property bool inUse: here && app.profileNowInUse
            app: settingsRoot.app
            title: modelData.name + (inUse ? "  \u00b7  in use" : "")
            desc: modelData.screens.map(x => x.name + (x.model ? " (" + x.model + ")" : "")).join(", ")
                  + (here ? "" : ". Not connected now.")
            trailing: [
                Seg {
                    app: settingsRoot.app
                    options: profCard.here && !profCard.inUse && app.revertLeft === 0 ? ["Use", "Delete"] : ["Delete"]
                    onPicked: i => {
                        if (options[i] === "Use") app.useMonProfile(profCard.modelData)
                        else app.deleteMonProfile(profCard.modelData.name)
                    }
                }
            ]
        }
    }
}
