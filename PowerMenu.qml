import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes

// Power menu (displayState "power"): 1 Lock · 2 Sleep · 3 Log Out ·
// 4 Restart · 5 Shut Down · 6 Restart to BIOS (firmware setup). Nothing runs on a tap: hold the number key (or
// press-and-hold the button, or hold Enter on the selected one) and a ring
// fills around it; when it completes (~0.9 s) the action runs. Letting go
// early cancels and the ring drains back.
// Keyboard: 1–6 hold, ←/→ select, Enter hold, Esc closes.
FocusScope {
    id: menu
    property bool active: false
    signal closeRequested()
    signal lockRequested()

    property int currentIndex: 0
    property int holdIndex: -1
    property real holdProgress: 0
    readonly property int holdDuration: 900

    readonly property var actions: [
        { key: "lock",     label: "Lock",      icon: "system-lock-screen-symbolic",  danger: false },
        { key: "sleep",    label: "Sleep",     icon: "weather-clear-night-symbolic", danger: false },
        { key: "logout",   label: "Log Out",   icon: "system-log-out-symbolic",      danger: true },
        { key: "reboot",   label: "Restart",   icon: "system-reboot-symbolic",       danger: true },
        { key: "poweroff", label: "Shut Down", icon: "system-shutdown-symbolic",     danger: true },
        { key: "bios",     label: "BIOS",      icon: "application-x-firmware-symbolic", danger: true }
    ]

    onActiveChanged: {
        cancelHold()
        if (active) { currentIndex = 0; forceActiveFocus(); uptimeProc.running = true }
    }

    function startHold(i) {
        if (holdIndex === i) return
        currentIndex = i
        holdIndex = i
        drain.stop()
        fill.from = holdProgress
        fill.duration = holdDuration * (1 - holdProgress)
        fill.restart()
    }
    function endHold(i) {
        if (holdIndex !== i) return
        if (holdProgress >= 1) return
        cancelHold()
    }
    function cancelHold() {
        fill.stop()
        holdIndex = -1
        drain.from = holdProgress
        drain.restart()
    }

    NumberAnimation {
        id: fill
        target: menu
        property: "holdProgress"
        to: 1
        easing.type: Easing.Linear
        onFinished: if (menu.holdIndex >= 0 && menu.holdProgress >= 1) menu.run(menu.actions[menu.holdIndex].key)
    }
    NumberAnimation {
        id: drain
        target: menu
        property: "holdProgress"
        to: 0
        duration: 220
        easing.type: Easing.OutCubic
    }

    function run(key) {
        holdIndex = -1
        holdProgress = 0
        menu.closeRequested()
        if (key === "lock") { menu.lockRequested(); return }
        // Lock first, then suspend a moment later, so the machine never
        // wakes up unlocked.
        if (key === "sleep") { menu.lockRequested(); suspendTimer.restart(); return }
        const cmds = {
            logout: ["hyprctl", "dispatch", "hl.dsp.exit()"],
            reboot: ["systemctl", "reboot"],
            poweroff: ["systemctl", "poweroff"],
            bios: ["systemctl", "reboot", "--firmware-setup"]
        }
        actionProc.command = cmds[key]
        actionProc.running = true
    }

    Process { id: actionProc }

    Timer {
        id: suspendTimer
        interval: 600
        onTriggered: { actionProc.command = ["systemctl", "suspend"]; actionProc.running = true }
    }

    // Uptime for the header line.
    property string uptimeText: ""
    Process {
        id: uptimeProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const secs = parseFloat(text.split(" ")[0])
                if (!isFinite(secs)) return
                const d = Math.floor(secs / 86400)
                const h = Math.floor(secs % 86400 / 3600)
                const m = Math.floor(secs % 3600 / 60)
                menu.uptimeText = "Up " + (d > 0 ? d + " d " : "") + (h > 0 ? h + " h " : "") + m + " min"
            }
        }
    }

    Keys.onPressed: (event) => {
        if (event.isAutoRepeat) { event.accepted = true; return }
        const n = event.key - Qt.Key_1
        if (n >= 0 && n < actions.length) { startHold(n); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { startHold(currentIndex); event.accepted = true; return }
        if (event.key === Qt.Key_Left) { cancelHold(); currentIndex = Math.max(0, currentIndex - 1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { cancelHold(); currentIndex = Math.min(actions.length - 1, currentIndex + 1); event.accepted = true }
        else if (event.key === Qt.Key_Escape) { menu.closeRequested(); event.accepted = true }
    }
    Keys.onReleased: (event) => {
        if (event.isAutoRepeat) { event.accepted = true; return }
        const n = event.key - Qt.Key_1
        if (n >= 0 && n < actions.length) { endHold(n); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { endHold(currentIndex); event.accepted = true }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: Quickshell.env("USER") || "Session"
                color: "#ffffff"
                font.pixelSize: 15
                font.weight: 700
                font.family: Theme.font
                Layout.fillWidth: true
            }
            Text {
                text: menu.uptimeText
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 11
                font.family: Theme.fontText
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: menu.actions

                Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property bool focused: menu.currentIndex === index
                    readonly property bool holding: menu.holdIndex === index
                    readonly property real progress: holding || (menu.holdIndex === -1 && menu.currentIndex === index) ? menu.holdProgress : 0
                    readonly property color tint: modelData.danger ? Theme.red : "#ffffff"
                    Layout.fillWidth: true
                    implicitHeight: 92

                    // Hover/press live on the whole slot, NOT inside `btn`:
                    // btn scales on focus, and a MouseArea inside a scaling
                    // item grows/shrinks its own hit area, so at the edge
                    // entered/exited fired back and forth (the flicker).
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: if (menu.holdIndex === -1) menu.currentIndex = slot.index
                        onPressed: menu.startHold(slot.index)
                        onReleased: menu.endHold(slot.index)
                        onCanceled: menu.endHold(slot.index)
                        onExited: if (pressed) menu.endHold(slot.index)
                    }

                    Item {
                        id: btn
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 2
                        width: 58
                        height: 58
                        scale: slot.holding ? 0.92 + 0.08 * (1 - slot.progress) : (slot.focused ? 1.04 : 1)
                        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                        // Soft focus ring around the selected button.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: width / 2
                            color: "transparent"
                            border.width: 1.5
                            border.color: Qt.rgba(1, 1, 1, 0.35)
                            opacity: slot.focused && slot.progress === 0 ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 160 } }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: slot.focused ? Qt.rgba(1, 1, 1, 0.16) : Theme.card
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        // Fill that rises with the hold progress.
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width * slot.progress
                            height: width
                            radius: width / 2
                            color: slot.tint
                            opacity: 0.9
                        }

                        // Progress ring.
                        Shape {
                            anchors.fill: parent
                            anchors.margins: -5
                            visible: slot.progress > 0
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeWidth: 3
                                strokeColor: slot.tint
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    centerX: 34
                                    centerY: 34
                                    radiusX: 32.5
                                    radiusY: 32.5
                                    startAngle: -90
                                    sweepAngle: 360 * slot.progress
                                }
                            }
                        }

                        IconImage {
                            id: icon
                            anchors.centerIn: parent
                            implicitSize: 22
                            source: "image://icon/" + slot.modelData.icon
                            visible: false
                            layer.enabled: true
                            smooth: true
                            mipmap: true
                        }
                        Rectangle {
                            id: iconFill
                            anchors.fill: icon
                            color: slot.progress > 0.5 && !slot.modelData.danger ? "#000000" : "#ffffff"
                            visible: false
                        }
                        MultiEffect {
                            anchors.fill: icon
                            source: iconFill
                            maskEnabled: true
                            maskSource: icon
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 0.0
                            maskThresholdMax: 1.0
                            maskSpreadAtMax: 0.0
                        }

                        // Number badge.
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -3
                            anchors.topMargin: -3
                            width: 18
                            height: 18
                            radius: 9
                            color: slot.focused ? "#ffffff" : Theme.cardElevated
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: slot.index + 1
                                color: slot.focused ? "#000000" : "#ffffff"
                                Behavior on color { ColorAnimation { duration: 150 } }
                                font.pixelSize: 10
                                font.weight: 700
                                font.family: Theme.fontText
                            }
                        }
                    }

                    // Label cross-fades to "Hold…" while holding.
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: btn.bottom
                        anchors.topMargin: 10
                        width: parent.width
                        height: 14
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: slot.modelData.label
                            color: "#ffffff"
                            opacity: slot.holding ? 0 : (slot.focused ? 1 : 0.6)
                            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 150 } }
                            font.pixelSize: 11
                            font.weight: 600
                            font.family: Theme.fontText
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Hold…"
                            color: slot.modelData.danger ? Theme.red : "#ffffff"
                            opacity: slot.holding ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 150 } }
                            font.pixelSize: 11
                            font.weight: 600
                            font.family: Theme.fontText
                        }
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Hold 1–6 (or press and hold a button) to confirm"
            color: "#ffffff"
            opacity: 0.35
            font.pixelSize: 10
            font.family: Theme.fontText
        }
    }
}
