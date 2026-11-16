import QtQuick
import QtQuick.Shapes

// Compact live-activity indicator at the left of the idle pill. Shows the
// running timer / pomodoro / stopwatch (progress ring + time). Screen recording and low battery have their own badges
// outside the pill (RecordingBadge.qml, BatteryBadge.qml).
// Click → the expanded activity view (signal `openRequested`).
Item {
    id: chip
    property var store: null
    property color accent: "#ffffff"
    signal openRequested()

    readonly property string kind: !store ? ""
        : store.timerActive ? "timer" : ""
    readonly property bool shown: kind !== ""
    readonly property bool paused: !!store && store.paused
    // Pomodoro breaks read green, everything else follows the accent.
    readonly property color tint: store && store.mode === "pomodoro" && store.phase !== "Focus" ? Theme.green : accent

    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: 22
    visible: shown

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Paused: two bars in place of the ring.
        Row {
            visible: chip.kind === "timer" && chip.paused
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Rectangle { width: 4; height: 13; radius: 1.5; color: chip.tint }
            Rectangle { width: 4; height: 13; radius: 1.5; color: chip.tint }
        }

        // Timer: progress ring (stopwatch: a quarter arc that spins slowly).
        Item {
            visible: chip.kind === "timer" && !chip.paused
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.width: 2.5
                border.color: Qt.rgba(chip.tint.r, chip.tint.g, chip.tint.b, 0.25)
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                rotation: chip.store && chip.store.mode === "stopwatch" ? (chip.store.elapsed / 1000 % 60) * 6 : 0
                ShapePath {
                    strokeWidth: 2.5
                    strokeColor: chip.tint
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 8
                        centerY: 8
                        radiusX: 6.75
                        radiusY: 6.75
                        startAngle: -90
                        sweepAngle: !chip.store ? 0
                            : chip.store.mode === "stopwatch" ? 90
                            : 360 * (1 - chip.store.progress)
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !chip.store ? ""
                : chip.kind === "timer" ? chip.store.format(chip.store.mode === "stopwatch" ? chip.store.elapsed : chip.store.remaining)
                : ""
            color: chip.tint
            opacity: chip.paused ? 0.6 : 1
            font.pixelSize: 13
            font.weight: 600
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -4
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.openRequested()
    }
}
