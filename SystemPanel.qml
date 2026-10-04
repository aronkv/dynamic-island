import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// System monitor (displayState "system", SUPER+M). Header: uptime + load.
// Six tiles (CPU with per-core bars and clock, GPU, memory, temperature +
// fan, network, power) carry 60-second sparklines (Shape + PathSvg with a
// fading gradient fill); then disk usage + read/write throughput and the
// top processes with a CPU bar each. Esc closes.
FocusScope {
    id: panel
    property var mon: null
    property var battery: null      // BatteryMonitor, for % and time left
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
        property bool filled: true
        preferredRendererType: Shape.CurveRenderer
        readonly property string line: {
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
            return d
        }
        readonly property real x0: sp.values && sp.values.length > 1 ? sp.width - (sp.values.length - 1) * (sp.width / 59) : 0
        // Area under the curve, fading out toward the bottom.
        ShapePath {
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: sp.height
                GradientStop { position: 0; color: Qt.rgba(sp.lineColor.r, sp.lineColor.g, sp.lineColor.b, sp.filled ? 0.28 : 0) }
                GradientStop { position: 1; color: Qt.rgba(sp.lineColor.r, sp.lineColor.g, sp.lineColor.b, 0) }
            }
            PathSvg { path: sp.line === "" ? "" : sp.line + " L " + sp.width + " " + sp.height + " L " + sp.x0.toFixed(1) + " " + sp.height + " Z" }
        }
        ShapePath {
            strokeWidth: 1.6
            strokeColor: sp.lineColor
            fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathSvg { path: sp.line }
        }
    }

    component Tile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property string unit: ""
        property string detail: ""
        default property alias extra: slot.data
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 92
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
            RowLayout {
                spacing: 2
                Text {
                    Layout.alignment: Qt.AlignBaseline
                    text: tile.value
                    color: "#ffffff"
                    font.pixelSize: 20
                    font.weight: 600
                    font.family: Theme.font
                    font.features: { "tnum": 1 }
                }
                Text {
                    Layout.alignment: Qt.AlignBaseline
                    visible: text !== ""
                    text: tile.unit
                    color: "#ffffff"
                    opacity: 0.6
                    font.pixelSize: 12
                    font.weight: 600
                    font.family: Theme.font
                }
            }
            Text {
                visible: text !== ""
                text: tile.detail
                color: "#ffffff"
                opacity: 0.5
                font.pixelSize: 10
                font.family: Theme.fontText
                font.features: { "tnum": 1 }
            }
        }
    }

    component BottomSpark: Spark {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 40
    }

    readonly property real netMax: {
        if (!mon) return 1
        const all = mon.rxHist.concat(mon.txHist)
        return Math.max(64 * 1024, all.length ? Math.max.apply(null, all) : 1)
    }
    readonly property real diskMax: {
        if (!mon) return 1
        const all = mon.readHist.concat(mon.writeHist)
        return Math.max(1024 * 1024, all.length ? Math.max.apply(null, all) : 1)
    }
    readonly property real powerMax: {
        if (!mon || !mon.powerHist.length) return 15
        return Math.max(15, Math.max.apply(null, mon.powerHist) * 1.15)
    }
    function rate(b) { return mon ? mon.bytes(b) + "/s" : "" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                text: "System"
                color: "#ffffff"
                font.pixelSize: 17
                font.weight: 700
                font.family: Theme.font
            }
            Item { Layout.fillWidth: true }
            Text {
                text: panel.mon && panel.mon.uptime > 0
                    ? "Up " + panel.mon.duration(panel.mon.uptime) + "  ·  Load " + panel.mon.load.map(l => l.toFixed(2)).join("  ")
                    : ""
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 11
                font.family: Theme.fontText
                font.features: { "tnum": 1 }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            rowSpacing: 8
            columnSpacing: 8

            Tile {
                label: "CPU"
                value: panel.mon ? Math.round(panel.mon.cpu * 100) : ""
                unit: "%"
                detail: panel.mon ? panel.mon.cpuFreq.toFixed(2) + " GHz · " + panel.mon.cores.length + " threads" : ""
                BottomSpark {
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
                label: "GPU"
                value: panel.mon && panel.mon.hasGpu ? Math.round(panel.mon.gpuBusy * 100) : "—"
                unit: panel.mon && panel.mon.hasGpu ? "%" : ""
                detail: panel.mon && panel.mon.hasGpu ? Math.round(panel.mon.gpuFreq) + " / " + Math.round(panel.mon.gpuMaxFreq) + " MHz" : ""
                BottomSpark {
                    values: panel.mon ? panel.mon.gpuHist : []
                    lineColor: "#64d2ff"
                }
            }
            Tile {
                label: "MEMORY"
                value: panel.mon ? panel.mon.bytes(panel.mon.memUsed) : ""
                detail: panel.mon ? "of " + panel.mon.bytes(panel.mon.memTotal) + (panel.mon.swapUsed > 16 * 1048576 ? " · swap " + panel.mon.bytes(panel.mon.swapUsed) : "") : ""
                BottomSpark {
                    values: panel.mon ? panel.mon.memHist : []
                    lineColor: Theme.green
                }
            }
            Tile {
                label: "TEMPERATURE"
                value: panel.mon ? Math.round(panel.mon.cpuTemp) : ""
                unit: "°C"
                detail: panel.mon
                    ? "CPU" + (panel.mon.ssdTemp > 0 ? " · SSD " + Math.round(panel.mon.ssdTemp) + "°" : "")
                      + (panel.mon.fanRpm > 0 ? " · fan " + panel.mon.fanRpm + " rpm" : "")
                    : ""
                BottomSpark {
                    values: panel.mon ? panel.mon.tempHist : []
                    maxValue: 100
                    lineColor: panel.mon && panel.mon.cpuTemp >= 80 ? Theme.red : Theme.orange
                }
            }
            Tile {
                label: "NETWORK" + (panel.mon && panel.mon.iface ? " · " + panel.mon.iface : "")
                value: panel.mon ? "↓ " + panel.rate(panel.mon.rxRate) : ""
                detail: panel.mon ? "↑ " + panel.rate(panel.mon.txRate) : ""
                BottomSpark {
                    values: panel.mon ? panel.mon.rxHist : []
                    maxValue: panel.netMax
                    lineColor: Theme.blue
                }
                BottomSpark {
                    values: panel.mon ? panel.mon.txHist : []
                    maxValue: panel.netMax
                    lineColor: "#bf5af2"
                    filled: false
                }
            }
            Tile {
                label: "POWER"
                value: panel.mon && panel.mon.power > 0.05 ? panel.mon.power.toFixed(1) : "—"
                unit: panel.mon && panel.mon.power > 0.05 ? "W" : ""
                detail: {
                    const b = panel.battery
                    if (!b) return ""
                    const pct = Math.round(b.percentage) + "%"
                    return b.onBattery || b.charging ? pct + " · " + b.statusText : pct + " · on AC"
                }
                BottomSpark {
                    values: panel.mon ? panel.mon.powerHist : []
                    maxValue: panel.powerMax
                    lineColor: panel.mon && panel.mon.powerStatus === "Charging" ? Theme.green : Theme.yellow
                }
            }
        }

        // Disk: usage bar + live throughput of the root disk.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 58
            radius: Theme.radiusMedium
            color: Theme.card
            clip: true

            Spark {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: parent.width * 0.45
                height: 30
                values: panel.mon ? panel.mon.readHist : []
                maxValue: panel.diskMax
                lineColor: Theme.blue
                opacity: 0.8
            }
            Spark {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: parent.width * 0.45
                height: 30
                values: panel.mon ? panel.mon.writeHist : []
                maxValue: panel.diskMax
                lineColor: Theme.orange
                filled: false
                opacity: 0.8
            }

            Column {
                x: 12
                y: 9
                width: parent.width * 0.5
                spacing: 6
                RowLayout {
                    width: parent.width
                    spacing: 8
                    Text { text: "DISK" + (panel.mon && panel.mon.rootDisk ? " · " + panel.mon.rootDisk : ""); color: "#ffffff"; opacity: 0.45; font.pixelSize: 10; font.weight: 600; font.letterSpacing: 0.5; font.family: Theme.fontText }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: panel.mon ? panel.mon.bytes(panel.mon.diskUsed) + " / " + panel.mon.bytes(panel.mon.diskTotal) : ""
                        color: "#ffffff"
                        font.pixelSize: 11
                        font.weight: 600
                        font.family: Theme.fontText
                    }
                }
                Rectangle {
                    width: parent.width
                    height: 6
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
                    text: panel.mon ? "Read " + panel.rate(panel.mon.diskRead) + "  ·  Write " + panel.rate(panel.mon.diskWrite) : ""
                    color: "#ffffff"
                    opacity: 0.5
                    font.pixelSize: 10
                    font.family: Theme.fontText
                    font.features: { "tnum": 1 }
                }
            }
        }

        // Top processes, each with a CPU share bar.
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: procCol.implicitHeight + 18
            radius: Theme.radiusMedium
            color: Theme.card
            Column {
                id: procCol
                x: 12
                y: 9
                width: parent.width - 24
                spacing: 5
                Text { text: "TOP PROCESSES"; color: "#ffffff"; opacity: 0.45; font.pixelSize: 10; font.weight: 600; font.letterSpacing: 0.5; font.family: Theme.fontText }
                Repeater {
                    model: panel.mon ? panel.mon.procs : []
                    Item {
                        required property var modelData
                        width: procCol.width
                        height: 22
                        RowLayout {
                            width: parent.width
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
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width - 130
                            height: 2
                            radius: 1
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Rectangle {
                                width: parent.width * Math.min(1, modelData.cpu / 100)
                                height: parent.height
                                radius: 1
                                color: panel.accent
                                opacity: 0.8
                                Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }
            }
        }
    }
}
