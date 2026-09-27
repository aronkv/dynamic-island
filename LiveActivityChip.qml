import QtQuick
import QtQuick.Shapes

// Compact live-activity indicator at the left of the idle pill. Shows the
// most important one: recording (pulsing red dot + elapsed) > timer /
// pomodoro / stopwatch (progress ring + time) > low battery (≤ 10 %, red
// battery + percentage; tap re-shows the alert) > rain soon.
// Click → the expanded activity view (signal `openRequested`).
Item {
    id: chip
    property var store: null
    property var weather: null
    property var battery: null          // BatteryMonitor
    property bool rainEnabled: true
    property color accent: "#ffffff"
    signal openRequested()
    signal batteryRequested()

    readonly property string kind: !store ? ""
        : store.recording ? "record"
        : store.timerActive ? "timer"
        : (battery && battery.onBattery && battery.percentage <= 10) ? "battery"
        : (rainEnabled && weather && weather.rainSoon) ? "rain" : ""
    readonly property bool shown: kind !== ""

    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: 22
    visible: shown

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // Recording: pulsing red dot.
        Rectangle {
            visible: chip.kind === "record"
            anchors.verticalCenter: parent.verticalCenter
            width: 9
            height: 9
            radius: 4.5
            color: "#ff453a"
            SequentialAnimation on opacity {
                running: chip.kind === "record"
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        // Timer: progress ring (stopwatch: a full ring that spins slowly).
        Item {
            visible: chip.kind === "timer"
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(chip.accent.r, chip.accent.g, chip.accent.b, 0.25)
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                rotation: chip.store && chip.store.mode === "stopwatch" ? (chip.store.elapsed / 1000 % 60) * 6 : 0
                ShapePath {
                    strokeWidth: 2
                    strokeColor: chip.accent
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 8
                        centerY: 8
                        radiusX: 7
                        radiusY: 7
                        startAngle: -90
                        sweepAngle: !chip.store ? 0
                            : chip.store.mode === "stopwatch" ? 90
                            : 360 * (1 - chip.store.progress)
                    }
                }
            }
        }

        // Low battery (≤ 10 % on battery): a small red battery glyph.
        Item {
            visible: chip.kind === "battery"
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 11
            Rectangle {
                width: 19
                height: 11
                radius: 3.5
                color: "transparent"
                border.width: 1.2
                border.color: Qt.rgba(1, 0.27, 0.23, 0.8)
                Rectangle {
                    x: 2; y: 2
                    height: parent.height - 4
                    width: Math.max(2, (parent.width - 4) * (chip.battery ? chip.battery.percentage / 100 : 0))
                    radius: 1.5
                    color: "#ff453a"
                }
            }
            Rectangle { x: 20; y: 3.5; width: 1.8; height: 4; radius: 1; color: Qt.rgba(1, 0.27, 0.23, 0.8) }
        }

        Text {
            visible: chip.kind === "rain"
            anchors.verticalCenter: parent.verticalCenter
            text: "🌧"
            font.pixelSize: 13
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !chip.store ? ""
                : chip.kind === "record" ? chip.store.format(chip.store.recordElapsed)
                : chip.kind === "timer" ? chip.store.format(chip.store.mode === "stopwatch" ? chip.store.elapsed : chip.store.remaining)
                : chip.kind === "battery" && chip.battery ? Math.round(chip.battery.percentage) + "%"
                : chip.kind === "rain" && chip.weather ? (chip.weather.rainInMinutes <= 1 ? "Rain now" : "Rain " + chip.weather.rainInMinutes + "m")
                : ""
            color: chip.kind === "record" || chip.kind === "battery" ? "#ff453a" : "#ffffff"
            opacity: chip.store && chip.store.paused && chip.kind === "timer" ? 0.5 : 1
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
        onClicked: chip.kind === "battery" ? chip.batteryRequested() : chip.openRequested()
    }
}
