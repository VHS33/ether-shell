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
    visible: settingsWin.page === 3
    readonly property int pageNo: 3
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Current" }

    Card {
        app: settingsRoot.app
        title: app.currentWall !== ""
               ? app.currentWall.split("/").pop()
               : "No wallpaper set yet"
        desc: app.wallBusy
              ? "Applying and retinting every app\u2026"
              : "Picking an image below sets it and rebuilds the palette with your Theme settings."

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: width * 9 / 16
            radius: 14
            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
            clip: true
            visible: app.currentWall !== ""

            Image {
                anchors.fill: parent
                source: app.currentWall !== "" ? "file://" + app.currentWall : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1200
                opacity: app.wallBusy ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            }
        }
    }

    SectionLabel { app: settingsRoot.app; text: "Library" }

    Card {
        app: settingsRoot.app
        title: app.wallpapers.length + (app.wallpapers.length === 1 ? " image" : " images")
        desc: app.wallpapers.length > 0
              ? "From ~/Pictures/wallpapers. New files show up the next time this page opens."
              : "Put images in ~/Pictures/wallpapers and reopen this page."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Random", "Open folder"]
                onPicked: i => {
                    if (i === 0) app.randomWallpaper()
                    else app.run("xdg-open \"$HOME/Pictures/wallpapers\"")
                }
            }
        ]

        Grid {
            id: wallGrid
            Layout.fillWidth: true
            Layout.topMargin: 4
            columns: 3
            spacing: 10
            readonly property real cellW: (width - spacing * (columns - 1)) / columns

            Repeater {
                model: app.wallpapers
                delegate: Rectangle {
                    id: thumb
                    required property var modelData
                    readonly property bool isCurrent: modelData === app.currentWall

                    width: wallGrid.cellW
                    height: width * 9 / 16
                    radius: 12
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                    clip: true
                    border.width: isCurrent ? 3 : thHov.hovered ? 2 : 0
                    border.color: isCurrent ? app.cBlue : app.cFg

                    HoverHandler { id: thHov }

                    Image {
                        anchors.fill: parent
                        anchors.margins: thumb.border.width
                        source: "file://" + thumb.modelData
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 360
                    }

                    // the colours this wallpaper would give
                    Rectangle {
                        readonly property var colours: app.wallPalettes[thumb.modelData] || []
                        visible: colours.length > 0
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 8
                        width: swRow.implicitWidth + 10
                        height: 20
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.45)
                        Row {
                            id: swRow
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater {
                                model: parent.parent.colours
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 12; height: 12; radius: 6
                                    color: modelData
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.35)
                                }
                            }
                        }
                    }

                    // check on the one in use
                    Rectangle {
                        visible: thumb.isCurrent
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        width: 24; height: 24; radius: 12
                        color: app.cBlue
                        Text {
                            anchors.centerIn: parent
                            text: "check"
                            color: app.cOnAccent
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(13)
                        }
                    }

                    // file name while hovered
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 26
                        color: Qt.rgba(0, 0, 0, 0.55)
                        opacity: thHov.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: app.animQuick; easing.type: Easing.OutCubic } }
                        Text {
                            anchors.centerIn: parent
                            width: parent.width - 14
                            text: String(thumb.modelData).split("/").pop()
                            color: "white"
                            font.family: "Inter"
                            font.pixelSize: app.fs(10)
                            elide: Text.ElideMiddle
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: thumb.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: if (!thumb.isCurrent) app.applyWallpaper(thumb.modelData)
                    }
                }
            }
        }
    }
}
