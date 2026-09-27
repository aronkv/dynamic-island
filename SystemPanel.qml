import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// System monitor (displayState "system", SUPER+M): CPU (total + per-core
// bars), memory, temperatures + fan, network down/up, disk, top processes.
// Tiles carry 60-second sparklines (Shape + PathSvg). Esc closes.
FocusScope {
    id: panel
    property var mon: null
    property bool active: false
    property color accent: "#ffffff"
    signal closeRequested()

    onActiveChanged: if (active) forceActiveFocus()
    Keys.onEscapePressed: panel.closeRequested()

    component Spark: Shape {
        id: sp
        property var values: []
        property real maxValue: 1
        property color lineColor: "#ffffff"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1.6
            strokeColor: sp.lineColor
            fillColor: Qt.rgba(sp.lineColor.r, sp.lineColor.g, sp.lineColor.b, 0.14)
            PathSvg {
                path: {
                    const v = sp.values
                    if (!v || v.length < 2) return ""
                    const w = sp.width, h = sp.height, n = 60
                    const mx = Math.max(sp.maxValue, 1e-9)
                    const x0 = w - (v.length - 1) * (w / (n - 1))
                    let d = ""
                    for (let i = 0; i < v.length; i++) {
                        const x = x0 + i * (w / (n - 1))
                        const y = h - Math.min(1, v[i] / mx) * (h - 2) - 1
                        d += (i === 0 ? "M " : " L ") + x.toFixed(1) + " " + y.toFixed(1)
                    }
                    return d + " L " + w + " " + h + " L " + x0.toFixed(1) + " " + h + " Z"
                }
            }
        }
    }

    component Tile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property string detail: ""
        default property alias extra: slot.data
        Layout.fillWidth: true
        implicitHeight: 96
        radius: Theme.radiusMedium
        color: Theme.card
        clip: true

        Item { id: slot; anchors.fill: parent }

        Column {
            x: 12
            y: 10
            spacing: 1
            Text {
                text: tile.label
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 10
                font.weight: 600
                font.letterSpacing: 0.5
                font.family: Theme.fontText
            }
            Text {
                text: tile.value
                color: "#ffffff"
                font.pixelSize: 20
                font.weight: 600
                font.family: Theme.font
                font.features: { "tnum": 1 }
            }
            Text {
                visible: text !== ""
                text: tile.detail
                color: "#ffffff"
                opacity: 0.5
                font.pixelSize: 10
                font.family: Theme.fontText
            }
        }
    }

    readonly property real netMax: {
        if (!mon) return 1
        const all = mon.rxHist.concat(mon.txHist)
        return Math.max(64 * 1024, all.length ? Math.max.apply(null, all) : 1)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "System"
                color: "#ffffff"
                font.pixelSize: 17
                font.weight: 700
                font.family: Theme.font
            }
            Item { Layout.fillWidth: true }
            Text {
                text: panel.mon && panel.mon.fanRpm > 0 ? "Fan " + panel.mon.fanRpm + " rpm" : ""
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 11
                font.family: Theme.fontText
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            Tile {
                label: "CPU"
                value: panel.mon ? Math.round(panel.mon.cpu * 100) + "%" : ""
                detail: panel.mon ? panel.mon.cores.length + " threads" : ""
                Spark {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 44
                    values: panel.mon ? panel.mon.cpuHist : []
                    lineColor: panel.accent
                }
                // Per-core bars, top right.
                Row {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 3
                    Repeater {
                        model: panel.mon ? panel.mon.cores : []
                        Rectangle {
                            required property real modelData
                            width: 4
                            height: 22
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(2, parent.height * modelData)
                                radius: 2
                                color: "#ffffff"
                                opacity: 0.85
                            }
                        }
                    }
                }
            }

            Tile {
                label: "MEMORY"
                value: panel.mon ? panel.mon.bytes(panel.mon.memUsed) : ""
                detail: panel.mon ? "of " + panel.mon.bytes(panel.mon.memTotal) + (panel.mon.swapUsed > 16 * 1048576 ? " · swap " + panel.mon.bytes(panel.mon.swapUsed) : "") : ""
                Spark {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 44
                    values: panel.mon ? panel.mon.memHist : []
                    lineColor: Theme.green
                }
            }

            Tile {
                label: "TEMPERATURE"
                value: panel.mon ? Math.round(panel.mon.cpuTemp) + "°C" : ""
                detail: panel.mon && panel.mon.ssdTemp > 0 ? "CPU · SSD " + Math.round(panel.mon.ssdTemp) + "°C" : "CPU"
                Spark {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 44
                    values: panel.mon ? panel.mon.tempHist : []
                    maxValue: 100
                    lineColor: panel.mon && panel.mon.cpuTemp >= 80 ? Theme.red : Theme.orange
                }
            }

            Tile {
                label: "NETWORK" + (panel.mon && panel.mon.iface ? " · " + panel.mon.iface : "")
                value: panel.mon ? "↓ " + panel.mon.bytes(panel.mon.rxRate) + "/s" : ""
                detail: panel.mon ? "↑ " + panel.mon.bytes(panel.mon.txRate) + "/s" : ""
                Spark {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 44
                    values: panel.mon ? panel.mon.rxHist : []
                    maxValue: panel.netMax
                    lineColor: Theme.blue
                }
                Spark {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 44
                    values: panel.mon ? panel.mon.txHist : []
                    maxValue: panel.netMax
                    lineColor: "#bf5af2"
                }
            }
        }

        // Disk
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: Theme.radiusMedium
            color: Theme.card
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10
                Text { text: "DISK"; color: "#ffffff"; opacity: 0.45; font.pixelSize: 10; font.weight: 600; font.family: Theme.fontText }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: Qt.rgba(1, 1, 1, 0.12)
                    Rectangle {
                        width: parent.width * (panel.mon ? panel.mon.diskUsed / Math.max(1, panel.mon.diskTotal) : 0)
                        height: parent.height
                        radius: 3
                        color: "#ffffff"
                    }
                }
                Text {
                    text: panel.mon ? panel.mon.bytes(panel.mon.diskUsed) + " / " + panel.mon.bytes(panel.mon.diskTotal) : ""
                    color: "#ffffff"
                    font.pixelSize: 11
                    font.weight: 600
                    font.family: Theme.fontText
                }
            }
        }

        // Top processes
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: procCol.implicitHeight + 16
            radius: Theme.radiusMedium
            color: Theme.card
            Column {
                id: procCol
                x: 12
                y: 8
                width: parent.width - 24
                spacing: 4
                Text { text: "TOP PROCESSES"; color: "#ffffff"; opacity: 0.45; font.pixelSize: 10; font.weight: 600; font.family: Theme.fontText }
                Repeater {
                    model: panel.mon ? panel.mon.procs : []
                    RowLayout {
                        required property var modelData
                        width: procCol.width
                        Text {
                            text: modelData.name
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: modelData.cpu.toFixed(1) + "%"
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: 600
                            font.family: Theme.fontText
                            font.features: { "tnum": 1 }
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 52
                        }
                        Text {
                            text: modelData.mem.toFixed(1) + "% mem"
                            color: "#ffffff"
                            opacity: 0.45
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: 72
                        }
                    }
                }
            }
        }
    }
}
