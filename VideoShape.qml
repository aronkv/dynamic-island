import QtQuick
import QtQuick.Shapes

// Filled video camera (SF Symbols "video.fill" proportions) in a 24×24
// grid, scaled to the item size — the camera privacy badge glyph.
Shape {
    id: cam
    property color color: "#32d74b"
    implicitWidth: 24
    implicitHeight: 24
    preferredRendererType: Shape.CurveRenderer
    readonly property real s: Math.min(width, height) / 24

    // Body: rounded rectangle.
    ShapePath {
        fillColor: cam.color
        strokeColor: "transparent"
        scale: Qt.size(cam.s, cam.s)
        startX: 4.8; startY: 6
        PathLine { x: 12.6; y: 6 }
        PathArc { x: 15.4; y: 8.8; radiusX: 2.8; radiusY: 2.8 }
        PathLine { x: 15.4; y: 15.2 }
        PathArc { x: 12.6; y: 18; radiusX: 2.8; radiusY: 2.8 }
        PathLine { x: 4.8; y: 18 }
        PathArc { x: 2; y: 15.2; radiusX: 2.8; radiusY: 2.8 }
        PathLine { x: 2; y: 8.8 }
        PathArc { x: 4.8; y: 6; radiusX: 2.8; radiusY: 2.8 }
    }
    // Lens: a trapezoid with softened corners (round stroke join).
    ShapePath {
        fillColor: cam.color
        strokeColor: cam.color
        strokeWidth: 1.6 * cam.s
        joinStyle: ShapePath.RoundJoin
        scale: Qt.size(cam.s, cam.s)
        startX: 17; startY: 10.4
        PathLine { x: 21.2; y: 7.6 }
        PathLine { x: 21.2; y: 16.4 }
        PathLine { x: 17; y: 13.6 }
        PathLine { x: 17; y: 10.4 }
    }
}
