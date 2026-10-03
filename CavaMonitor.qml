import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
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

    // Capture only the playing app's own output stream, not the whole sink
    // monitor (`source = auto`): with auto, a Discord call's voices showed up
    // in the bars, and a loud voice pushed cava's autosens down so the music
    // looked flat afterwards. `appKeys` (MprisMonitor.appKeys) are matched
    // against the first word of each output stream's node.name ("spotify",
    // "Brave", "mpv"); verified that cava with `source = <stream node name>`
    // hears only that stream. No match (unknown app) → falls back to auto.
    property var appKeys: []
    readonly property var _stream: Pipewire.nodes.values.find(n =>
        n.isStream && n.type === PwNodeType.AudioOutStream
        && appKeys.includes((n.name || "").split(" ")[0].toLowerCase())) ?? null
    readonly property string source: _stream ? _stream.name : "auto"
    // Restart cava when the target changes, including the same app
    // recreating its stream (new node id). A capture stream whose target is
    // missing would otherwise be moved by WirePlumber to the default source
    // — the mic — so a named target also runs with node.dont-fallback /
    // dont-reconnect / dont-move (verified: cava then exits instead).
    readonly property string _sourceKey: _stream ? _stream.name + "#" + _stream.id : "auto"
    property bool _restarting: false
    on_SourceKeyChanged: { _restarting = true; restartTimer.restart() }
    Timer {
        id: restartTimer
        interval: 100
        onTriggered: cavaMonitor._restarting = false
    }
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
        running: cavaMonitor.enabled && !cavaMonitor._restarting
        // cava has no CLI flag for the source, so feed it the config with
        // the `source =` line swapped (bash process substitution; the name
        // goes in as an argument, not spliced into the script).
        environment: cavaMonitor.source === "auto" ? ({})
            : ({ "PIPEWIRE_PROPS": "{ node.dont-fallback=true node.dont-reconnect=true node.dont-move=true }" })
        command: ["bash", "-c",
            "exec cava -p <(awk -v s=\"$1\" '/^source =/ { print \"source = \" s; next } { print }' \"$2\")",
            "bash", cavaMonitor.source, Quickshell.env("HOME") + "/.config/quickshell/cava/config"]

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
