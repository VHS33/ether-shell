import QtQuick

// The bar's shared graph (Settings > Bar > Resource monitor > Graphs: One
// graph): a line per stat that has a graph, each in its own colour, drawn
// over each other.  Four fixed lines rather than a list, so a new reading
// only moves points instead of rebuilding anything.
Item {
    id: sg
    property var app
    implicitWidth: app.fs(76)
    implicitHeight: app.fs(16)

    Sparkline {
        anchors.fill: parent
        visible: sg.app.statGraphed(sg.app.statCpu)
        points: sg.app.cpuHist
        color: sg.app.statCpuColour
    }
    Sparkline {
        anchors.fill: parent
        visible: sg.app.statGraphed(sg.app.statMem)
        points: sg.app.memHist
        color: sg.app.statMemColour
    }
    Sparkline {
        anchors.fill: parent
        visible: sg.app.gpuOk && sg.app.statGraphed(sg.app.statGpu)
        points: sg.app.gpuHist
        color: sg.app.statGpuColour
    }
    Sparkline {
        anchors.fill: parent
        visible: sg.app.gpuOk && sg.app.statGraphed(sg.app.statTemp)
        points: sg.app.tempHist
        color: sg.app.statTempColour
    }
}
