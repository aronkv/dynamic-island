import Quickshell.Networking
import Quickshell.Io
import Quickshell
import QtQuick

Item {
    id: networkMonitor

    readonly property var wifiDevice: {
        for (const d of Networking.devices.values) {
            if (d.type === DeviceType.Wifi) return d
        }
        return null
    }

    // Quickshell doesn't scan for networks unless told to — without this,
    // wifiDevice.networks stays empty even though real networks are visible
    // system-wide (confirmed via `nmcli dev wifi list`). Also (re)fetches
    // the nmcli-sourced detail map below once a Wi-Fi device actually
    // exists, since it can't run meaningfully before that.
    onWifiDeviceChanged: if (wifiDevice) { wifiDevice.scannerEnabled = true; refreshDetails() }
    Component.onCompleted: if (wifiDevice) { wifiDevice.scannerEnabled = true; refreshDetails() }

    readonly property var wiredDevice: {
        for (const d of Networking.devices.values) {
            if (d.type === DeviceType.Wired) return d
        }
        return null
    }

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool ethernetConnected: wiredDevice ? wiredDevice.hasLink : false

    // "Primary" connection for the header/overview status slot: a connected
    // wired link wins over Wi-Fi (NetworkManager gives ethernet the lower
    // route metric by default — confirmed via `ip route`: 100 vs 600 — so
    // it's the one actually carrying traffic when both are up).
    readonly property bool ethernetActive: wiredDevice ? (wiredDevice.connected && wiredDevice.hasLink) : false
    readonly property var activeWifiNetwork: wifiEnabled ? (networks.find(n => n.connected) || null) : null
    readonly property string primaryType: ethernetActive ? "ethernet" : activeWifiNetwork ? "wifi" : "none"
    readonly property string primaryIcon: primaryType === "ethernet" ? "network-wired-symbolic" : "network-wireless-symbolic"
    readonly property string primaryLabel: {
        if (primaryType === "ethernet") return "Ethernet"
        if (primaryType === "wifi") return activeWifiNetwork.name
        return wifiEnabled ? "Not connected" : "Off"
    }

    readonly property var networks: {
        if (!wifiDevice) return []
        const list = wifiDevice.networks.values.slice()
        list.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.known !== b.known) return a.known ? -1 : 1
            return b.signalStrength - a.signalStrength
        })
        return list
    }

    function setWifiEnabled(enabled) {
        Networking.wifiEnabled = enabled
    }

    // Toggling the scanner off/on forces a fresh scan request instead of
    // relying on whatever NetworkManager's own background scan cadence
    // happens to be — called when the Wi-Fi panel is opened so the list
    // doesn't sit stale on whatever was cached when scanning first turned on.
    function rescan() {
        if (!wifiDevice) return
        wifiDevice.scannerEnabled = false
        wifiDevice.scannerEnabled = true
        refreshDetails()
    }

    // Extra per-network detail (band/channel/frequency/speed/detailed
    // security string/BSSID) for the panel's right-click expanded row —
    // Quickshell.Networking's own WifiNetwork exposes only `signalStrength`
    // and a coarse `security` enum, confirmed against its real qmltypes, so
    // this shells out to `nmcli` (via wifi_details.py, matching this
    // project's established Python-helper convention) for the rest.
    // {"<ssid>": {bssid, channel, band, freq, rate, security}, ...}
    property var wifiDetails: ({})

    Process {
        id: detailsProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/wifi_details.py"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const trimmed = text.trim()
                if (trimmed.length === 0) return
                try {
                    networkMonitor.wifiDetails = JSON.parse(trimmed)
                } catch (e) {
                    // Leave the previous details in place rather than
                    // wiping them over a transient parse failure.
                }
            }
        }
    }

    function refreshDetails() {
        detailsProc.running = false
        detailsProc.running = true
    }

    // Forgets a saved Wi-Fi network — Quickshell.Networking's own Network/
    // WifiNetwork type exposes no such method (confirmed against its real
    // qmltypes: connect/disconnect/connectWithPsk only, nothing that deletes
    // a saved profile), so this shells out to `nmcli connection delete`.
    // Argv-list, not `sh -c` (CLAUDE.md's Process security convention) —
    // an SSID is untrusted/arbitrary text as far as this code is concerned,
    // so it must never be interpolated into a shell string. NetworkManager
    // names a Wi-Fi connection profile after its SSID by default (confirmed
    // live via `nmcli connection show`), which is what `network.name`
    // already gives us — no separate UUID lookup needed for the common case.
    Process {
        id: forgetProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: networkMonitor.rescan()
    }

    function forgetNetwork(name) {
        forgetProc.command = ["nmcli", "connection", "delete", "id", name]
        forgetProc.running = true
    }

    // Overwrites a saved network's stored password — matches the phone
    // reference's "Modify network" flow (name shown, password field
    // defaulting to "(unchanged)", Save). Quickshell.Networking exposes no
    // way to touch a saved profile's secrets at all, so this shells out to
    // `nmcli connection modify` (the field is `802-11-wireless-security.psk`,
    // confirmed live — nmcli's own `wifi-sec.psk` alias doesn't exist).
    // Argv-list, not `sh -c` (CLAUDE.md's Process security convention) — the
    // new password is untrusted, arbitrary text and must never be
    // interpolated into a shell string. Re-brings the connection up
    // afterward so a currently-connected network picks up the change
    // immediately instead of silently running on the old, now-invalid psk
    // until its next reconnect.
    Process {
        id: modifyProc
        property string connectionName: ""
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: {
            upProc.command = ["nmcli", "connection", "up", "id", connectionName]
            upProc.running = true
        }
    }

    Process {
        id: upProc
        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: networkMonitor.rescan()
    }

    function modifyPassword(name, newPsk) {
        modifyProc.connectionName = name
        modifyProc.command = ["nmcli", "connection", "modify", "id", name, "802-11-wireless-security.psk", newPsk]
        modifyProc.running = true
    }
}
