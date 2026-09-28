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
    visible: settingsWin.page === 20
    readonly property int pageNo: 20
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Login screen" }

    Card {
        app: settingsRoot.app
        title: "Background"
        desc: app.loginBusy ? "Setting it\u2026"
              : app.loginError !== "" ? app.loginError
              : app.loginFollows
              ? "The wallpaper and colours of whoever signed in last: on your own computer, always your current look."
              : "A background of its own, whoever signed in last. Its colours come from it."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Your wallpaper", "Its own"]
                current: app.loginFollows ? 0 : 1
                onPicked: i => app.setLoginFollow(i === 0)
            },
            Seg {
                app: settingsRoot.app
                options: ["Preview"]
                current: -1
                onPicked: app.previewLogin()
            }
        ]
    }
    // Ether Nightfall, then your wallpapers (for "Its own")
    Flow {
        visible: !app.loginFollows
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.bottomMargin: 10
        spacing: 8
        Repeater {
            model: [app.loginDefault].concat(app.wallpapers.slice(0, 23))
            delegate: Rectangle {
                id: lthumb
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === 0 ? !app.cfg.loginBackground
                                                              : app.cfg.loginBackground === modelData
                width: 132; height: 74; radius: 10
                color: app.cCard
                border.width: isCurrent ? 3 : 0
                border.color: app.cBlue
                clip: true
                Image {
                    anchors.fill: parent
                    anchors.margins: lthumb.isCurrent ? 3 : 0
                    source: "file://" + lthumb.modelData
                    sourceSize.width: 264
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Rectangle {
                    visible: lthumb.index === 0
                    anchors { left: parent.left; bottom: parent.bottom; margins: 6 }
                    width: lbl.implicitWidth + 12; height: 18; radius: 9
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Text { id: lbl; anchors.centerIn: parent; text: "Ether default"; color: "white"; font.family: "Inter"; font.pixelSize: app.fs(10) }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: lthumb.isCurrent || app.loginBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!lthumb.isCurrent && !app.loginBusy) app.setLoginBackground(lthumb.modelData)
                }
            }
        }
    }

    Card {
        app: settingsRoot.app
        title: "Preview"
        desc: "Locks the screen now so you can see your changes. Your password unlocks it as usual. The clock follows Bar, Time format."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Lock now"]
                onPicked: { app.settingsShown = false; app.run("sleep 0.4; loginctl lock-session") }
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Background" }

    Card {
        app: settingsRoot.app
        title: "Blur"
        desc: "How soft your wallpaper is behind the clock. Zero shows it sharp."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 0
                to: 12
                step: 1
                value: app.lockBlur
                label: Math.round(value) === 0 ? "Sharp" : Math.round(value)
                onMoved: v => app.setting("lockBlur", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.lockBlur === undefined ? 0 : -1
                onPicked: app.resetSetting("lockBlur")
            }
        ]
    }

    Card {
        app: settingsRoot.app
        title: "Brightness"
        desc: "How bright the wallpaper is kept. Lower makes the clock and text stand out more."
        trailing: [
            Slider {
                app: settingsRoot.app
                from: 20
                to: 100
                step: 5
                value: app.lockDim
                label: Math.round(value) + "%"
                onMoved: v => app.setting("lockDim", Math.round(v))
            },
            Seg {
                app: settingsRoot.app
                options: ["Default"]
                current: app.cfgUser.lockDim === undefined ? 0 : -1
                onPicked: app.resetSetting("lockDim")
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Text" }

    Card {
        app: settingsRoot.app
        title: "Greeting"
        desc: app.lockGreetMode === "time"
              ? "Good morning, afternoon, evening or night, with your user name."
              : app.lockGreetMode === "custom"
              ? "Your own line under the clock. Type it below and press Enter."
              : "No line under the clock."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Time of day", "Custom", "Off"]
                current: ["time", "custom", "off"].indexOf(app.lockGreetMode)
                onPicked: i => app.setting("lockGreetMode", ["time", "custom", "off"][i])
            }
        ]

        Rectangle {
            Layout.fillWidth: true
            visible: app.lockGreetMode === "custom"
            implicitHeight: 38
            radius: 19
            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
            border.width: greetIn.activeFocus ? 1 : 0
            border.color: app.cBlue
            TextInput {
                id: greetIn
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                verticalAlignment: TextInput.AlignVCenter
                text: app.lockGreetText
                color: app.cFg
                selectionColor: app.cBlue
                font.family: "Inter"
                font.pixelSize: app.fs(12)
                clip: true
                maximumLength: 80
                onAccepted: { app.setting("lockGreetText", text); settingsKeys.forceActiveFocus() }
                onActiveFocusChanged: if (!activeFocus && text !== app.lockGreetText)
                    app.setting("lockGreetText", text)
                Text {
                    visible: !greetIn.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Welcome back"
                    color: app.cFaint
                    font: greetIn.font
                }
            }
        }
    }

    Card {
        app: settingsRoot.app
        title: "Now playing"
        desc: "Shows the current track near the bottom while music is playing."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.lockMedia ? 1 : 0
                onPicked: i => app.setting("lockMedia", i === 1)
            }
        ]
    }
}
