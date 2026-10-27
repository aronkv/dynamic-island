import Quickshell.Widgets
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes

// Bluetooth device connected (displayState "bluetooth"): a compact pill
// like the Ethernet one — the device's icon and name on the left, its
// battery on the right when BlueZ reports one (often a moment after the
// connection, so it's bound live), else "Connected". When audio moves to
// the device, a ring around the icon sweeps up to the output volume, so
// the volume reads as part of the connection instead of a separate OSD.
Item {
    id: root
    property bool shown: false
    property var device: null
    property string iconSource: "image://icon/bluetooth-symbolic"
    property real volume: -1            // 0..1, -1 = not the audio output

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

    // Starts empty each time the pill shows and sweeps up once the notch
    // has opened; later volume changes follow with the same easing.
    property real ringLevel: 0
    readonly property real ringTarget: shown && volume >= 0 ? Math.min(volume, 1) : 0
    onShownChanged: if (!shown) ringLevel = 0
    onRingTargetChanged: ringDelay.restart()
    Timer { id: ringDelay; interval: Theme.reduceMotion ? 0 : 260; onTriggered: root.ringLevel = root.ringTarget }
    Behavior on ringLevel {
        NumberAnimation { duration: Theme.reduceMotion ? 0 : 650; easing.type: Easing.OutCubic }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 8
        anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Item {
            id: glyph
            width: 28
            height: 28
            anchors.verticalCenter: parent.verticalCenter

            Shape {
                anchors.fill: parent
                visible: root.volume >= 0
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: 2
                    strokeColor: Qt.rgba(1, 1, 1, 0.2)
                    fillColor: "transparent"
                    PathAngleArc { centerX: 14; centerY: 14; radiusX: 13; radiusY: 13; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeWidth: 2
                    strokeColor: "#ffffff"
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 14; centerY: 14; radiusX: 13; radiusY: 13; startAngle: -90; sweepAngle: 360 * root.ringLevel }
                }
            }

            IconImage {
                id: icon
                anchors.centerIn: parent
                width: 16
                height: 16
                implicitSize: 16
                source: root.iconSource
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
