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

    // fuser walks every process's open files (~30 ms CPU per run). The
    // webcam's USB runtime-PM state is a cheap file read: uvcvideo wakes the
    // device on open(), so "suspended" means nobody has it open and fuser is
    // skipped. Any other state (or no such file) falls back to fuser.
    FileView {
        id: pmState
        path: "/sys/class/video4linux/video0/device/../power/runtime_status"
        blockLoading: true
        printErrors: false
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            pmState.reload()
            if (pmState.text().trim() === "suspended") {
                cameraMonitor._active = false
                return
            }
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
