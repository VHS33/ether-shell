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
    visible: settingsWin.page === 17
    readonly property int pageNo: 17
    spacing: 4

    SectionLabel { app: settingsRoot.app; text: "Holidays" }

    Card {
        app: settingsRoot.app
        title: "Show holidays"
        desc: "Tints the day behind major US holidays and names them when you select the day."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Off", "On"]
                current: app.calHolidays ? 1 : 0
                onPicked: i => app.setting("calHolidays", i === 1)
            }
        ]
    }


    SectionLabel { app: settingsRoot.app; text: "Layout" }

    Card {
        app: settingsRoot.app
        title: "Week starts on"
        desc: "The first column of the calendar in the sidebar."
        trailing: [
            Seg {
                app: settingsRoot.app
                options: ["Sunday", "Monday"]
                current: app.calWeekStart
                onPicked: i => app.setting("calWeekStart", i)
            }
        ]
    }
}
