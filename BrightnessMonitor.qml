import Quickshell.Io
import QtQuick

Item {
    id: brightnessMonitor

    readonly property string _basePath: "/sys/class/backlight/intel_backlight/"

    // max_brightness never changes at runtime — read it once, don't watch it.
    Process {
        id: maxBrightnessProc
        command: ["cat", brightnessMonitor._basePath + "max_brightness"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const n = parseInt(text, 10)
                if (!isNaN(n) && n > 0) brightnessMonitor._maxBrightness = n
            }
        }
        Component.onCompleted: running = true
    }

    property real _maxBrightness: 0

    // sysfs brightness has no push-notify mechanism (unlike Pipewire's
    // volume), so this is read off a watched file instead. Confirmed by
    // testing (not assumed): watchChanges alone only makes fileChanged fire
    // when the file changes on disk — it does NOT re-read the content into
    // text()/textChanged on its own. An explicit reload() in onFileChanged
    // is required, or the exposed text stays stuck at whatever it was when
    // the FileView first loaded.
    FileView {
        id: brightnessFile
        path: brightnessMonitor._basePath + "brightness"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }

    // Brightness is stepped by the island itself (IPC `brightness up/down`,
    // bound to the XF86MonBrightness keys): a fixed table of `steps`
    // perceptual levels, raw = max · (i/steps)^gamma, with step 0 = raw 1 so
    // the panel never goes fully black. The previous `brightnessctl -e4 -n2
    // set 5%±` rounded to integers on a 4th-power curve — tiny/stuck steps
    // at the bottom, huge ones at the top — and the OSD had to invert that.
    readonly property int steps: 20
    readonly property real gamma: 2.2
    function rawFor(i) {
        if (i <= 0) return 1
        return Math.max(1, Math.round(_maxBrightness * Math.pow(i / steps, gamma)))
    }
    // Nearest step for a raw value (external changes, startup).
    function stepFor(raw) {
        if (_maxBrightness <= 0) return 0
        const x = Math.pow(Math.max(0, raw) / _maxBrightness, 1 / gamma) * steps
        return Math.max(0, Math.min(steps, Math.round(x)))
    }

    readonly property int _rawNow: {
        const n = parseInt(brightnessFile.text(), 10)
        return isNaN(n) ? -1 : n
    }
    // The step we last set ourselves; -1 = follow sysfs.
    property int _ownStep: -1
    property int _ownRaw: -1
    // _ownFresh: we set a level < 1 s ago. sysfs doesn't reliably notify
    // (inotify on attribute writes), so until the file is re-read _rawNow is
    // still the old value — basing the next step on it made held / fast
    // key presses re-set the same level over and over (slow ramp).
    // It stays set until the file actually reads back our value (forcing a
    // re-read after 1 s, giving up after ~3 s): dropping it on a timer alone
    // let the OSD jump back to a stale level after a long hold.
    property bool _ownFresh: false
    Timer {
        id: ownFreshTimer
        interval: 1000
        repeat: true
        property int tries: 0
        onTriggered: {
            if (brightnessMonitor._rawNow === brightnessMonitor._ownRaw || ++tries > 2) {
                brightnessMonitor._ownFresh = false
                stop()
            } else {
                brightnessFile.reload()
            }
        }
    }
    readonly property int stepIndex: (_ownStep >= 0 && (_ownFresh || _rawNow === _ownRaw || _rawNow < 0))
        ? _ownStep : stepFor(_rawNow)

    // 0..1 level for the OSD — exactly stepIndex/steps, so the bar sits on
    // the same grid the keys move on.
    readonly property real level: _maxBrightness > 0 ? stepIndex / steps : 0

    // direction: +1 / -1; moved: false when already at the end (the OSD's
    // sun only turns when the brightness actually changed).
    signal stepped(int direction, bool moved)

    Process { id: setProc }

    function step(direction) {
        if (_maxBrightness <= 0) return
        const cur = stepIndex
        const next = Math.max(0, Math.min(steps, cur + direction))
        const moved = next !== cur
        if (moved) {
            _ownStep = next
            _ownRaw = rawFor(next)
            _ownFresh = true
            ownFreshTimer.tries = 0
            ownFreshTimer.restart()
            setProc.command = ["brightnessctl", "-q", "set", String(_ownRaw)]
            setProc.startDetached()
        }
        stepped(direction, moved)
    }
}
