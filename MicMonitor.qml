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
    readonly property bool pipewireActive: Pipewire.nodes.values.some(n =>
        n.isStream && n.type === PwNodeType.AudioInStream && n.name !== "cava"
    )

    // Secondary pactl-based check, OR'd into `active` below — a fallback
    // for a capture stream that for whatever reason doesn't register
    // cleanly through Quickshell's own Pipewire node binding. Same 2000ms
    // polling pattern as CameraMonitor.qml's fuser-based check; a plain
    // argv-list command since there's no shell feature needed here (no
    // pipes/redirects), unlike fuser's stderr-silencing.
    property bool _pactlActive: false
    property bool _foundThisRun: false

    readonly property bool active: pipewireActive || _pactlActive

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            micMonitor._foundThisRun = false
            checkProc.running = true
        }
    }

    // A plain "any source-output exists" check (the original version of
    // this file) false-positived as soon as `CavaMonitor.qml` started
    // running: cava listens to the current sink's *monitor* source to
    // visualize whatever's playing, which is itself a "source-output" in
    // pactl's eyes, indistinguishable from a real mic capture by count
    // alone (confirmed live: `pactl list source-outputs short` showed an
    // entry attached to source 54, `..._analog-stereo.monitor` — the sink
    // monitor, not source 55, the real `..._analog-stereo` mic input).
    // Fixed by cross-referencing each source-output's source index against
    // the source list and excluding any source whose name ends in
    // ".monitor" (a monitor tap on an output device, never an actual
    // microphone) before counting it as mic activity.
    Process {
        id: checkProc
        command: ["sh", "-c", "pactl list sources short; echo ---; pactl list source-outputs short"]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line === "---") { checkProc._inOutputs = true; return }
                const cols = line.trim().split(/\s+/)
                if (cols.length < 2 || cols[0].length === 0) return
                if (!checkProc._inOutputs) {
                    if (line.includes(".monitor")) checkProc._monitorSourceIds[cols[0]] = true
                } else {
                    const sourceId = cols[1]
                    if (!checkProc._monitorSourceIds[sourceId]) micMonitor._foundThisRun = true
                }
            }
        }

        property bool _inOutputs: false
        property var _monitorSourceIds: ({})

        onRunningChanged: if (running) { _inOutputs = false; _monitorSourceIds = ({}) }
        onExited: micMonitor._pactlActive = micMonitor._foundThisRun
    }
}
