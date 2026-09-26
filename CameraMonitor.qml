import Quickshell.Io
import QtQuick

Item {
    id: cameraMonitor

    // fuser/lsof-based polling heuristic: Quickshell has no camera-usage
    // signal, unlike Pipewire's mic-capture flag. This only detects apps
    // that hold /dev/video* open directly (most v4l2 camera apps); it will
    // not catch a portal-routed camera stream that never opens the device node.
    readonly property bool active: _active

    property bool _active: false
    property bool _foundThisRun: false

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            cameraMonitor._foundThisRun = false
            checkProc.running = true
        }
    }

    Process {
        id: checkProc
        command: ["sh", "-c", "fuser /dev/video* 2>/dev/null"]

        stdout: SplitParser {
            onRead: (line) => {
                if (line.trim().length > 0) cameraMonitor._foundThisRun = true
            }
        }

        onExited: cameraMonitor._active = cameraMonitor._foundThisRun
    }
}
