import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// OSD content for volume, brightness, Caps Lock and mic mute.
//  • Level kinds (volume / brightness): one tall white slider, no text —
//    the black speaker / sun sits inside the fill on the left. The fill is
//    already at the value when the OSD appears (no slide-in); while it's
//    visible, changes ease in 120 ms. The sun turns ±30° per brightness
//    step (spin()), only when the brightness actually moved.
//  • Toggle kinds (capslock / mic): the island stays idle-pill sized and
//    shows only a capsule with the icon — dark + white icon when off;
//    Caps Lock on = white capsule + black icon, mic muted = red + white.
Item {
    id: osd
    // "volume" | "brightness" | "capslock" | "mic"
    property string kind: "volume"
    property real level: 0          // 0..1 (volume/brightness)
    property bool muted: false      // volume muted
    property bool on: false         // capslock on / mic muted
    property bool shown: false

    readonly property bool isLevel: kind === "volume" || kind === "brightness"

    // No width animation while the OSD is appearing.
    property bool snap: true
    onShownChanged: {
        snap = true
        if (shown) { snapTimer.restart(); pop.restart() }
    }
    Timer { id: snapTimer; interval: 250; onTriggered: osd.snap = false }

    property real sunAngle: 0
    function spin(direction) { sunAngle += direction * 30 }

    onOnChanged: pop.restart()
    SequentialAnimation {
        id: pop
        NumberAnimation { target: osd.isLevel ? iconSlot : toggleIcon; property: "scale"; to: 0.82; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: osd.isLevel ? iconSlot : toggleIcon; property: "scale"; to: 1.0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
    }

    // ── Level slider ─────────────────────────────────────────────────
    Rectangle {
        id: track
        visible: osd.isLevel
        anchors.fill: parent
        anchors.margins: 10
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.18)

        Rectangle {
            id: fill
            readonly property real value: osd.kind === "volume" && osd.muted ? 0 : Math.max(0, Math.min(1, osd.level))
            height: parent.height
            width: Math.max(height, parent.width * value)
            radius: height / 2
            color: "#ffffff"
            Behavior on width {
                enabled: !osd.snap
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }
        }

        Item {
            id: iconSlot
            x: (track.height - width) / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24

            // Speaker: black body, waves lit by level, X when muted.
            Item {
                anchors.fill: parent
                visible: osd.kind === "volume"
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "#000000"
                        strokeColor: "#000000"
                        strokeWidth: 1.2
                        joinStyle: ShapePath.RoundJoin
                        startX: 2.5; startY: 9.5
                        PathLine { x: 6; y: 9.5 }
                        PathLine { x: 10.5; y: 5.5 }
                        PathLine { x: 10.5; y: 18.5 }
                        PathLine { x: 6; y: 14.5 }
                        PathLine { x: 2.5; y: 14.5 }
                        PathLine { x: 2.5; y: 9.5 }
                    }
                }
                Repeater {
                    model: 3
                    Shape {
                        required property int index
                        anchors.fill: parent
                        visible: !osd.muted
                        preferredRendererType: Shape.CurveRenderer
                        opacity: osd.level > index / 3 + 0.001 ? 1 : 0.2
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: "#000000"
                            strokeWidth: 1.9
                            capStyle: ShapePath.RoundCap
                            PathAngleArc {
                                moveToStart: true
                                centerX: 11; centerY: 12
                                radiusX: 3.6 + index * 3.2; radiusY: radiusX
                                startAngle: -42; sweepAngle: 84
                            }
                        }
                    }
                }
                Repeater {
                    model: [45, -45]
                    Rectangle {
                        required property var modelData
                        visible: osd.muted
                        x: 16.2; y: 7.5
                        width: 1.9; height: 9
                        radius: 1
                        rotation: modelData
                        color: "#000000"
                    }
                }
            }

            // Sun: black core + 8 rays, turns with each step.
            Item {
                id: sun
                anchors.fill: parent
                visible: osd.kind === "brightness"
                rotation: osd.sunAngle
                Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Rectangle {
                    anchors.centerIn: parent
                    width: 9; height: 9
                    radius: 4.5
                    color: "#000000"
                }
                Repeater {
                    model: 8
                    Item {
                        required property int index
                        anchors.fill: parent
                        rotation: index * 45
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 1.5
                            width: 2.2
                            height: 4
                            radius: 1.1
                            color: "#000000"
                        }
                    }
                }
            }
        }
    }

    // ── Toggle capsule (Caps Lock / mic) ─────────────────────────────
    Rectangle {
        id: capsule
        visible: !osd.isLevel
        anchors.fill: parent
        anchors.margins: 4
        radius: height / 2
        color: !osd.on ? "transparent"
            : osd.kind === "mic" ? Theme.red : "#ffffff"
        Behavior on color { ColorAnimation { duration: 200 } }
        readonly property color glyph: osd.on && osd.kind === "capslock" ? "#000000" : "#ffffff"

        Item {
            id: toggleIcon
            anchors.centerIn: parent
            width: 20
            height: 20

            Shape {
                anchors.fill: parent
                visible: osd.kind === "capslock"
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: osd.on ? capsule.glyph : "transparent"
                    strokeColor: capsule.glyph
                    strokeWidth: 1.8
                    joinStyle: ShapePath.RoundJoin
                    scale: Qt.size(20 / 24, 20 / 24)
                    startX: 12; startY: 3.5
                    PathLine { x: 20; y: 11.5 }
                    PathLine { x: 15.5; y: 11.5 }
                    PathLine { x: 15.5; y: 15.5 }
                    PathLine { x: 8.5; y: 15.5 }
                    PathLine { x: 8.5; y: 11.5 }
                    PathLine { x: 4; y: 11.5 }
                    PathLine { x: 12; y: 3.5 }
                }
                ShapePath {
                    fillColor: capsule.glyph
                    strokeColor: capsule.glyph
                    strokeWidth: 1.2
                    joinStyle: ShapePath.RoundJoin
                    scale: Qt.size(20 / 24, 20 / 24)
                    startX: 8.5; startY: 18
                    PathLine { x: 15.5; y: 18 }
                    PathLine { x: 15.5; y: 20.5 }
                    PathLine { x: 8.5; y: 20.5 }
                    PathLine { x: 8.5; y: 18 }
                }
            }

            Item {
                anchors.centerIn: parent
                width: 17
                height: 17
                visible: osd.kind === "mic"
                IconImage {
                    id: micIcon
                    anchors.fill: parent
                    source: "image://icon/" + (osd.on ? "microphone-sensitivity-muted-symbolic" : "audio-input-microphone-symbolic")
                    visible: false
                    layer.enabled: true
                    smooth: true
                    mipmap: true
                }
                Rectangle { id: micFill; anchors.fill: micIcon; color: capsule.glyph; visible: false }
                MultiEffect {
                    anchors.fill: micIcon
                    source: micFill
                    maskEnabled: true
                    maskSource: micIcon
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.0
                    maskThresholdMax: 1.0
                    maskSpreadAtMax: 0.0
                }
            }
        }
    }
}
