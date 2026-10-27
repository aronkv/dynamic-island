import Quickshell
import Quickshell.Bluetooth
import QtQuick

Item {
    id: bluetoothMonitor

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter ? adapter.enabled : false
    readonly property bool discovering: adapter ? adapter.discovering : false
    readonly property int state: adapter ? adapter.state : BluetoothAdapterState.Disabled

    readonly property var devices: {
        if (!adapter) return []
        const list = adapter.devices.values.slice()
        list.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.paired !== b.paired) return a.paired ? -1 : 1
            return a.deviceName.localeCompare(b.deviceName)
        })
        return list
    }

    // Fires on every disconnected → connected transition, however it was
    // started (auto-reconnect, the panel, bluetoothctl).
    signal deviceConnected(var device)
    Instantiator {
        model: bluetoothMonitor.adapter ? bluetoothMonitor.adapter.devices : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectedChanged() {
                if (modelData && modelData.connected) bluetoothMonitor.deviceConnected(modelData)
            }
        }
    }

    // BlueZ names a class icon ("audio-headset"); Adwaita only ships those
    // as colour PNGs, which the flat-white mask turns into a blob, so use
    // the symbolic variant when the theme has one.
    function iconName(d) {
        const name = d && d.icon ? d.icon + "-symbolic" : ""
        return name !== "" && Quickshell.iconPath(name, true) !== "" ? name : "bluetooth-symbolic"
    }

    function setEnabled(enabled) {
        if (!adapter) return
        adapter.enabled = enabled
    }

    // Toggling discovering off/on forces a fresh scan instead of trusting
    // whatever's already cached — same rationale as NetworkMonitor.rescan().
    function rescan() {
        // Discovery on a powered-off adapter fails ("Resource Not Ready").
        if (!adapter || !adapter.enabled) return
        adapter.discovering = false
        adapter.discovering = true
    }
}
