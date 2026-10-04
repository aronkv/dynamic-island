import QtQuick

// Low-battery alert (displayState "lowbattery"): a compact pill like the
// charging one — what happened on the left, the level on the right in the
// level's colour — instead of the old expanded card with buttons (user
// request). Escalates with the threshold the battery just dropped to:
//   20 % — yellow, "Low Power On" (Power Saver switches on automatically)
//          or "Low Battery";
//   10 % — orange, "Battery Low";
//    5 % — red, "Connect Charger", the percentage pulses;
//    1 % — red, "Almost Empty", faster pulse.
// Collapses by itself; tapping the pill re-shows it (DynamicIsland).
Item {
    id: root
    property var battery: null          // BatteryMonitor
    property bool shown: false
    property int level: 20              // threshold that fired: 20 | 10 | 5 | 1
    property bool lowPowerOn: false

    readonly property real pct: battery ? Math.max(0, Math.min(100, battery.percentage)) : level
    readonly property color tint: level >= 20 ? "#ffd60a" : level >= 10 ? "#ff9f0a" : "#ff453a"
    readonly property bool critical: level <= 5
    readonly property string label: level >= 20 ? (lowPowerOn ? "Low Power On" : "Low Battery")
        : level >= 10 ? (lowPowerOn ? "Battery Low · Low Power" : "Battery Low")
        : level >= 5 ? "Connect Charger" : "Almost Empty"

    // Critical levels: the percentage breathes (faster at 1 %).
    property real pulse: 1
    SequentialAnimation on pulse {
        running: root.shown && root.critical && !Theme.reduceMotion
        loops: Animation.Infinite
        NumberAnimation { to: 0.35; duration: root.level <= 1 ? 450 : 800; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: root.level <= 1 ? 450 : 800; easing.type: Easing.InOutSine }
        onStopped: root.pulse = 1
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        Text {
            id: labelText
            text: root.label
            color: "#ffffff"
            font.pixelSize: 14
            font.weight: 600
            font.family: Theme.fontText
        }
        Item { width: parent.width - labelText.width - pctText.width; height: 1 }
        Text {
            id: pctText
            text: Math.round(root.pct) + "%"
            color: root.tint
            opacity: root.pulse
            font.pixelSize: 14
            font.weight: 700
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }
}
