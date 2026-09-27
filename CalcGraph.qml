import QtQuick
import QtQuick.Shapes

// Small function plot for the calculator: f(x) = left − right side of an
// equation / inequality over `range`, the x axis (f = 0), roots as dots,
// and — for inequalities — the solution intervals shaded along the x axis.
// Hovering shows a crosshair with the (x, f(x)) readout.
Rectangle {
    id: graph
    property var analysis: null     // CalcEngine.analyze() result
    property color accent: "#ff9f0a"
    radius: 16
    color: Theme.card
    clip: true

    readonly property real xMin: analysis ? analysis.range[0] : -10
    readonly property real xMax: analysis ? analysis.range[1] : 10
    readonly property int samples: 240

    // Sampled points + a robust y range (ignores poles / huge spikes).
    readonly property var points: {
        const out = []
        if (!analysis) return out
        for (let i = 0; i <= samples; i++) {
            const x = xMin + (xMax - xMin) * i / samples
            let y = NaN
            try { y = analysis.f(x) } catch (e) {}
            out.push([x, y])
        }
        return out
    }
    readonly property var yRange: {
        const ys = points.map(p => p[1]).filter(v => isFinite(v)).sort((a, b) => a - b)
        if (ys.length === 0) return [-1, 1]
        let lo = ys[Math.floor(ys.length * 0.03)], hi = ys[Math.ceil(ys.length * 0.97) - 1]
        lo = Math.min(lo, 0); hi = Math.max(hi, 0)          // always show the x axis
        if (hi - lo < 1e-9) { lo -= 1; hi += 1 }
        const pad = (hi - lo) * 0.12
        return [lo - pad, hi + pad]
    }

    readonly property real padX: 8
    function px(x) { return padX + (x - xMin) / (xMax - xMin) * (width - 2 * padX) }
    function py(y) { return (yRange[1] - y) / (yRange[1] - yRange[0]) * height }

    // Solution intervals (inequalities).
    Repeater {
        model: graph.analysis && graph.analysis.kind === "inequality" ? graph.analysis.intervals : []
        Rectangle {
            required property var modelData
            readonly property real l: Math.max(graph.xMin, isFinite(modelData[0]) ? modelData[0] : graph.xMin)
            readonly property real r: Math.min(graph.xMax, isFinite(modelData[1]) ? modelData[1] : graph.xMax)
            x: graph.px(l)
            width: Math.max(2, graph.px(r) - graph.px(l))
            y: 0
            height: graph.height
            color: Qt.rgba(0.2, 0.84, 0.29, 0.14)
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: graph.py(0) - 2
                height: 4
                radius: 2
                color: "#32d74b"
            }
        }
    }

    // x axis (f = 0) and y axis (x = 0) when in range.
    Rectangle {
        x: 0
        width: parent.width
        y: graph.py(0)
        height: 1
        color: Qt.rgba(1, 1, 1, 0.3)
    }
    Rectangle {
        visible: graph.xMin < 0 && graph.xMax > 0
        x: graph.px(0)
        width: 1
        y: 0
        height: parent.height
        color: Qt.rgba(1, 1, 1, 0.15)
    }

    // The curve (breaks at poles / undefined points).
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 2
            strokeColor: graph.accent
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg {
                path: {
                    let d = ""
                    let pen = false
                    const [ylo, yhi] = graph.yRange
                    const span = yhi - ylo
                    for (const [x, y] of graph.points) {
                        if (!isFinite(y) || y < ylo - span * 2 || y > yhi + span * 2) { pen = false; continue }
                        d += (pen ? " L " : " M ") + graph.px(x).toFixed(1) + " " + graph.py(y).toFixed(1)
                        pen = true
                    }
                    return d
                }
            }
        }
    }

    // Roots.
    Repeater {
        model: graph.analysis ? graph.analysis.roots : []
        Rectangle {
            required property real modelData
            visible: modelData >= graph.xMin && modelData <= graph.xMax
            width: 8
            height: 8
            radius: 4
            x: graph.px(modelData) - 4
            y: graph.py(0) - 4
            color: "#ffffff"
            border.color: graph.accent
            border.width: 2
        }
    }

    // Range labels.
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 5
        text: Math.round(graph.xMin * 100) / 100
        color: "#ffffff"
        opacity: 0.35
        font.pixelSize: 9
    }
    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 5
        text: Math.round(graph.xMax * 100) / 100
        color: "#ffffff"
        opacity: 0.35
        font.pixelSize: 9
    }

    // Hover crosshair + readout.
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        readonly property real hx: graph.xMin + (Math.max(graph.padX, Math.min(graph.width - graph.padX, mouseX)) - graph.padX) / (graph.width - 2 * graph.padX) * (graph.xMax - graph.xMin)
        readonly property real hy: { try { return graph.analysis ? graph.analysis.f(hx) : NaN } catch (e) { return NaN } }
    }
    Rectangle {
        visible: hover.containsMouse
        x: graph.px(hover.hx)
        width: 1
        height: parent.height
        color: "#ffffff"
        opacity: 0.3
    }
    Rectangle {
        visible: hover.containsMouse && isFinite(hover.hy) && hover.hy >= graph.yRange[0] && hover.hy <= graph.yRange[1]
        x: graph.px(hover.hx) - 4
        y: graph.py(hover.hy) - 4
        width: 8
        height: 8
        radius: 4
        color: graph.accent
    }
    Rectangle {
        visible: hover.containsMouse
        x: Math.min(graph.width - width - 6, Math.max(6, graph.px(hover.hx) + 8))
        y: 6
        width: readout.implicitWidth + 12
        height: 20
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.6)
        Text {
            id: readout
            anchors.centerIn: parent
            text: "x " + (Math.round(hover.hx * 100) / 100) + "  ·  y " + (isFinite(hover.hy) ? Math.round(hover.hy * 100) / 100 : "—")
            color: "#ffffff"
            font.pixelSize: 10
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }
}
