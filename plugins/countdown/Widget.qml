import QtQuick
import "Countdown.mjs" as C

// Countdown: an example desktop widget.  It draws only what's inside: Ether
// Shell puts it in a card like the built-in widgets.  Its settings (the
// event and the date) are ether.settings, set on its settings page.
Column {
    id: w
    property var ether                          // given by Ether Shell
    spacing: 2

    property date now: new Date()
    Timer { interval: 600000; running: true; repeat: true; onTriggered: w.now = new Date() }   // (days change slowly)

    readonly property string title: (ether && ether.settings.title) || "New Year"
    readonly property var day: C.parseDay((ether && ether.settings.date) || C.nextNewYear(now))
    readonly property int days: day ? C.daysUntil(day, now) : 0

    Text {
        text: !w.day ? "?" : w.days >= 0 ? w.days : "\u2713"
        color: w.ether ? w.ether.accent : "white"
        font.family: w.ether ? w.ether.font : ""
        font.pixelSize: 48
        font.weight: Font.Light
    }
    Text {
        text: !w.day ? "Set a date in Settings, Plugins"
            : w.days > 1 ? "days until " + w.title
            : w.days === 1 ? "day until " + w.title
            : w.days === 0 ? w.title + " is today"
            : w.title + " has been"
        color: w.ether ? w.ether.fg : "white"
        font.family: w.ether ? w.ether.font : ""
        font.pixelSize: w.ether ? w.ether.fs(14) : 14
    }
    Text {
        visible: w.day !== null
        text: w.day ? Qt.formatDate(w.day, "dddd d MMMM yyyy") : ""
        color: w.ether ? w.ether.dim : "white"
        font.family: w.ether ? w.ether.font : ""
        font.pixelSize: w.ether ? w.ether.fs(11) : 11
    }
}
