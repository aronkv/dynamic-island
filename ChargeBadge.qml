import QtQuick
import QtQuick.Shapes

// Idle "plugged in" badge left of the island: just the green bolt shape —
// no disc — with a soft dark halo in the bolt's own shape so it reads on
// any wallpaper. While charging, a soft band of light sweeps up through
// the bolt every few seconds. Fully charged (plugged in,
// not charging) shows a charger-plug glyph instead of the bolt. The glyph
// sits a few px right of the badge's center (closer to the island).
Item {
    id: badge
    property bool charging: false
    property bool shown: false
    // Kept for compatibility with callers; not drawn anymore.
    property real percent: 0
    width: 44
    height: 44

    readonly property color green: "#32d74b"
    readonly property real shift: 6

    // Charger plug (prongs, rounded head, cable) in a 24×24 grid.
    component PlugShape: Shape {
        id: plug
        property color color: "#ffffff"
        readonly property real k: width / 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath {   // prongs
            fillColor: plug.color
            strokeColor: "transparent"
            scale: Qt.size(plug.k, plug.k)
            startX: 8.3; startY: 2.5
            PathLine { x: 10.3; y: 2.5 }
            PathLine { x: 10.3; y: 7.5 }
            PathLine { x: 8.3; y: 7.5 }
            PathLine { x: 8.3; y: 2.5 }
            PathMove { x: 13.7; y: 2.5 }
            PathLine { x: 15.7; y: 2.5 }
            PathLine { x: 15.7; y: 7.5 }
            PathLine { x: 13.7; y: 7.5 }
            PathLine { x: 13.7; y: 2.5 }
        }
        ShapePath {   // head, tapering into the cable
            fillColor: plug.color
            strokeColor: plug.color
            strokeWidth: 1.2
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(plug.k, plug.k)
            startX: 6; startY: 7.5
            PathLine { x: 18; y: 7.5 }
            PathLine { x: 18; y: 12 }
            PathQuad { x: 13.5; y: 17; controlX: 18; controlY: 16.5 }
            PathLine { x: 10.5; y: 17 }
            PathQuad { x: 6; y: 12; controlX: 6; controlY: 16.5 }
            PathLine { x: 6; y: 7.5 }
        }
        ShapePath {   // cable
            fillColor: "transparent"
            strokeColor: plug.color
            strokeWidth: 2.2
            capStyle: ShapePath.RoundCap
            scale: Qt.size(plug.k, plug.k)
            startX: 12; startY: 17
            PathLine { x: 12; y: 22 }
        }
    }

    // Soft dark halo in the glyph's own shape, so it reads on any
    // wallpaper. Used to be a blurred offscreen layer (MultiEffect); after a
    // fullscreen game was closed that layer came back as a grey box behind
    // the bolt. Now: the bolt's outline stroked several times, wide and
    // faint to narrow and darker (round joins), which fades out evenly from
    // the edge — scaled-up copies made a stepped, uneven rim.
    Repeater {
        model: [{ w: 12, a: 0.03 }, { w: 9, a: 0.04 }, { w: 6.5, a: 0.06 }, { w: 4, a: 0.08 }, { w: 2, a: 0.12 }]
        BoltShape {
            required property var modelData
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: badge.shift
            width: 28
            height: 28
            visible: badge.charging
            color: "transparent"
            outline: Qt.rgba(0, 0, 0, modelData.a)
            outlineWidth: modelData.w * 24 / 28   // path is scaled to 28 px
        }
    }
    // Same stroked-outline halo for the plug. Its three ShapePaths would
    // overlap (and double the alpha where they meet), so the halo strokes
    // one closed silhouette of the whole glyph instead — prongs, head and
    // cable in a single path. Scaled-up copies (the old halo) gave an
    // uneven, offset rim.
    component PlugHalo: Shape {
        id: halo
        property color outline: "black"
        property real outlineWidth: 2
        readonly property real k: width / 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: halo.outline
            strokeWidth: halo.outlineWidth
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(halo.k, halo.k)
            PathSvg {
                path: "M 8.3 2.5 L 10.3 2.5 L 10.3 6.9 L 13.7 6.9 L 13.7 2.5 L 15.7 2.5 L 15.7 6.9 L 18.6 6.9 "
                    + "L 18.6 12 Q 18.6 17.1 13.5 17.6 L 13.1 17.6 L 13.1 22 L 12.8 22.8 L 12 23.1 "
                    + "L 11.2 22.8 L 10.9 22 L 10.9 17.6 L 10.5 17.6 Q 5.4 17.1 5.4 12 L 5.4 6.9 L 8.3 6.9 Z"
            }
        }
    }
    Repeater {
        model: [{ w: 12, a: 0.03 }, { w: 9, a: 0.04 }, { w: 6.5, a: 0.06 }, { w: 4, a: 0.08 }, { w: 2, a: 0.12 }]
        PlugHalo {
            required property var modelData
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: badge.shift
            width: 26
            height: 26
            visible: !badge.charging
            outline: Qt.rgba(0, 0, 0, modelData.a)
            outlineWidth: modelData.w * 24 / 26   // path is scaled to 26 px
        }
    }

    PlugShape {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: badge.shift
        width: 26
        height: 26
        visible: !badge.charging
        color: badge.green
    }

    BoltShape {
        id: bolt
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: badge.shift
        visible: badge.charging
        width: 28
        height: 28
        color: badge.green
    }

    // While charging, every few seconds a band of light sweeps up through
    // the bolt (charge flowing in). The band
    // is the bolt drawn again in a light green inside plain rectangular
    // clips that move up — no offscreen layer or mask (those came back as
    // a grey box after a fullscreen game). Five nested clips, wide/faint
    // to narrow/bright, give the band soft edges.
    Item {
        id: sweep
        anchors.fill: bolt
        visible: badge.charging && pos > -0.5
        property real pos: -1          // band centre, 0 = bottom … 1 = top
        readonly property real centreY: height * (1 - pos)
        Repeater {
            model: [{ h: 16, a: 0.14 }, { h: 12.5, a: 0.18 }, { h: 9, a: 0.22 }, { h: 6, a: 0.28 }, { h: 3, a: 0.35 }]
            Item {
                required property var modelData
                x: 0
                width: sweep.width
                y: sweep.centreY - modelData.h / 2
                height: modelData.h
                clip: true
                BoltShape {
                    x: 0
                    y: -parent.y
                    width: sweep.width
                    height: sweep.height
                    color: Qt.rgba(0.85, 1, 0.88, modelData.a)
                }
            }
        }
    }

    SequentialAnimation {
        running: badge.charging && badge.shown && !Theme.reduceMotion
        loops: Animation.Infinite
        PauseAnimation { duration: 600 }
        NumberAnimation { target: sweep; property: "pos"; from: -0.3; to: 1.3; duration: 900; easing.type: Easing.InOutSine }
        PropertyAction { target: sweep; property: "pos"; value: -1 }
        PauseAnimation { duration: 3500 }
    }
}
