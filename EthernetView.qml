import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

// Ethernet cable plugged in / pulled (displayState "ethernet"): a compact
// pill like the charging one — the wired-network glyph and "Ethernet" on
// the left, the negotiated link speed on the right ("1 Gbps", read from
// /sys/class/net/<iface>/speed once the link is up), or "Disconnected" when
// the cable is pulled.
Item {
    id: root
    property bool shown: false
    property bool connected: false
    property string iface: ""

    property string speed: ""
    readonly property string detail: !connected ? "Disconnected" : speed !== "" ? speed : "Connected"

    // The kernel reports the speed in Mb/s once negotiation finishes, which
    // can lag the carrier by a moment, so it is read when the pill shows
    // and once more shortly after.
    onShownChanged: if (shown && connected) { speed = ""; readSpeed(); speedRetry.restart() }
    function readSpeed() {
        if (iface === "") return
        speedProc.command = ["cat", "/sys/class/net/" + iface + "/speed"]
        speedProc.running = true
    }
    Timer { id: speedRetry; interval: 900; onTriggered: root.readSpeed() }
    Process {
        id: speedProc
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const mbps = parseInt(text)
                if (!(mbps > 0)) return
                root.speed = mbps >= 1000 ? (mbps / 1000) + " Gbps" : mbps + " Mbps"
            }
        }
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
            opacity: root.connected ? 1 : 0.45
            IconImage {
                id: icon
                anchors.fill: parent
                implicitSize: 18
                source: "image://icon/network-wired-symbolic"
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
            text: "Ethernet"
            color: "#ffffff"
            font.pixelSize: 14
            font.weight: 600
            font.family: Theme.fontText
        }
        Item { width: parent.width - glyph.width - labelText.width - detailText.width - 2 * parent.spacing; height: 1 }
        Text {
            id: detailText
            anchors.verticalCenter: parent.verticalCenter
            text: root.detail
            color: "#ffffff"
            opacity: root.connected ? 1 : 0.5
            font.pixelSize: 14
            font.weight: 700
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }
}
