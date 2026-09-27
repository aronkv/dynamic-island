import Quickshell.Io
import QtQuick

// Night Shift via hyprsunset. Runs `hyprsunset -t <K>` while it should be
// on (manually "Always", or between today's sunset and sunrise from the
// weather data), kills it otherwise (hyprsunset restores the normal gamma
// on exit). Temperature changes restart it. Checks the schedule every
// minute. `available` is false when hyprsunset isn't installed.
Item {
    id: nl
    property var settingsStore: null
    property var weather: null

    readonly property bool enabled: settingsStore ? settingsStore.nightLight : false
    readonly property int temperature: settingsStore ? settingsStore.nightLightTemp : 4000
    readonly property string schedule: settingsStore ? settingsStore.nightLightSchedule : "sunset"
    property bool available: true
    property real now: Date.now()

    readonly property bool shouldRun: {
        if (!enabled) return false
        if (schedule === "always") return true
        const d = weather && weather.daily && weather.daily.length > 0 ? weather.daily[0] : null
        const t = new Date(now)
        const mins = t.getHours() * 60 + t.getMinutes()
        // Fallback when there's no weather data yet: 20:00 → 07:00.
        const toMin = s => { const x = new Date(s); return x.getHours() * 60 + x.getMinutes() }
        const on = d && d.sunset ? toMin(d.sunset) : 20 * 60
        const off = d && d.sunrise ? toMin(d.sunrise) : 7 * 60
        return mins >= on || mins < off
    }
    readonly property bool running: proc.running

    Timer { interval: 60000; running: nl.enabled; repeat: true; onTriggered: nl.now = Date.now() }

    function _apply() {
        if (!shouldRun) { if (proc.running) proc.signal(15); return }
        if (proc.running) { restartPending = true; proc.signal(15); return }
        proc.command = ["hyprsunset", "-t", String(Math.max(1000, Math.min(6500, temperature)))]
        proc.running = true
    }
    property bool restartPending: false
    onShouldRunChanged: _apply()
    onTemperatureChanged: if (shouldRun) debounce.restart()
    Timer { id: debounce; interval: 300; onTriggered: nl._apply() }
    Component.onCompleted: _apply()

    Process {
        id: proc
        onExited: (code) => {
            if (nl.restartPending) { nl.restartPending = false; nl._apply() }
        }
    }

    Process {
        id: check
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: (code) => nl.available = code === 0
        Component.onCompleted: running = true
    }
}
