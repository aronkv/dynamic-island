import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

// Bluetooth device connected (displayState "bluetooth"): a compact pill
// like the Ethernet one — the device's icon and name on the left, its
// battery on the right when BlueZ reports one (often a moment after the
// connection, so it's bound live), else "Connected".
Item {
    id: root
    property bool shown: false
    property var device: null

    readonly property string name: {
        if (!device) return ""
        const n = device.deviceName
        return n && n.toUpperCase() !== device.address.toUpperCase() ? n : "Unknown device"
    }
    readonly property string detail: {
        if (!device || !device.batteryAvailable) return "Connected"
        // May come back as a 0..1 fraction rather than 0..100.
        const b = device.battery
        return Math.round((b > 0 && b <= 1) ? b * 100 : b) + "%"
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 18
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Item {
            id: glyph
            width: 18
            height: 18
            anchors.verticalCenter: parent.verticalCenter
            IconImage {
                id: icon
                anchors.fill: parent
                implicitSize: 18
                source: "image://icon/" + (root.device && root.device.icon ? root.device.icon : "bluetooth-symbolic")
                visible: false
                layer.enabled: true
            }
            Rectangle { id: iconFill; anchors.fill: icon; color: "#ffffff"; visible: false }
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
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width - glyph.width - detailText.width - 3 * parent.spacing)
            text: root.name
            elide: Text.ElideRight
            color: "#ffffff"
            font.pixelSize: 14
            font.weight: 600
            font.family: Theme.fontText
        }
        Item { width: parent.width - glyph.width - labelText.width - detailText.width - 3 * parent.spacing; height: 1 }
        Text {
            id: detailText
            anchors.verticalCenter: parent.verticalCenter
            text: root.detail
            color: "#ffffff"
            font.pixelSize: 14
            font.weight: 700
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }
}
