import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.common.widgets
import qs.services

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
    id: wallPage

    // the library in two: pictures, and live (moving) wallpapers.  Opens on
    // the kind in use; the tab picked is kept while the shell runs.
    readonly property var pictures: app.wallpapers.filter(p => !app.isMovingWall(p))
    readonly property var lives: app.wallpapers.filter(p => app.isMovingWall(p))
    property string tab: app.isMovingWall(app.currentWall) ? "live" : "pictures"
    readonly property var shown: tab === "live" ? lives : pictures

    SectionLabel { app: settingsRoot.app; text: "Current" }

    Card {
        app: settingsRoot.app
        title: app.currentWall !== ""
               ? app.currentWall.split("/").pop()
               : "No wallpaper set yet"
        desc: app.wallBusy
              ? "Applying and retinting every app\u2026"
              : app.isMovingWall(app.currentWall)
              ? "A moving wallpaper: the desktop plays it, and the colours come from a still picked from it."
              : "Picking one below sets it and rebuilds the palette with your Theme settings."

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            implicitHeight: width * 9 / 16
            radius: app.rr(14)
            color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
            clip: true
            visible: app.currentWall !== ""

            Image {
                anchors.fill: parent
                source: app.currentStill !== "" ? "file://" + app.currentStill : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1200
                opacity: app.wallBusy ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: app.animNormal; easing.type: Easing.OutCubic } }
            }
        }
    }

    Card {
        app: settingsRoot.app
        title: "Moving wallpapers"
        desc: (app.cfg.wallMotion === "never"
               ? "Videos and GIFs stay still: their still frame is shown."
               : app.cfg.wallMotion === "empty"
               ? "They play only while nothing is open on the workspace, and rest as soon as a window is."
               : "They play all the time.")
              + (app.cfg.wallMotion === "never" ? "" : " They always pause for fullscreen apps and games, while the screen is locked, and on battery.")
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Always", "Empty desktop", "Never"]
                current: app.cfg.wallMotion === "never" ? 2 : app.cfg.wallMotion === "empty" ? 1 : 0
                onPicked: i => app.setting("wallMotion", ["always", "empty", "never"][i])
            }
        ]
    }

    SectionLabel { app: settingsRoot.app; text: "Library" }

    Card {
        app: settingsRoot.app
        title: wallPage.tab === "live"
               ? wallPage.lives.length + (wallPage.lives.length === 1 ? " live wallpaper" : " live wallpapers")
               : wallPage.pictures.length + (wallPage.pictures.length === 1 ? " picture" : " pictures")
        desc: wallPage.tab === "live"
              ? (wallPage.lives.length > 0
                 ? "Videos and GIFs from ~/Pictures/wallpapers. The desktop plays them; the colours come from a still of each."
                 : "No live wallpapers yet. Put videos (MP4, WebM, MKV, MOV) or GIFs in ~/Pictures/wallpapers and reopen this page.")
              : (wallPage.pictures.length > 0
                 ? "From ~/Pictures/wallpapers. New files show up the next time this page opens."
                 : "No pictures yet. Put images in ~/Pictures/wallpapers and reopen this page.")
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Random", "Open folder"]
                onPicked: i => {
                    if (i === 0) {
                        // one from this tab, not the one in use
                        const pool = wallPage.shown.filter(p => p !== app.currentWall)
                        if (pool.length) app.applyWallpaper(pool[Math.floor(Math.random() * pool.length)])
                    }
                    else app.run("xdg-open \"$HOME/Pictures/wallpapers\"")
                }
            }
        ]

        // Pictures or Live
        Seg {
            app: settingsRoot.app
            options: ["Pictures  " + wallPage.pictures.length, "Live  " + wallPage.lives.length]
            current: wallPage.tab === "live" ? 1 : 0
            onPicked: i => wallPage.tab = i === 1 ? "live" : "pictures"
        }

        Grid {
            id: wallGrid
            Layout.fillWidth: true
            Layout.topMargin: 4
            columns: 3
            spacing: 10
            readonly property real cellW: (width - spacing * (columns - 1)) / columns

            Repeater {
                model: wallPage.shown
                delegate: Rectangle {
                    id: thumb
                    required property var modelData
                    readonly property bool isCurrent: modelData === app.currentWall

                    width: wallGrid.cellW
                    height: width * 9 / 16
                    radius: app.rr(12)
                    color: Qt.rgba(app.cFg.r, app.cFg.g, app.cFg.b, 0.08)
                    clip: true
                    border.width: isCurrent ? 3 : thHov.hovered ? 2 : 0
                    border.color: isCurrent ? app.cBlue : app.cFg

                    HoverHandler { id: thHov }

                    Image {
                        anchors.fill: parent
                        anchors.margins: thumb.border.width
                        // (a moving wallpaper's still)
                        source: app.stillOf(thumb.modelData) ? "file://" + app.stillOf(thumb.modelData) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 360
                    }
                    // a moving one: a play badge in the corner
                    Rectangle {
                        visible: app.isMovingWall(thumb.modelData)
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        width: 24; height: 24
                        radius: app.rr(12)
                        color: Qt.rgba(0, 0, 0, 0.55)
                        Text {
                            anchors.centerIn: parent
                            text: "play_arrow"
                            color: "white"
                            font.family: "Material Symbols Rounded"
                            font.pixelSize: app.fs(16)
                        }
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
                        radius: app.rr(10)
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
                            font.family: Theme.uiFont
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
