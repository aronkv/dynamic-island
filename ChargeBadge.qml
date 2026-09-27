import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Idle "plugged in" badge left of the island: just the green bolt shape —
// no disc — with a soft dark halo in the bolt's own shape so it reads on
// any wallpaper. While charging, a light streak runs up through the bolt
// (clipped to the bolt via a mask) every ~2 s. Fully charged (plugged in,
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

    // Soft dark halo in the bolt's own shape: a black bolt blurred inside
    // a box big enough for the blur to fade out (no disc, no ring).
    Item {
        anchors.centerIn: parent
        width: 64
        height: 64
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 20
        }
        BoltShape {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: badge.shift
            width: 34
            height: 34
            visible: badge.charging
            color: Qt.rgba(0, 0, 0, 0.9)
        }
        PlugShape {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: badge.shift
            width: 32
            height: 32
            visible: !badge.charging
            color: Qt.rgba(0, 0, 0, 0.9)
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

    // Light streak, masked to the bolt shape.
    Item {
        id: shine
        anchors.fill: bolt
        visible: false
        layer.enabled: true
        Rectangle {
            id: band
            width: parent.width
            height: 10
            y: parent.height
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.9) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        SequentialAnimation {
            running: badge.charging && badge.shown && !Theme.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { target: band; property: "y"; from: shine.height; to: -band.height; duration: 1100; easing.type: Easing.InOutSine }
            // Long rest between sweeps: each sweep re-renders the layered
            // mask effect every frame (~10 % CPU when it looped every 2 s).
            PauseAnimation { duration: 4500 }
        }
    }
    BoltShape {
        id: boltMask
        anchors.fill: bolt
        color: "#ffffff"
        visible: false
        layer.enabled: true
    }
    MultiEffect {
        anchors.fill: bolt
        visible: badge.charging
        source: shine
        maskEnabled: true
        maskSource: boltMask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.0
        maskThresholdMax: 1.0
        maskSpreadAtMax: 0.0
    }
}
