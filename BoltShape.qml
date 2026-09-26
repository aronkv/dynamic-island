import QtQuick
import QtQuick.Shapes

// Vector lightning bolt (SF Symbols "bolt.fill" proportions) in a 24×24
// grid, scaled to the item size. No installed icon theme ships a plain bolt,
// and a Canvas may never paint inside a hidden panel — hence a Shape.
Shape {
    id: bolt
    property color color: "#32d74b"
    property color outline: "transparent"
    property real outlineWidth: 0
    implicitWidth: 24
    implicitHeight: 24
    preferredRendererType: Shape.CurveRenderer
    readonly property real s: Math.min(width, height) / 24

    ShapePath {
        fillColor: bolt.color
        strokeColor: bolt.outline
        strokeWidth: bolt.outlineWidth
        joinStyle: ShapePath.RoundJoin
        scale: Qt.size(bolt.s, bolt.s)
        startX: 14; startY: 1.5
        PathLine { x: 4.2; y: 13.6 }
        PathLine { x: 11.2; y: 13.6 }
        PathLine { x: 9.8; y: 22.5 }
        PathLine { x: 19.8; y: 10.2 }
        PathLine { x: 12.8; y: 10.2 }
        PathLine { x: 14; y: 1.5 }
    }
}
