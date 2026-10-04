import Quickshell.Services.Pipewire
import Quickshell.Io
import QtQuick

Item {
    id: micMonitor

    // Excludes cava by name — CavaMonitor.qml's own visualizer process
    // registers as a genuine PwNodeType.AudioInStream node (confirmed via
    // `pw-dump`: media.class "Stream/Input/Audio", node.name "cava")
    // because it captures the current sink's *monitor* tap to visualize
    // playback, not a real microphone — PipeWire's own type system doesn't
    // distinguish "input stream from a mic" from "input stream from a
    // monitor loopback", so a name-based exclusion is the reliable fix
    // here (this is our own known, controlled process, not a general
    // heuristic). This is a real bug fix, not a duplicate of the pactl
    // fallback below — that fallback exists for the opposite gap (a mic
    // capture PipeWire itself doesn't see), so both checks need this same
    // cava exclusion independently.
    // Same for the screen recorder: gpu-screen-recorder's system-audio
    // capture is an input stream named "gsr-default_output" on the sink
    // monitor. Excluded here; if the recording also takes the mic, the pactl
    // check below still sees a real (non-monitor) source and lights the badge.
    readonly property bool pipewireActive: Pipewire.nodes.values.some(n =>
        n.isStream && n.type === PwNodeType.AudioInStream && n.name !== "cava" && !n.name.startsWith("gsr-")
    )

    // Secondary pactl-based check, OR'd into `active` below — a fallback
    // for a capture stream that for whatever reason doesn't register
    // cleanly through Quickshell's own Pipewire node binding. Same 2000ms
    // polling pattern as CameraMonitor.qml's fuser-based check; a plain
    // argv-list command since there's no shell feature needed here (no
    // pipes/redirects), unlike fuser's stderr-silencing.
    property bool _pactlActive: false

    readonly property bool active: pipewireActive || _pactlActive

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: checkProc.running = true
    }

    // A plain "any source-output exists" check (the original version of
    // this file) false-positived as soon as cava ran: it captures audio to
    // visualize it, which pactl lists as a source-output like any mic
    // capture. Monitor taps (sources named "*.monitor") were excluded by
    // source index — but since cava captures the playing app's own stream
    // (CavaMonitor `source = <stream node name>`), pactl reports that
    // capture's source as 4294967295 (no source at all), which the index
    // check counted as a mic. Now pactl's JSON output is read and captures
    // are skipped by their own node.name (cava, gsr-* = the screen
    // recorder's system audio) as well as by monitor source, and only a
    // capture attached to a real, non-monitor source counts.
    Process {
        id: checkProc
        command: ["sh", "-c", "pactl -f json list sources; echo; echo '#OUTPUTS'; pactl -f json list source-outputs"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: micMonitor._pactlActive = micMonitor._parse(text)
        }
    }

    function _parse(text) {
        try {
            const parts = text.split("#OUTPUTS")
            const sources = JSON.parse(parts[0])
            const outputs = JSON.parse(parts[1])
            const real = {}
            for (const src of sources)
                if (!(src.name || "").endsWith(".monitor") && (src.properties || {})["device.class"] !== "monitor")
                    real[src.index] = true
            return outputs.some(o => {
                const name = ((o.properties || {})["node.name"] || "")
                if (name === "cava" || name.startsWith("gsr-")) return false
                return real[o.source] === true
            })
        } catch (e) {
            return false
        }
    }
}
