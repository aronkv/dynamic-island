import QtQuick
import QtQuick.Shapes

// Green light running around the pill while ChargingView shows: in from
// the left ear's flare, down the left edge, along the bottom, up the right
// edge and out through the right ear (the top is the screen edge). A
// sibling of notch spanning notch plus both ears (`ear` px each side),
// since notch clips its own children. Follows notch's live size.
Item {
    id: root
    property real ear: 10
    property real cornerRadius: 18
    property bool shown: false

    readonly property color green: "#32d74b"
    readonly property real sw: 3.5
    readonly property real i: sw / 2               // inset: stroke stays on the pill
    readonly property real e: ear
    readonly property real er: e + i                // ear arc radius (concave flare)
    readonly property real r: Math.max(0, Math.min(cornerRadius, height / 2, (width - 2 * e) / 2) - i)
    readonly property real len: Math.PI * er                                   // two quarter ear arcs
        + 2 * Math.max(0, height - i - r - e)                                  // left + right edges
        + Math.max(0, width - 2 * e - 2 * i - 2 * r)                           // bottom
        + Math.PI * r                                                           // two bottom corners
    readonly property real seg: len / 3

    component Outline: Shape {
        id: outline
        property color color
        property var dashPattern: []
        property real dashOffset: 0
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        ShapePath {
            strokeColor: outline.color
            strokeWidth: root.sw
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            strokeStyle: outline.dashPattern.length ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: outline.dashPattern
            dashOffset: outline.dashOffset
            // Left ear: quarter circle centered (0, e), top → right.
            startX: 0; startY: root.e - root.er
            PathArc { x: root.er; y: root.e; radiusX: root.er; radiusY: root.er }
            PathLine { x: root.e + root.i; y: root.height - root.i - root.r }
            PathArc { x: root.e + root.i + root.r; y: root.height - root.i; radiusX: root.r; radiusY: root.r; direction: PathArc.Counterclockwise }
            PathLine { x: root.width - root.e - root.i - root.r; y: root.height - root.i }
            PathArc { x: root.width - root.e - root.i; y: root.height - root.i - root.r; radiusX: root.r; radiusY: root.r; direction: PathArc.Counterclockwise }
            PathLine { x: root.width - root.er; y: root.e }
            // Right ear: quarter circle centered (width, e), left → top.
            PathArc { x: root.width; y: root.e - root.er; radiusX: root.er; radiusY: root.er }
        }
    }

    // Faint full track, then the bright running segment on top.
    Outline {
        color: Qt.rgba(0.2, 0.84, 0.29, 0.18)
    }
    Outline {
        color: root.green
        // Dash units are stroke widths. One dash period = the whole path, so
        // the segment leaving through the right ear re-enters at the left
        // one with no blank gap between laps.
        dashPattern: [root.seg / root.sw, (root.len - root.seg) / root.sw]
        property real travel: 0
        dashOffset: -travel * root.len / root.sw
        NumberAnimation on travel {
            from: 0; to: 1
            duration: 1600
            loops: Animation.Infinite
            running: root.shown && !Theme.reduceMotion
        }
    }
}
