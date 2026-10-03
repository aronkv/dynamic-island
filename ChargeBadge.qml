import QtQuick
import QtQuick.Shapes

// Idle "plugged in" badge left of the island: just the green bolt shape —
// no disc — with a soft dark halo in the bolt's own shape so it reads on
// any wallpaper. While charging, the bolt briefly brightens every few
// seconds. Fully charged (plugged in,
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
    // wallpaper: a few larger, faint dark copies stacked under it. Used to
    // be a blurred offscreen layer (MultiEffect); after a fullscreen game
    // was closed that layer came back as a grey box behind the bolt.
    Repeater {
        model: [{ k: 1.35, a: 0.18 }, { k: 1.22, a: 0.25 }, { k: 1.1, a: 0.35 }]
        Item {
            required property var modelData
            anchors.fill: parent
            BoltShape {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: badge.shift
                width: 28 * modelData.k
                height: 28 * modelData.k
                visible: badge.charging
                color: Qt.rgba(0, 0, 0, modelData.a)
            }
            PlugShape {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: badge.shift
                width: 26 * modelData.k
                height: 26 * modelData.k
                visible: !badge.charging
                color: Qt.rgba(0, 0, 0, modelData.a)
            }
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
        // While charging, a brief brighten every few seconds (was a light
        // streak masked to the bolt — same layer problem as the halo).
        SequentialAnimation on color {
            running: badge.charging && badge.shown && !Theme.reduceMotion
            loops: Animation.Infinite
            ColorAnimation { to: "#b4f5bf"; duration: 550; easing.type: Easing.InOutSine }
            ColorAnimation { to: "#32d74b"; duration: 550; easing.type: Easing.InOutSine }
            PauseAnimation { duration: 4500 }
        }
    }
}
