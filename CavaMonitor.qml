import Quickshell
import Quickshell.Io
import QtQuick

// Live audio-bar levels via the real `cava` CLI, raw-ascii output mode
// (confirmed live against real playback via speaker-test — `source: auto`
// correctly follows whatever the current default sink actually is, no
// hardcoded device path needed). Takes `enabled` as external input (set by
// the caller, e.g. only while a player is actively playing) rather than
// reaching into MprisMonitor itself, matching this project's one-purpose
// monitor convention — the Process only runs while enabled, so this isn't
// sampling audio or spending CPU when nothing needs it.
Item {
    id: cavaMonitor

    property bool enabled: false
    // 20 raw bands (cava/config: bars = 20) for the media card's background
    // visualizer; the idle pill shows 5, each the average of 4 bands.
    readonly property int barCount: 20
    property var bars: new Array(20).fill(0)
    readonly property int pillCount: 5
    readonly property var pillBars: {
        const out = []
        for (let i = 0; i < 5; i++) {
            let sum = 0
            for (let k = 0; k < 4; k++) sum += bars[i * 4 + k] || 0
            out.push(Math.min(1, sum / 4 * 1.3))
        }
        return out
    }

    Process {
        id: cavaProc
        running: cavaMonitor.enabled
        command: ["cava", "-p", Quickshell.env("HOME") + "/.config/quickshell/cava/config"]

        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.split(";").filter(p => p.length > 0)
                if (parts.length === 0) return
                // parseInt can return NaN on a malformed/truncated line, and
                // NaN silently poisons Math.max/min (both return NaN if any
                // argument is NaN) — without this guard a single bad line
                // would propagate NaN into a Rectangle.height binding.
                cavaMonitor.bars = parts.map(v => {
                    const n = parseInt(v, 10)
                    return Math.max(0, Math.min(1, (isNaN(n) ? 0 : n) / 100))
                })
            }
        }
    }

    onEnabledChanged: if (!enabled) bars = new Array(20).fill(0)
}
