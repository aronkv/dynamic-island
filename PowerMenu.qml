import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Power menu (displayState "power"): 1 Lock · 2 Sleep · 3 Log Out ·
// 4 Restart · 5 Shut Down · 6 BIOS (restart into firmware setup).
// Click + confirm: Lock and Sleep run on one click. A dangerous action's
// first click opens its button into a red "Restart?" pill; a second
// click (or Enter, or the same number) runs it. Anything else — another
// button, an arrow key, Esc, or 3 s without input — folds it back.
// Keyboard: 1–6 / Enter activate, ←/→ select, Esc cancels then closes.
FocusScope {
    id: menu
    property bool active: false
    signal closeRequested()
    signal lockRequested()

    property int currentIndex: 0
    property int confirmIndex: -1
    // Slot under the mouse (-1 = none). The highlight follows it, else the
    // keyboard's currentIndex — one highlighted button at a time.
    property int hoverIndex: -1

    readonly property var actions: [
        { key: "lock",     label: "Lock",      ask: "",           icon: "system-lock-screen-symbolic",     danger: false },
        { key: "sleep",    label: "Sleep",     ask: "",           icon: "weather-clear-night-symbolic",    danger: false },
        { key: "logout",   label: "Log Out",   ask: "Log Out?",   icon: "system-log-out-symbolic",         danger: true },
        { key: "reboot",   label: "Restart",   ask: "Restart?",   icon: "system-reboot-symbolic",          danger: true },
        { key: "poweroff", label: "Shut Down", ask: "Shut Down?", icon: "system-shutdown-symbolic",        danger: true },
        { key: "bios",     label: "BIOS",      ask: "BIOS?", icon: "application-x-firmware-symbolic", danger: true }
    ]

    onActiveChanged: {
        confirmIndex = -1
        hoverIndex = -1
        if (active) { currentIndex = 0; forceActiveFocus(); uptimeProc.running = true }
    }

    function activate(i) {
        currentIndex = i
        const a = actions[i]
        if (!a.danger || confirmIndex === i) { run(a.key); return }
        confirmIndex = i
        confirmTimer.restart()
    }
    function cancelConfirm() {
        confirmIndex = -1
        confirmTimer.stop()
    }

    Timer {
        id: confirmTimer
        interval: 3000
        onTriggered: menu.confirmIndex = -1
    }

    function run(key) {
        cancelConfirm()
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
        if (n >= 0 && n < actions.length) { activate(n); event.accepted = true; return }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { activate(currentIndex); event.accepted = true; return }
        if (event.key === Qt.Key_Left) { cancelConfirm(); currentIndex = Math.max(0, currentIndex - 1); event.accepted = true }
        else if (event.key === Qt.Key_Right) { cancelConfirm(); currentIndex = Math.min(actions.length - 1, currentIndex + 1); event.accepted = true }
        else if (event.key === Qt.Key_Escape) {
            if (confirmIndex >= 0) cancelConfirm()
            else menu.closeRequested()
            event.accepted = true
        }
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

        // Slots touch (spacing 0) so the cursor never crosses a dead gap
        // between two buttons.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 0

            Repeater {
                model: menu.actions

                Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property bool focused: menu.hoverIndex >= 0 ? menu.hoverIndex === index : menu.currentIndex === index
                    readonly property bool confirming: menu.confirmIndex === index
                    readonly property real pillWidth: askText.implicitWidth + 58
                    Layout.preferredWidth: confirming ? pillWidth + 10 : (menu.confirmIndex >= 0 ? 62 : 70)
                    implicitHeight: 92
                    Behavior on Layout.preferredWidth { enabled: !Theme.reduceMotion; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                    // On the whole (unscaled) slot, so hover never flickers.
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            menu.hoverIndex = slot.index
                            if (menu.confirmIndex === -1) menu.currentIndex = slot.index
                        }
                        onExited: if (menu.hoverIndex === slot.index) menu.hoverIndex = -1
                        onClicked: menu.activate(slot.index)
                    }

                    // The button: a circle that opens into a red pill while
                    // asking for confirmation.
                    Rectangle {
                        id: btn
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 2
                        width: slot.confirming ? slot.pillWidth : 58
                        height: 58
                        radius: 29
                        color: slot.confirming ? Theme.red
                            : mouse.pressed ? Qt.rgba(1, 1, 1, 0.24)
                            : slot.focused ? Qt.rgba(1, 1, 1, 0.16) : Theme.card
                        // Only the confirm pill's width animates; hover/focus
                        // colours change instantly (animated ones crossed
                        // mid-way while the cursor moved and read as flicker).
                        Behavior on width { enabled: !Theme.reduceMotion; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Item {
                                width: 22
                                height: 22
                                anchors.verticalCenter: parent.verticalCenter
                                IconImage {
                                    id: icon
                                    anchors.fill: parent
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
                                    color: "#ffffff"
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
                            }

                            Text {
                                id: askText
                                anchors.verticalCenter: parent.verticalCenter
                                text: slot.modelData.ask
                                visible: opacity > 0
                                opacity: slot.confirming ? 1 : 0
                                width: slot.confirming ? implicitWidth : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 180 } }
                                color: "#ffffff"
                                font.pixelSize: 13
                                font.weight: 700
                                font.family: Theme.fontText
                            }
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
                            Text {
                                anchors.centerIn: parent
                                text: slot.index + 1
                                color: slot.focused ? "#000000" : "#ffffff"
                                font.pixelSize: 10
                                font.weight: 700
                                font.family: Theme.fontText
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: btn.bottom
                        anchors.topMargin: 10
                        text: slot.confirming ? "Click again" : slot.modelData.label
                        color: slot.confirming ? Theme.red : "#ffffff"
                        opacity: slot.focused || slot.confirming ? 1 : 0.6
                        font.pixelSize: 11
                        font.weight: 600
                        font.family: Theme.fontText
                    }
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Click or press 1–6 · Log Out, Restart, Shut Down and BIOS ask again"
            color: "#ffffff"
            opacity: 0.35
            font.pixelSize: 10
            font.family: Theme.fontText
        }
    }
}
