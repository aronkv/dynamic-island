import Quickshell
import Quickshell.Io
import QtQuick

// Live activities shown in the idle pill (LiveActivityChip) and the
// expanded "activity" view (ActivityPanel):
//  • Screen recording — gpu-screen-recorder (hardware VAAPI), whole screen,
//    to ~/Videos/Recordings/. Resolution / fps / quality / audio / cursor
//    come from Settings (read at start). Stopped with SIGINT so the file is
//    finalized properly.
//  • Timer / stopwatch / pomodoro (25 / 5 min cycles) — end/start
//    timestamps persisted in activity.json, so a qs reload keeps them.
// Finished timers and pomodoro phase switches notify (notify-send → the
// island's own notification server) and play a short chime.
Item {
    id: store
    property var settingsStore: null

    // ── Screen recording ──────────────────────────────────────────────
    property bool recording: false
    property real recordStart: 0
    property string recordFile: ""
    property string recordError: ""

    function toggleRecording() { recording ? stopRecording() : startRecording() }
    function startRecording() {
        if (recording) return
        const dir = Quickshell.env("HOME") + "/Videos/Recordings"
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss")
        recordFile = dir + "/Recording_" + stamp + ".mp4"
        recordError = ""
        mkdirProc.command = ["mkdir", "-p", dir]
        mkdirProc.running = true
    }
    // argv from the Settings → Screen recording options. System audio and
    // mic are merged into one track ("a|b").
    function recorderArgs(file) {
        const st = settingsStore
        const fps = st ? st.recordFps : 60
        // A file every player and editor opens: H.264 High (yuv420p) on the
        // GPU (VAAPI — leaves the CPU to the game; CPU x264 competed with
        // e.g. Minecraft), constant frame rate (editors choke on VFR), a
        // constant bitrate in kbps (-bm cbr makes -q a bitrate), and AAC
        // audio — gsr's default for MP4 is Opus, which many players and
        // editors can't read. Verified: 1080p, 60/1 CFR, AAC LC.
        const kbps = st ? st.recordBitrate : 80000
        const video = ["-k", "h264", "-fm", "cfr", "-bm", "cbr", "-q", String(kbps), "-ac", "aac", "-ab", "320"]
        const res = st ? st.recordResolution : "native"
        const sizes = { "1080": "1920x1080", "720": "1280x720", "480": "854x480" }
        const args = ["gpu-screen-recorder", "-w", "screen", "-f", String(fps), ...video,
                      "-cursor", (st ? st.recordCursor : true) ? "yes" : "no"]
        if (sizes[res]) args.push("-s", sizes[res])
        const audio = []
        if (!st || st.recordSystemAudio) audio.push("default_output")
        if (st && st.recordMic) audio.push("default_input")
        if (audio.length > 0) args.push("-a", audio.join("|"))
        return args.concat(["-o", file])
    }
    function stopRecording() {
        if (recorder.running) recorder.signal(2)   // SIGINT → finalize file
    }
    Process {
        id: mkdirProc
        onExited: {
            recorder.command = store.recorderArgs(store.recordFile)
            recorder.running = true
            startCheck.restart()
        }
    }
    // If the recorder never started (e.g. gpu-screen-recorder missing),
    // say so instead of failing silently.
    Timer {
        id: startCheck
        interval: 1500
        onTriggered: if (!store.recording && !recorder.running)
            store.notify("Screen recording unavailable", "Install it with: sudo pacman -S gpu-screen-recorder", "dialog-error")
    }
    Process {
        id: recorder
        onStarted: { store.recording = true; store.recordStart = Date.now() }
        stderr: StdioCollector { id: recErr; waitForEnd: true }
        onExited: (code) => {
            const wasRecording = store.recording
            store.recording = false
            if (!wasRecording || (code !== 0 && code !== 130 && code !== 2)) {
                store.recordError = recErr.text.trim().split("\n").pop() || "Recording failed"
                notify("Screen recording failed", store.recordError, "dialog-error")
                return
            }
            notify("Screen recording saved", store.recordFile.replace(Quickshell.env("HOME"), "~"), "media-record")
        }
    }

    // ── Timers ────────────────────────────────────────────────────────
    // mode: "" | "timer" | "stopwatch" | "pomodoro"
    property string mode: ""
    property real endAt: 0          // timer/pomodoro: when it ends (ms)
    property real startAt: 0        // stopwatch: when it (re)started
    property real pausedLeft: 0     // ms left (timer) / elapsed (stopwatch) while paused
    property bool paused: false
    property real total: 0          // timer/pomodoro phase length (ms) for the ring
    property string phase: ""       // pomodoro: "Focus" | "Break"
    property int pomodoroCount: 0
    property real now: Date.now()

    readonly property bool timerActive: mode !== ""
    readonly property bool any: recording || timerActive
    readonly property real remaining: mode === "stopwatch" ? 0
        : paused ? pausedLeft : Math.max(0, endAt - now)
    readonly property real elapsed: mode === "stopwatch" ? (paused ? pausedLeft : now - startAt) : 0
    readonly property real progress: mode === "stopwatch" || total <= 0 ? 0 : 1 - remaining / total
    readonly property real recordElapsed: recording ? now - recordStart : 0

    Timer {
        interval: 250
        running: store.any
        repeat: true
        onTriggered: {
            store.now = Date.now()
            if ((store.mode === "timer" || store.mode === "pomodoro") && !store.paused && store.endAt > 0 && store.now >= store.endAt)
                store._finishPhase()
        }
    }

    function format(ms) {
        const s = Math.max(0, Math.round(ms / 1000))
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(sec).padStart(2, "0")
    }

    function startTimer(seconds, label) {
        mode = "timer"; phase = label || "Timer"
        total = seconds * 1000; endAt = Date.now() + total; paused = false; now = Date.now()
        _save()
    }
    function startStopwatch() {
        mode = "stopwatch"; phase = "Stopwatch"; startAt = Date.now(); paused = false; total = 0; now = Date.now()
        _save()
    }
    function startPomodoro() {
        mode = "pomodoro"; pomodoroCount = 0; _pomodoroPhase("Focus")
    }
    function _pomodoroPhase(p) {
        phase = p
        total = (p === "Focus" ? 25 : (pomodoroCount > 0 && pomodoroCount % 4 === 0 ? 15 : 5)) * 60000
        endAt = Date.now() + total; paused = false; now = Date.now()
        _save()
    }
    function togglePause() {
        if (!timerActive) return
        if (!paused) {
            pausedLeft = mode === "stopwatch" ? Date.now() - startAt : Math.max(0, endAt - Date.now())
            paused = true
        } else {
            if (mode === "stopwatch") startAt = Date.now() - pausedLeft
            else endAt = Date.now() + pausedLeft
            paused = false
        }
        now = Date.now()
        _save()
    }
    function addMinute() {
        if (mode !== "timer" && mode !== "pomodoro") return
        if (paused) pausedLeft += 60000
        else endAt += 60000
        total += 60000
        _save()
    }
    function stopTimer() { mode = ""; phase = ""; endAt = 0; startAt = 0; paused = false; total = 0; _save() }

    function _finishPhase() {
        chime.running = true
        if (mode === "pomodoro") {
            if (phase === "Focus") {
                pomodoroCount++
                notify("Focus done", "Time for a break.", "alarm-symbolic")
                _pomodoroPhase("Break")
            } else {
                notify("Break over", "Back to focus.", "alarm-symbolic")
                _pomodoroPhase("Focus")
            }
            return
        }
        notify(phase === "Timer" ? "Timer done" : phase, format(total) + " is up.", "alarm-symbolic")
        stopTimer()
    }

    // ── Helpers ───────────────────────────────────────────────────────
    Process { id: notifyProc }
    function notify(title, body, icon) {
        notifyProc.command = ["notify-send", "-a", "Island", "-i", icon || "dialog-information", title, body || ""]
        notifyProc.running = true
    }
    Process {
        id: chime
        command: ["pw-play", "/usr/share/sounds/freedesktop/stereo/complete.oga"]
    }

    // Persistence (debounced — see CLAUDE.md).
    FileView {
        id: file
        path: Quickshell.shellDir + "/activity.json"
        printErrors: false
        watchChanges: false
        onAdapterUpdated: saveTimer.restart()
        onLoaded: {
            store.mode = adapter.mode; store.endAt = adapter.endAt; store.startAt = adapter.startAt
            store.pausedLeft = adapter.pausedLeft; store.paused = adapter.paused; store.total = adapter.total
            store.phase = adapter.phase; store.pomodoroCount = adapter.pomodoroCount; store.now = Date.now()
        }
        JsonAdapter {
            id: adapter
            property string mode: ""
            property real endAt: 0
            property real startAt: 0
            property real pausedLeft: 0
            property bool paused: false
            property real total: 0
            property string phase: ""
            property int pomodoroCount: 0
        }
    }
    Timer { id: saveTimer; interval: 300; onTriggered: file.writeAdapter() }
    function _save() {
        adapter.mode = mode; adapter.endAt = endAt; adapter.startAt = startAt; adapter.pausedLeft = pausedLeft
        adapter.paused = paused; adapter.total = total; adapter.phase = phase; adapter.pomodoroCount = pomodoroCount
    }

    // "5m", "90s", "1h30m", "25" (minutes), "1:30" (m:s) → seconds, or 0.
    function parseDuration(t) {
        t = (t || "").trim().toLowerCase()
        if (/^\d+(\.\d+)?$/.test(t)) return Math.round(parseFloat(t) * 60)
        let m = t.match(/^(\d+):(\d{1,2})$/)
        if (m) return parseInt(m[1]) * 60 + parseInt(m[2])
        let total = 0, matched = false
        const re = /(\d+(?:\.\d+)?)\s*(h|hr|hours?|ó|óra|m|min|mins?|minutes?|p|perc|s|sec|secs?|seconds?|mp)/g
        while ((m = re.exec(t)) !== null) {
            matched = true
            const v = parseFloat(m[1]), u = m[2]
            total += /^(h|hr|hour|hours|ó|óra)$/.test(u) ? v * 3600 : /^(s|sec|secs|second|seconds|mp)$/.test(u) ? v : v * 60
        }
        return matched ? Math.round(total) : 0
    }
}
