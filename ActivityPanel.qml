import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Expanded live activities (displayState "activity", opened from the pill
// chip): recording (elapsed + Stop) and the running timer / pomodoro /
// stopwatch (big time, progress ring, pause/resume, +1 min, stop). When
// nothing runs, quick starters: 5 / 10 / 25 min, stopwatch, pomodoro, record.
Item {
    id: panel
    property var store: null
    property var weather: null
    property color accent: "#ffffff"
    signal closeRequested()

    component Pill: Rectangle {
        id: pill
        property string label: ""
        property color tint: Theme.card
        property color textColor: "#ffffff"
        signal clicked()
        implicitWidth: pillText.implicitWidth + 28
        implicitHeight: 34
        radius: 17
        color: pillMouse.pressed ? Qt.lighter(tint, 1.3) : tint
        scale: pillMouse.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 120 } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.textColor
            font.pixelSize: 12
            font.weight: 600
            font.family: Theme.fontText
        }
        MouseArea { id: pillMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pill.clicked() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // ── Recording ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: panel.store && panel.store.recording
            spacing: 10
            Rectangle { width: 10; height: 10; radius: 5; color: "#ff453a" }
            Text {
                text: "Recording"
                color: "#ffffff"
                font.pixelSize: 15
                font.weight: 700
                font.family: Theme.font
            }
            Text {
                text: panel.store ? panel.store.format(panel.store.recordElapsed) : ""
                color: "#ff453a"
                font.pixelSize: 15
                font.weight: 600
                font.family: Theme.fontText
                font.features: { "tnum": 1 }
            }
            Item { Layout.fillWidth: true }
            Pill { label: "Stop"; tint: "#ff453a"; onClicked: panel.store.stopRecording() }
        }

        // ── Timer / pomodoro / stopwatch ──────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: panel.store && panel.store.timerActive
            spacing: 14

            Item {
                width: 64
                height: 64
                Rectangle {
                    anchors.fill: parent
                    radius: 32
                    color: "transparent"
                    border.width: 5
                    border.color: Qt.rgba(panel.accent.r, panel.accent.g, panel.accent.b, 0.2)
                }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeWidth: 5
                        strokeColor: panel.accent
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: 32
                            centerY: 32
                            radiusX: 29.5
                            radiusY: 29.5
                            startAngle: -90
                            sweepAngle: !panel.store ? 0 : panel.store.mode === "stopwatch" ? 360 : 360 * (1 - panel.store.progress)
                        }
                    }
                }
            }

            ColumnLayout {
                spacing: 0
                Layout.fillWidth: true
                Text {
                    text: panel.store ? panel.store.phase + (panel.store.mode === "pomodoro" ? " · #" + (panel.store.pomodoroCount + 1) : "") + (panel.store.paused ? " · Paused" : "") : ""
                    color: "#ffffff"
                    opacity: 0.55
                    font.pixelSize: 12
                    font.family: Theme.fontText
                }
                Text {
                    text: !panel.store ? "" : panel.store.format(panel.store.mode === "stopwatch" ? panel.store.elapsed : panel.store.remaining)
                    color: "#ffffff"
                    font.pixelSize: 34
                    font.weight: 300
                    font.family: Theme.font
                    font.features: { "tnum": 1 }
                }
            }

            ColumnLayout {
                spacing: 6
                Pill { label: panel.store && panel.store.paused ? "Resume" : "Pause"; onClicked: panel.store.togglePause() }
                Pill { visible: panel.store && panel.store.mode !== "stopwatch"; label: "+1 min"; onClicked: panel.store.addMinute() }
            }
            Pill { label: "Stop"; tint: Theme.cardElevated; textColor: "#ff453a"; onClicked: panel.store.stopTimer() }
        }

        // ── Rain ──────────────────────────────────────────────────────
        Text {
            visible: panel.weather && panel.weather.rainSoon
            text: "🌧  Rain expected in about " + (panel.weather ? Math.max(1, panel.weather.rainInMinutes) : 0) + " min"
            color: "#ffffff"
            opacity: 0.8
            font.pixelSize: 13
            font.family: Theme.fontText
        }

        // ── Quick start ───────────────────────────────────────────────
        Text {
            visible: panel.store && !panel.store.timerActive
            text: "START"
            color: "#ffffff"
            opacity: 0.4
            font.pixelSize: 10
            font.weight: 600
            font.letterSpacing: 0.5
            font.family: Theme.fontText
        }
        Flow {
            Layout.fillWidth: true
            visible: panel.store && !panel.store.timerActive
            spacing: 8
            Pill { label: "5 min"; onClicked: panel.store.startTimer(300) }
            Pill { label: "10 min"; onClicked: panel.store.startTimer(600) }
            Pill { label: "25 min"; onClicked: panel.store.startTimer(1500) }
            Pill { label: "Stopwatch"; onClicked: panel.store.startStopwatch() }
            Pill { label: "Pomodoro"; onClicked: panel.store.startPomodoro() }
            Pill {
                visible: panel.store && !panel.store.recording
                label: "● Record screen"
                textColor: "#ff453a"
                onClicked: { panel.store.startRecording(); panel.closeRequested() }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
