import QtQuick
import QtQuick.Shapes

// Compact live-activity indicator at the left of the idle pill. Shows the
// most important one: timer / pomodoro / stopwatch (progress ring + time)
// > rain soon. Screen recording and low battery have their own badges
// outside the pill (RecordingBadge.qml, BatteryBadge.qml).
// Click → the expanded activity view (signal `openRequested`).
Item {
    id: chip
    property var store: null
    property var weather: null
    property bool rainEnabled: true
    property color accent: "#ffffff"
    signal openRequested()

    readonly property string kind: !store ? ""
        : store.timerActive ? "timer"
        : (rainEnabled && weather && weather.rainSoon) ? "rain" : ""
    readonly property bool shown: kind !== ""

    implicitWidth: shown ? row.implicitWidth : 0
    implicitHeight: 22
    visible: shown

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

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

        Text {
            visible: chip.kind === "rain"
            anchors.verticalCenter: parent.verticalCenter
            text: "🌧"
            font.pixelSize: 13
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: !chip.store ? ""
                : chip.kind === "timer" ? chip.store.format(chip.store.mode === "stopwatch" ? chip.store.elapsed : chip.store.remaining)
                : chip.kind === "rain" && chip.weather ? (chip.weather.rainInMinutes <= 1 ? "Rain now" : "Rain " + chip.weather.rainInMinutes + "m")
                : ""
            color: "#ffffff"
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
        onClicked: chip.openRequested()
    }
}
