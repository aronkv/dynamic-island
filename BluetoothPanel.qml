import Quickshell.Bluetooth
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects

// Bluetooth sub-view, iOS Settings style: connected devices as a status
// card on top (device icon badge, battery % with a mini gauge when BlueZ
// reports it), then grouped lists "My Devices" (paired) and "Other Devices"
// (discovered, with a spinner while scanning). Click a row: connect /
// disconnect / pair. The ⓘ button (or right-click) expands Connect/
// Disconnect + Forget. All logic is BluetoothMonitor's / BlueZ's.
ColumnLayout {
    id: panel
    property var monitor: null
    // Row (by address) whose actions are expanded — lives on the panel so
    // the delegate recreation on every devices-array change doesn't lose it.
    property string expandedDeviceAddress: ""
    signal settingsRequested()
    signal closeRequested()
    spacing: 10

    readonly property bool on: monitor && monitor.adapter && monitor.enabled
    // BlueZ copies Address into Name until it resolves a friendly one;
    // those (privacy-randomized BLE adverts) aren't shown as available.
    function hasResolvedName(d) {
        return d.deviceName && d.deviceName.toUpperCase() !== d.address.toUpperCase()
    }
    function displayName(d) { return hasResolvedName(d) ? d.deviceName : "Unknown device" }
    function batteryPct(d) {
        // May come back as a 0..1 fraction rather than 0..100.
        const b = d.battery
        return Math.round((b > 0 && b <= 1) ? b * 100 : b)
    }
    readonly property var connectedDevices: monitor ? monitor.devices.filter(d => d.connected) : []
    readonly property var savedDevices: monitor ? monitor.devices.filter(d => d.paired && !d.connected) : []
    readonly property var availableDevices: monitor ? monitor.devices.filter(d => !d.paired && !d.connected && hasResolvedName(d)) : []

    function activate(d) {
        if (d.connected) d.disconnect()
        else if (d.paired) d.connect()
        else d.pair()
    }
    function toggleExpanded(d) {
        expandedDeviceAddress = expandedDeviceAddress === d.address ? "" : d.address
    }

    component RowIcon: Item {
        id: rowIcon
        property string icon: ""
        property color iconColor: "#ffffff"
        implicitWidth: 16
        implicitHeight: 16
        IconImage {
            id: iconImg
            anchors.fill: parent
            source: rowIcon.icon !== "" ? "image://icon/" + rowIcon.icon : ""
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }
        Rectangle { id: flatFill; anchors.fill: parent; color: rowIcon.iconColor; visible: false }
        MultiEffect {
            anchors.fill: iconImg
            source: flatFill
            maskEnabled: true
            maskSource: iconImg
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.0
            maskThresholdMax: 1.0
            maskSpreadAtMax: 0.0
        }
    }

    component Spinner: Item {
        id: sp
        property color color: "#ffffff"
        implicitWidth: 12
        implicitHeight: 12
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: sp.color
                strokeWidth: 1.6
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    moveToStart: true
                    centerX: sp.width / 2; centerY: sp.height / 2
                    radiusX: sp.width / 2 - 1; radiusY: radiusX
                    startAngle: 0; sweepAngle: 270
                }
            }
            RotationAnimation on rotation {
                running: sp.visible
                from: 0; to: 360
                duration: 800
                loops: Animation.Infinite
            }
        }
    }

    component PillButton: Rectangle {
        id: pb
        property string label: ""
        property bool primary: false
        property bool destructive: false
        signal clicked()
        implicitWidth: pbText.implicitWidth + 24
        implicitHeight: 28
        radius: 14
        color: primary ? "#ffffff"
            : destructive ? (pbMouse.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.28) : Qt.rgba(1, 0.27, 0.23, 0.16))
            : (pbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1))
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: pbMouse.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.label
            color: pb.primary ? "#000000" : pb.destructive ? Theme.red : "#ffffff"
            font.pixelSize: 12
            font.weight: 600
            font.family: Theme.fontText
        }
        MouseArea {
            id: pbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    component InfoButton: Rectangle {
        id: ib
        property bool open: false
        signal clicked()
        implicitWidth: 24
        implicitHeight: 24
        radius: 12
        color: open ? "#ffffff" : (ibMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent")
        border.width: open ? 0 : 1.2
        border.color: Qt.rgba(1, 1, 1, 0.45)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: "i"
            color: ib.open ? "#000000" : "#ffffff"
            opacity: ib.open ? 1 : 0.7
            font.pixelSize: 12
            font.weight: 700
            font.family: "SF Pro Rounded"
        }
        MouseArea {
            id: ibMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    // Horizontal mini battery gauge (device battery from BlueZ).
    component MiniBattery: Item {
        id: mb
        property real pct: 0
        implicitWidth: 22
        implicitHeight: 11
        Rectangle {
            id: mbBody
            width: 19; height: 11
            radius: 3
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.5)
            Rectangle {
                x: 2; y: 2
                height: parent.height - 4
                width: Math.max(1, (parent.width - 4) * Math.min(1, mb.pct / 100))
                radius: 1.5
                color: mb.pct <= 20 ? Theme.red : "#ffffff"
            }
        }
        Rectangle {
            anchors.left: mbBody.right
            anchors.leftMargin: 1
            anchors.verticalCenter: mbBody.verticalCenter
            width: 1.5; height: 4
            radius: 1
            color: Qt.rgba(1, 1, 1, 0.5)
        }
    }

    // One device row. `hero` = the bigger status-card look for connected
    // devices (white icon badge).
    component DeviceRow: Item {
        id: row
        property var device: null
        property bool first: false
        property bool hero: false
        Layout.fillWidth: true
        implicitHeight: rowCol.implicitHeight
        clip: true

        readonly property bool expanded: panel.expandedDeviceAddress === device.address
        readonly property bool busy: device.pairing || device.state === BluetoothDeviceState.Connecting || device.state === BluetoothDeviceState.Disconnecting

        // No connectionFailed-style signal for Bluetooth — infer a failed
        // pair() from pairing going true → false without paired.
        property bool wasPairing: false
        property bool pairFailed: false
        Connections {
            target: row.device
            function onPairingChanged() {
                if (row.device.pairing) { row.wasPairing = true; row.pairFailed = false }
                else if (row.wasPairing) { row.wasPairing = false; row.pairFailed = !row.device.paired }
            }
        }

        readonly property string status: {
            if (pairFailed) return "Couldn't pair"
            if (device.pairing) return "Pairing…"
            if (device.state === BluetoothDeviceState.Connecting) return "Connecting…"
            if (device.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…"
            if (device.connected) return "Connected"
            if (device.paired) return "Not Connected"
            return ""
        }

        Rectangle {
            visible: !row.first
            x: row.hero ? 60 : 44
            width: parent.width - x
            height: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }

        ColumnLayout {
            id: rowCol
            width: parent.width
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: row.hero ? 60 : 44

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 1, 1, rowMouse.containsMouse ? 0.05 : 0)
                }

                Rectangle {
                    id: badge
                    x: row.hero ? 12 : 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: row.hero ? 36 : 26
                    height: width
                    radius: width / 2
                    color: row.hero ? "#ffffff" : "transparent"
                    RowIcon {
                        anchors.centerIn: parent
                        width: row.hero ? 18 : 16
                        height: width
                        icon: row.device.icon || "bluetooth-symbolic"
                        iconColor: row.hero ? "#000000" : "#ffffff"
                        opacity: row.hero ? 1 : 0.85
                    }
                }

                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: row.hero ? 12 : 10
                    anchors.right: trailing.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: row.hero ? 2 : 1
                    Text {
                        width: parent.width
                        text: panel.displayName(row.device)
                        color: "#ffffff"
                        font.pixelSize: row.hero ? 15 : 13
                        font.weight: row.hero ? 700 : 500
                        font.family: row.hero ? Theme.font : Theme.fontText
                        elide: Text.ElideRight
                    }
                    Row {
                        spacing: 6
                        visible: row.status !== "" || (row.device.batteryAvailable && row.device.connected)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.status !== ""
                            text: row.status
                            color: row.pairFailed ? Theme.red : "#ffffff"
                            opacity: row.pairFailed ? 1 : 0.5
                            font.pixelSize: row.hero ? 11 : 10
                            font.family: Theme.fontText
                        }
                        MiniBattery {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.device.batteryAvailable
                            pct: panel.batteryPct(row.device)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.device.batteryAvailable
                            text: panel.batteryPct(row.device) + "%"
                            color: "#ffffff"
                            opacity: 0.6
                            font.pixelSize: row.hero ? 11 : 10
                            font.family: Theme.fontText
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                Row {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Spinner { anchors.verticalCenter: parent.verticalCenter; visible: row.busy }
                    InfoButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.device.paired || row.device.connected
                        open: row.expanded
                        onClicked: panel.toggleExpanded(row.device)
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    anchors.rightMargin: 44
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) panel.toggleExpanded(row.device)
                        else panel.activate(row.device)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 12
                spacing: 8
                visible: row.expanded

                PillButton {
                    label: row.device.connected ? "Disconnect" : "Connect"
                    primary: !row.device.connected
                    onClicked: row.device.connected ? row.device.disconnect() : row.device.connect()
                }
                Text {
                    Layout.fillWidth: true
                    text: row.device.address
                    color: "#ffffff"
                    opacity: 0.35
                    font.pixelSize: 10
                    font.family: Theme.fontText
                    elide: Text.ElideRight
                }
                PillButton {
                    visible: row.device.paired
                    label: "Forget"
                    destructive: true
                    onClicked: { row.device.forget(); panel.expandedDeviceAddress = "" }
                }
            }
        }
    }

    component SectionLabel: RowLayout {
        property string text: ""
        property bool busy: false
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        spacing: 6
        Text {
            text: parent.text
            color: "#ffffff"
            opacity: 0.45
            font.pixelSize: 11
            font.weight: 600
            font.letterSpacing: 0.4
            font.family: Theme.fontText
        }
        Spinner { visible: parent.busy; color: Qt.rgba(1, 1, 1, 0.5); width: 10; height: 10 }
        Item { Layout.fillWidth: true }
    }

    component Group: Rectangle {
        default property alias rows: groupCol.data
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: 14
        color: Theme.card
        clip: true
        ColumnLayout {
            id: groupCol
            width: parent.width
            spacing: 0
        }
    }

    PanelHeader {
        showIdentity: false
        Layout.fillWidth: true
        visible: panel.monitor && panel.monitor.adapter
        icon: "bluetooth-symbolic"
        title: "Bluetooth"
        subtitle: !panel.on ? "Off"
            : panel.connectedDevices.length === 1 ? panel.displayName(panel.connectedDevices[0])
            : panel.connectedDevices.length > 1 ? panel.connectedDevices.length + " devices connected"
            : "On"
        showToggle: true
        toggleChecked: panel.monitor ? panel.monitor.enabled : false
        showRefresh: panel.on
        onToggled: if (panel.monitor) panel.monitor.setEnabled(!panel.monitor.enabled)
        onRefreshRequested: if (panel.monitor) panel.monitor.rescan()
        onSettingsRequested: panel.settingsRequested()
        onCloseRequested: panel.closeRequested()
    }

    Flickable {
        id: deviceFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: deviceColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        visible: panel.on

        ColumnLayout {
            id: deviceColumn
            width: parent.width
            spacing: 6

            // ── Status card: connected devices ──────────────────────
            Group {
                Repeater {
                    model: panel.connectedDevices
                    delegate: DeviceRow {
                        required property var modelData
                        required property int index
                        device: modelData
                        first: index === 0
                        hero: true
                    }
                }
                // Nothing connected.
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 60
                    visible: panel.connectedDevices.length === 0
                    Rectangle {
                        id: idleBadge
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36; height: 36
                        radius: 18
                        color: Qt.rgba(1, 1, 1, 0.1)
                        RowIcon { anchors.centerIn: parent; width: 18; height: 18; icon: "bluetooth-symbolic" }
                    }
                    Column {
                        anchors.left: idleBadge.right
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: "Not Connected"
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.weight: 700
                            font.family: Theme.font
                        }
                        Text {
                            text: panel.monitor && panel.monitor.adapter && panel.monitor.adapter.name
                                ? "Visible as “" + panel.monitor.adapter.name + "”" : "Choose a device below"
                            color: "#ffffff"
                            opacity: 0.5
                            font.pixelSize: 11
                            font.family: Theme.fontText
                        }
                    }
                }
            }

            SectionLabel {
                text: "MY DEVICES"
                visible: panel.savedDevices.length > 0
            }
            Group {
                visible: panel.savedDevices.length > 0
                Repeater {
                    model: panel.savedDevices
                    delegate: DeviceRow {
                        required property var modelData
                        required property int index
                        device: modelData
                        first: index === 0
                    }
                }
            }

            SectionLabel {
                text: "OTHER DEVICES"
                busy: panel.monitor ? panel.monitor.discovering : false
            }
            Group {
                visible: panel.availableDevices.length > 0
                Repeater {
                    model: panel.availableDevices
                    delegate: DeviceRow {
                        required property var modelData
                        required property int index
                        device: modelData
                        first: index === 0
                    }
                }
            }
            Text {
                Layout.leftMargin: 14
                visible: panel.availableDevices.length === 0
                text: panel.monitor && panel.monitor.discovering ? "Searching…" : "No other devices found"
                color: "#ffffff"
                opacity: 0.35
                font.pixelSize: 12
                font.family: Theme.fontText
            }
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: !panel.on

        Column {
            anchors.centerIn: parent
            spacing: 8
            RowIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 28; height: 28
                icon: "bluetooth-disabled-symbolic"
                opacity: 0.3
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: panel.monitor && panel.monitor.adapter ? "Bluetooth is off" : "No Bluetooth adapter found"
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 12
                font.family: Theme.fontText
            }
        }
    }
}
