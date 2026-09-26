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
