import Quickshell
import Quickshell.Io
import QtQuick

// Quickshell (Qt) caches icon-theme lookups for the life of the process, so an
// app installed after the island started keeps showing the fallback icon.
// pacman's gtk-update-icon-cache hook rewrites hicolor's icon-theme.cache after
// practically every desktop-app install; when its mtime moves, restart the
// island via reload.sh. Polled (CameraMonitor/ScreenshotMonitor shape) rather
// than FileView.watchChanges, because the cache is replaced by an atomic
// rename, which drops a single-file watch.
Item {
    id: iconCacheMonitor

    property string _baseline: ""

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: statProc.running = true
    }

    // One pacman transaction can touch the cache more than once; let it settle
    // so a single restart covers the whole install.
    Timer {
        id: settleTimer
        interval: 3000
        onTriggered: Quickshell.execDetached([Quickshell.shellDir + "/reload.sh"])
    }

    Process {
        id: statProc
        command: ["stat", "-c", "%Y", "/usr/share/icons/hicolor/icon-theme.cache"]

        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const mtime = text.trim()
                if (mtime.length === 0) return
                if (iconCacheMonitor._baseline === "") {
                    iconCacheMonitor._baseline = mtime
                } else if (mtime !== iconCacheMonitor._baseline) {
                    iconCacheMonitor._baseline = mtime
                    settleTimer.restart()
                }
            }
        }
    }
}
