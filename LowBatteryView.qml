import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// Low-battery alert (displayState "lowbattery"), escalating with the level
// the battery just dropped to while on battery:
//   20 % — "Low Battery", yellow: remaining time + Low Power Mode toggle.
//   10 % — "Battery Low", orange: Low Power Mode is switched on for you.
//    5 % — "Battery Critical", red, the glyph and a red rim pulse; offers to
//          dim the display. Stays until dismissed or plugged in.
//    1 % — "Almost Empty", red, faster pulse; offers "Sleep Now" (locks
//          first). Stays until dismissed or plugged in.
// The same battery-glyph language as ChargingView, drained instead of filling.
Item {
    id: root
    property var battery: null          // BatteryMonitor
    property bool shown: false
    property int level: 20              // threshold that fired: 20 | 10 | 5 | 1
    property bool lowPowerOn: false
    signal dismissRequested()
    signal lowPowerRequested()
    signal dimRequested()
    signal sleepRequested()

    readonly property real pct: battery ? Math.max(0, Math.min(100, battery.percentage)) : level
    readonly property color tint: level >= 20 ? "#ffd60a" : level >= 10 ? "#ff9f0a" : "#ff453a"
    readonly property bool critical: level <= 5
    readonly property string title: level >= 20 ? "Low Battery"
        : level >= 10 ? "Battery Low"
        : level >= 5 ? "Battery Critical" : "Almost Empty"
    readonly property string remaining: {
        const t = battery ? battery.timeRemaining : 0
        if (!(t > 60)) return ""
        const h = Math.floor(t / 3600), m = Math.round((t % 3600) / 60)
        return h > 0 ? "about " + h + " h " + m + " min left" : "about " + m + " min left"
    }
    readonly property string subtitle: {
        if (level >= 20) return Math.round(pct) + "% remaining" + (remaining ? " · " + remaining : "") + (lowPowerOn ? " · Low Power on" : "")
        if (level >= 10) return "Plug in soon" + (remaining ? " · " + remaining : "") + (lowPowerOn ? " · Low Power on" : "")
        if (level >= 5) return "Connect your charger now" + (remaining ? " · " + remaining : "")
        return "Save your work — the laptop will shut down soon"
    }

    // Critical levels breathe: the glyph and the rim pulse (faster at 1 %).
    property real pulse: 1
    SequentialAnimation on pulse {
        running: root.shown && root.critical && !Theme.reduceMotion
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: root.level <= 1 ? 450 : 800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: root.level <= 1 ? 450 : 800; easing.type: Easing.InOutSine }
        onStopped: root.pulse = 1
    }

    // Drain animation each time the view appears: from a bit above the
    // level down to it.
    property real fill: 0
    onShownChanged: if (shown) drain.restart()
    NumberAnimation {
        id: drain
        target: root
        property: "fill"
        from: Math.min(1, root.pct / 100 + 0.12)
        to: root.pct / 100
        duration: Theme.reduceMotion ? 0 : 900
        easing.type: Easing.OutCubic
    }

    // Red rim just inside the island's outline (critical levels only).
    Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        color: "transparent"
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: 17
        bottomRightRadius: 17
        border.width: 2
        border.color: "#ff453a"
        visible: root.critical
        opacity: 0.25 + 0.55 * root.pulse
    }

    component ActionPill: Rectangle {
        id: pill
        property string label: ""
        property bool primary: false
        property color accent: "#ffffff"
        signal clicked()
        implicitWidth: pillText.implicitWidth + 26
        implicitHeight: 30
        radius: 15
        color: primary ? accent : (pillMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.1))
        scale: pillMouse.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 110 } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.primary ? "#000000" : "#ffffff"
            font.pixelSize: 12
            font.weight: 600
            font.family: "SF Pro Text"
        }
        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 22
        anchors.topMargin: 14
        anchors.bottomMargin: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // ── Battery glyph ─────────────────────────────────────────
            Item {
                implicitWidth: 58
                implicitHeight: 28
                opacity: root.critical ? 0.45 + 0.55 * root.pulse : 1

                Rectangle {
                    id: shell
                    width: 53
                    height: 28
                    radius: 8.5
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1.5
                    border.color: root.critical ? Qt.rgba(1, 0.27, 0.23, 0.7) : Qt.rgba(1, 1, 1, 0.35)

                    Item {
                        anchors.fill: parent
                        anchors.margins: 3
                        clip: true
                        Rectangle {
                            height: parent.height
                            // Always at least a visible sliver, even at 1 %.
                            width: Math.max(5, parent.width * root.fill)
                            radius: 5.5
                            color: root.tint
                        }
                    }
                }
                Rectangle {
                    anchors.left: shell.right
                    anchors.leftMargin: 2
                    anchors.verticalCenter: shell.verticalCenter
                    width: 3
                    height: 10
                    radius: 1.5
                    color: root.critical ? Qt.rgba(1, 0.27, 0.23, 0.7) : Qt.rgba(1, 1, 1, 0.35)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: root.title
                    color: root.critical ? "#ff453a" : "#ffffff"
                    font.pixelSize: 15
                    font.weight: 600
                    font.family: "SF Pro Display"
                }
                Text {
                    Layout.fillWidth: true
                    text: root.subtitle
                    color: "#ffffff"
                    opacity: 0.55
                    font.pixelSize: 11
                    font.family: "SF Pro Text"
                    elide: Text.ElideRight
                }
            }

            Row {
                Layout.alignment: Qt.AlignVCenter
                Text {
                    id: pctText
                    text: Math.round(root.pct)
                    color: root.tint
                    font.pixelSize: 26
                    font.weight: 700
                    font.family: "SF Pro Rounded"
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.baseline: pctText.baseline
                    text: "%"
                    color: root.tint
                    opacity: 0.8
                    font.pixelSize: 15
                    font.weight: 600
                    font.family: "SF Pro Rounded"
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Item { Layout.fillWidth: true }
            ActionPill {
                visible: root.level >= 20
                label: root.lowPowerOn ? "Low Power On" : "Low Power Mode"
                primary: !root.lowPowerOn
                accent: root.tint
                onClicked: root.lowPowerRequested()
            }
            ActionPill {
                visible: root.level === 5
                label: "Dim Display"
                primary: true
                accent: "#ff9f0a"
                onClicked: root.dimRequested()
            }
            ActionPill {
                visible: root.level <= 1
                label: "Sleep Now"
                primary: true
                accent: "#ff453a"
                onClicked: root.sleepRequested()
            }
            ActionPill {
                label: "Dismiss"
                onClicked: root.dismissRequested()
            }
        }
    }
}
