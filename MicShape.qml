import QtQuick
import QtQuick.Shapes

// Filled microphone (SF Symbols "mic.fill" proportions) in a 24×24 grid,
// scaled to the item size — the privacy badge glyph, drawn like BoltShape
// instead of Adwaita's thin outline icon.
Shape {
    id: mic
    property color color: "#ff9f0a"
    implicitWidth: 24
    implicitHeight: 24
    preferredRendererType: Shape.CurveRenderer
    readonly property real s: Math.min(width, height) / 24

    // Capsule body.
    ShapePath {
        fillColor: mic.color
        strokeColor: "transparent"
        scale: Qt.size(mic.s, mic.s)
        startX: 8.4; startY: 5.6
        PathArc { x: 15.6; y: 5.6; radiusX: 3.6; radiusY: 3.6 }
        PathLine { x: 15.6; y: 11.4 }
        PathArc { x: 8.4; y: 11.4; radiusX: 3.6; radiusY: 3.6 }
        PathLine { x: 8.4; y: 5.6 }
    }
    // Stand: U-shaped yoke, stem and foot.
    ShapePath {
        fillColor: "transparent"
        strokeColor: mic.color
        strokeWidth: 2 * mic.s
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        scale: Qt.size(mic.s, mic.s)
        startX: 5.4; startY: 10.8
        PathArc { x: 18.6; y: 10.8; radiusX: 6.6; radiusY: 6.6; direction: PathArc.Counterclockwise }
        PathMove { x: 12; y: 17.6 }
        PathLine { x: 12; y: 21 }
        PathMove { x: 8.6; y: 21 }
        PathLine { x: 15.4; y: 21 }
    }
}
