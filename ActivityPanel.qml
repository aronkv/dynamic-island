import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// Expanded live activities (displayState "activity", opened from the pill
// chip). Recording: pulsing dot, elapsed time, round stop button. Timer /
// pomodoro / stopwatch: round pause / +1 / stop buttons on the left, the
// phase and a big time on the right, a progress bar underneath. When
// nothing runs: a row of equal start tiles (5 / 10 / 25 min, stopwatch,
// pomodoro, record).
Item {
    id: panel
    property var store: null
    property color accent: "#ffffff"
    signal closeRequested()

    readonly property bool running: !!store && store.timerActive
    readonly property bool isStopwatch: running && store.mode === "stopwatch"
    // Pomodoro breaks read green, everything else follows the accent.
    readonly property color tint: running && store.mode === "pomodoro" && store.phase !== "Focus" ? Theme.green : accent

    // Round icon button; `glyph` is "pause" | "play" | "stop" | "close" | text.
    component RoundButton: Item {
        id: rb
        property string glyph: ""
        property color fg: "#ffffff"
        property color bg: Theme.cardElevated
        signal clicked()
        implicitWidth: 46
        implicitHeight: 46
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: rbMouse.pressed ? Qt.lighter(rb.bg, 1.25) : rb.bg
            scale: rbMouse.pressed ? 0.92 : 1
            Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

            // Pause: two bars.
            Row {
                visible: rb.glyph === "pause"
                anchors.centerIn: parent
                spacing: 5
                Rectangle { width: 5; height: 17; radius: 1.5; color: rb.fg }
                Rectangle { width: 5; height: 17; radius: 1.5; color: rb.fg }
            }
            // Play: triangle, nudged right to look centred.
            Shape {
                visible: rb.glyph === "play"
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 2
                width: 16; height: 18
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: rb.fg
                    strokeColor: rb.fg
                    strokeWidth: 2
                    joinStyle: ShapePath.RoundJoin
                    startX: 1; startY: 1
                    PathLine { x: 15; y: 9 }
                    PathLine { x: 1; y: 17 }
                    PathLine { x: 1; y: 1 }
                }
            }
            // Stop: rounded square.
            Rectangle {
                visible: rb.glyph === "stop"
                anchors.centerIn: parent
                width: 15; height: 15; radius: 3
                color: rb.fg
            }
            // Close: an X.
            Item {
                visible: rb.glyph === "close"
                anchors.centerIn: parent
                width: 16; height: 16
                Rectangle { anchors.centerIn: parent; width: 19; height: 3; radius: 1.5; rotation: 45; color: rb.fg }
                Rectangle { anchors.centerIn: parent; width: 19; height: 3; radius: 1.5; rotation: -45; color: rb.fg }
            }
            Text {
                visible: ["pause", "play", "stop", "close"].indexOf(rb.glyph) === -1
                anchors.centerIn: parent
                text: rb.glyph
                color: rb.fg
                font { pixelSize: 15; weight: 700; family: Theme.fontText }
            }
        }
        MouseArea { id: rbMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }

    // Start tile: big value on top, caption under it.
    component StartTile: Item {
        id: tile
        property string value: ""
        property string caption: ""
        property color valueColor: "#ffffff"
        property bool dot: false
        signal clicked()
        Layout.fillWidth: true
        Layout.preferredHeight: 68
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: tileMouse.pressed ? Theme.cardElevated : Theme.card
            scale: tileMouse.pressed ? 0.95 : 1
            Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
            Item {
                id: valueBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: 12
                width: parent.width
                height: 26
                Text {
                    visible: !tile.dot
                    anchors.centerIn: parent
                    text: tile.value
                    color: tile.valueColor
                    font { pixelSize: 21; weight: 500; family: Theme.font; features: { "tnum": 1 } }
                }
                Rectangle {
                    visible: tile.dot
                    anchors.centerIn: parent
                    width: 16; height: 16; radius: 8
                    color: Theme.red
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: valueBox.bottom
                anchors.topMargin: 4
                text: tile.caption
                color: "#ffffff"
                opacity: 0.5
                font { pixelSize: 11; weight: 600; family: Theme.fontText }
            }
        }
        MouseArea { id: tileMouse; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 14

        // ── Recording ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: panel.store && panel.store.recording
            spacing: 12
            Rectangle {
                width: 12; height: 12; radius: 6
                color: Theme.red
                SequentialAnimation on opacity {
                    running: panel.visible && panel.store && panel.store.recording && !Theme.reduceMotion
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            ColumnLayout {
                spacing: 0
                Text {
                    text: "SCREEN RECORDING"
                    color: "#ffffff"
                    opacity: 0.5
                    font { pixelSize: 11; weight: 600; letterSpacing: 0.5; family: Theme.fontText }
                }
                Text {
                    text: panel.store ? panel.store.format(panel.store.recordElapsed) : ""
                    color: Theme.red
                    font { pixelSize: 26; weight: 400; family: Theme.font; features: { "tnum": 1 } }
                }
            }
            Item { Layout.fillWidth: true }
            RoundButton {
                glyph: "stop"
                fg: "#ffffff"
                bg: Theme.red
                onClicked: panel.store.stopRecording()
            }
        }

        // ── Timer / pomodoro / stopwatch ──────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: panel.running
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                RoundButton {
                    glyph: panel.store && panel.store.paused ? "play" : "pause"
                    fg: panel.tint
                    bg: Qt.rgba(panel.tint.r, panel.tint.g, panel.tint.b, 0.22)
                    onClicked: panel.store.togglePause()
                }
                RoundButton {
                    visible: !panel.isStopwatch
                    glyph: "+1"
                    onClicked: panel.store.addMinute()
                }
                RoundButton {
                    glyph: "close"
                    onClicked: panel.store.stopTimer()
                }

                Item { Layout.fillWidth: true }

                ColumnLayout {
                    spacing: -2
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: !panel.store ? "" : (panel.store.phase || "Timer").toUpperCase()
                            + (panel.store.mode === "pomodoro" ? "  ·  #" + (panel.store.pomodoroCount + 1) : "")
                            + (panel.store.paused ? "  ·  PAUSED" : "")
                        color: "#ffffff"
                        opacity: 0.5
                        font { pixelSize: 11; weight: 600; letterSpacing: 0.5; family: Theme.fontText }
                    }
                    Text {
                        Layout.alignment: Qt.AlignRight
                        text: !panel.store ? "" : panel.store.format(panel.isStopwatch ? panel.store.elapsed : panel.store.remaining)
                        color: panel.tint
                        opacity: panel.store && panel.store.paused ? 0.5 : 1
                        font { pixelSize: 44; weight: 300; family: Theme.font; features: { "tnum": 1 } }
                    }
                }
            }

            // Progress (countdowns only).
            Rectangle {
                Layout.fillWidth: true
                visible: !panel.isStopwatch
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.12)
                Rectangle {
                    height: parent.height
                    radius: 2
                    width: parent.width * (panel.store ? Math.min(1, Math.max(0, panel.store.progress)) : 0)
                    color: panel.tint
                }
            }
        }

        // ── Quick start ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: !panel.running
            spacing: 8
            StartTile { value: "5"; caption: "min"; onClicked: panel.store.startTimer(300) }
            StartTile { value: "10"; caption: "min"; onClicked: panel.store.startTimer(600) }
            StartTile { value: "25"; caption: "min"; onClicked: panel.store.startTimer(1500) }
            StartTile { value: "0:00"; caption: "Stopwatch"; onClicked: panel.store.startStopwatch() }
            StartTile { value: "25/5"; caption: "Pomodoro"; onClicked: panel.store.startPomodoro() }
            StartTile {
                visible: panel.store && !panel.store.recording
                dot: true
                caption: "Record"
                onClicked: { panel.store.startRecording(); panel.closeRequested() }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
