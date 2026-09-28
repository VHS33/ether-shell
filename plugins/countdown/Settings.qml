import QtQuick
import "Countdown.mjs" as C

// Countdown's settings: what the event is, and its date.  Saved with
// ether.set() as you finish each field (Enter, or clicking away).
Column {
    id: s
    property var ether                          // given by Ether Shell
    spacing: 10

    component Field: Column {
        id: f
        property string label
        property string value
        property string hint
        property bool bad: false
        signal done(string text)
        width: parent ? parent.width : 300
        spacing: 4
        Text { text: f.label; color: s.ether.dim; font.family: s.ether.font; font.pixelSize: s.ether.fs(11); font.bold: true }
        Rectangle {
            width: Math.min(parent.width, 320); height: 36; radius: 18
            color: Qt.rgba(s.ether.fg.r, s.ether.fg.g, s.ether.fg.b, 0.08)
            border.width: input.activeFocus || f.bad ? 1 : 0
            border.color: f.bad ? s.ether.red : s.ether.accent
            TextInput {
                id: input
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14; rightMargin: 14 }
                text: f.value
                color: s.ether.fg
                font.family: s.ether.font
                font.pixelSize: s.ether.fs(13)
                selectByMouse: true
                onEditingFinished: f.done(text)
                Text { anchors.fill: parent; visible: !parent.text; text: f.hint; color: s.ether.faint; font: parent.font; verticalAlignment: Text.AlignVCenter }
            }
        }
    }

    Field {
        label: "The event"
        value: s.ether.settings.title || ""
        hint: "New Year"
        onDone: t => s.ether.set("title", t.trim())
    }
    Field {
        id: dateField
        label: "Its date (year-month-day)"
        value: s.ether.settings.date || ""
        hint: C.nextNewYear(new Date())
        bad: value !== "" && C.parseDay(value) === null
        onDone: t => {
            // only a real date is saved; otherwise the field says so
            if (t.trim() === "" || C.parseDay(t) !== null) { s.ether.set("date", t.trim()); dateField.bad = false }
            else dateField.bad = true
        }
    }
}
