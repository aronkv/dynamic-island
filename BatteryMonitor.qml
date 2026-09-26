import Quickshell.Services.UPower
import Quickshell.Io
import QtQuick

Item {
    id: batteryMonitor

    // Reads the autoLowPower preference.
    property var settingsStore: null

    readonly property var device: UPower.displayDevice

    readonly property real percentage: device ? device.percentage * 100 : 0
    readonly property int state: device ? device.state : UPowerDeviceState.Unknown
    readonly property string stateText: device ? UPowerDeviceState.toString(device.state) : "Unknown"
    readonly property bool healthSupported: device ? device.healthSupported : false
    readonly property real healthPercentage: device ? device.healthPercentage : 0
    readonly property real timeToEmpty: device ? device.timeToEmpty : 0
    readonly property real timeToFull: device ? device.timeToFull : 0

    // Live power draw (W) — UPower's own rate, reactive, no polling. On this
    // dual-battery T480 the DisplayDevice aggregates both packs' rates.
    readonly property real powerDraw: device ? Math.abs(device.changeRate) : 0
    readonly property bool onBattery: UPower.onBattery
    readonly property bool charging: state === UPowerDeviceState.Charging
    readonly property bool pluggedIn: !UPower.onBattery

    // Per-pack breakdown (BAT0 internal, BAT1 removable) — UPower.devices
    // lists each real battery next to the synthetic DisplayDevice.
    readonly property var batteries: {
        const list = []
        for (const d of UPower.devices.values) {
            if (d.isLaptopBattery && d.isPresent) list.push(d)
        }
        list.sort((a, b) => a.nativePath.localeCompare(b.nativePath))
        return list
    }

    // Smoothed remaining time: UPower's raw estimate jumps around with every
    // load spike, so this is an exponential moving average of it (seconds).
    property real _smoothedTime: 0
    readonly property real timeRemaining: _smoothedTime
    function _updateTime() {
        const raw = charging ? timeToFull : (onBattery ? timeToEmpty : 0)
        if (raw <= 0) { _smoothedTime = 0; return }
        _smoothedTime = _smoothedTime <= 0 ? raw : _smoothedTime * 0.8 + raw * 0.2
    }
    onTimeToEmptyChanged: _updateTime()
    onTimeToFullChanged: _updateTime()
    onChargingChanged: { _smoothedTime = 0; _updateTime() }
    onOnBatteryChanged: { _smoothedTime = 0; _updateTime() }

    function formatDuration(seconds) {
        if (seconds <= 0) return ""
        const h = Math.floor(seconds / 3600)
        const m = Math.round((seconds % 3600) / 60)
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }

    // Connected charger's rated power (USB-C PD: voltage_max × current_max
    // of the online ucsi source; plain AC adapters report nothing → 0).
    property real adapterWatts: 0
    Process {
        id: adapterProbe
        // Fixed literal script, no interpolated data (safe as sh -c).
        command: ["sh", "-c", "for d in /sys/class/power_supply/*; do [ \"$(cat $d/online 2>/dev/null)\" = 1 ] && [ -r $d/voltage_max ] && [ -r $d/current_max ] && echo $(cat $d/voltage_max) $(cat $d/current_max); done"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                let best = 0
                for (const line of text.trim().split("\n")) {
                    const p = line.trim().split(/\s+/)
                    if (p.length === 2) best = Math.max(best, (parseFloat(p[0]) / 1e6) * (parseFloat(p[1]) / 1e6))
                }
                batteryMonitor.adapterWatts = Math.round(best)
            }
        }
    }
    onPluggedInChanged: adapterDelay.restart()
    // PD negotiation takes a moment after plugging in.
    Timer { id: adapterDelay; interval: 1500; onTriggered: adapterProbe.running = true }
    Component.onCompleted: adapterProbe.running = true

    readonly property string statusText: {
        if (!device) return "Unknown"
        if (state === UPowerDeviceState.FullyCharged) return "Fully charged"
        if (charging) return timeRemaining > 0 ? formatDuration(timeRemaining) + " until full" : "Charging"
        if (pluggedIn) return "Plugged in, not charging"
        return timeRemaining > 0 ? formatDuration(timeRemaining) + " remaining" : "On battery"
    }

    readonly property string iconName: {
        const level = Math.min(100, Math.max(0, Math.round(percentage / 10) * 10))
        if (state === UPowerDeviceState.FullyCharged) return "battery-level-100-charged-symbolic"
        if (charging || (pluggedIn && state === UPowerDeviceState.PendingCharge)) return "battery-level-" + level + "-charging-symbolic"
        return "battery-level-" + level + "-symbolic"
    }

    // Power profiles via tlp-pd (TLP's power-profiles-daemon-compatible
    // D-Bus service) through Quickshell's native PowerProfiles singleton —
    // reactive in both directions, no sudo, and external switches (e.g.
    // `tlpctl`/`powerprofilesctl`) show up live. Replaces the old
    // `sudo -n tlp ac|bat|start` path, whose state was only ever optimistic.
    readonly property int profile: PowerProfiles.profile
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property string degradationReason: {
        const r = PowerProfiles.degradationReason
        if (r === PerformanceDegradationReason.LapDetected) return "lap detected"
        if (r === PerformanceDegradationReason.HighTemperature) return "high temperature"
        return ""
    }
    function setProfile(p) {
        _lowPowerAutoApplied = false
        PowerProfiles.profile = p
    }

    // Whether tlp-pd is actually running — without it PowerProfiles has no
    // backend and the switcher would silently do nothing.
    property bool daemonAvailable: false
    Process {
        id: daemonProbe
        command: ["systemctl", "is-active", "--quiet", "tlp-pd.service"]
        onExited: (code) => batteryMonitor.daemonAvailable = code === 0
        Component.onCompleted: running = true
    }

    // macOS-style automatic Low Power: on battery at or below 20% switch to
    // Power Saver once, and restore the previous profile when plugged back
    // in — but only if this monitor was the one that switched it.
    readonly property bool autoLowPower: settingsStore ? settingsStore.autoLowPower : true
    property bool _lowPowerAutoApplied: false
    property int _profileBeforeAuto: PowerProfile.Balanced
    function _checkAutoLowPower() {
        if (!autoLowPower || !device || !daemonAvailable) return
        if (onBattery && percentage <= 20 && !_lowPowerAutoApplied && profile !== PowerProfile.PowerSaver) {
            _profileBeforeAuto = profile
            PowerProfiles.profile = PowerProfile.PowerSaver
            _lowPowerAutoApplied = true
        } else if (!onBattery && _lowPowerAutoApplied) {
            PowerProfiles.profile = _profileBeforeAuto
            _lowPowerAutoApplied = false
        }
    }
    onPercentageChanged: _checkAutoLowPower()
    onDaemonAvailableChanged: _checkAutoLowPower()
    onAutoLowPowerChanged: _checkAutoLowPower()

    // Per-pack stats straight from the kernel (sysfs), one line per BAT*:
    //   name cycle_count energy_full energy_full_design end_threshold
    // (µWh). upower -d was used before, but its charge-end-threshold was
    // stale (reported 80% while sysfs — what actually applies — said 100%),
    // and only the first pack's cycle count was shown.
    property var packs: []          // [{ name, cycles, fullWh, designWh, health, endThreshold }]
    readonly property real fullCapacityWh: packs.reduce((a, p) => a + p.fullWh, 0)
    readonly property real designCapacityWh: packs.reduce((a, p) => a + p.designWh, 0)
    readonly property bool fullCapacitySupported: fullCapacityWh > 0
    // Combined health = total full / total design capacity.
    readonly property bool healthKnown: designCapacityWh > 0
    readonly property real healthCombined: healthKnown ? fullCapacityWh / designCapacityWh * 100 : 0
    readonly property bool chargeCyclesSupported: packs.some(p => p.cycles >= 0)
    readonly property int chargeCycles: packs.reduce((a, p) => Math.max(a, p.cycles), -1)
    // Only a real limit (< 100%) counts.
    readonly property int chargeLimit: packs.reduce((a, p) => (p.endThreshold > 0 && p.endThreshold < 100) ? Math.max(a, p.endThreshold) : a, 0)
    readonly property bool chargeLimitSupported: chargeLimit > 0
    function packInfo(nativePath) { return packs.find(p => p.name === nativePath) || null }

    Process {
        id: extraStatsProbe
        // Fixed literal script, no interpolated data (safe as sh -c).
        command: ["sh", "-c", "for d in /sys/class/power_supply/BAT*; do echo $(basename $d) $(cat $d/cycle_count 2>/dev/null || echo -1) $(cat $d/energy_full 2>/dev/null || echo 0) $(cat $d/energy_full_design 2>/dev/null || echo 0) $(cat $d/charge_control_end_threshold 2>/dev/null || echo 0); done"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const out = []
                for (const line of text.trim().split("\n")) {
                    const f = line.trim().split(/\s+/)
                    if (f.length < 5) continue
                    const full = parseFloat(f[2]) / 1e6, design = parseFloat(f[3]) / 1e6
                    out.push({ name: f[0], cycles: parseInt(f[1], 10), fullWh: full, designWh: design,
                               health: design > 0 ? full / design * 100 : 0, endThreshold: parseInt(f[4], 10) })
                }
                batteryMonitor.packs = out
            }
        }
        Component.onCompleted: running = true
    }

    // These barely change — re-probing every 5 minutes (rather than once)
    // just keeps the panel honest if the user changes the charge-limit
    // policy externally while it happens to be open.
    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: extraStatsProbe.running = true
    }
}
