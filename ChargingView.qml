import Quickshell.Services.UPower
import QtQuick

// Charger connected (displayState "charging"): the pill just says
// "Charging" with the percentage, while ChargingOutline (a sibling of
// notch, so it can reach the ears) runs a green light around the pill.
// Replaced the old expanded battery-glyph card (user request).
Item {
    id: root
    property var battery: null          // BatteryMonitor
    property bool shown: false

    readonly property real pct: battery ? Math.max(0, Math.min(100, battery.percentage)) : 0
    readonly property string label: !battery ? "" : battery.charging ? "Charging"
        : battery.state === UPowerDeviceState.FullyCharged ? "Charged" : "Plugged In"
    readonly property color green: "#32d74b"

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
            color: root.green
            font.pixelSize: 14
            font.weight: 700
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }
}
