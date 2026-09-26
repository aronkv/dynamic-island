import Quickshell
import Quickshell.Io
import QtQuick

// Lists image files in a configurable folder (default ~/Pictures/Wallpapers,
// created if missing) and applies a click via hyprpaper's real IPC —
// confirmed live: `hyprctl hyprpaper wallpaper "<monitor>,<path>"`. Also
// rewrites hyprpaper.conf so the choice survives a hyprpaper restart (the
// IPC call alone is live-only, not persistent).
//
// Real bug found live (2026-09-20): a picked wallpaper applied instantly
// in the running session but never reappeared after a real re-login — it
// kept coming back to a stale `~/Downloads/T480.png` that isn't even in
// this app's own wallpaper folder. Root cause was the OLD version of this
// file's persistence step: `sed -i 's|^path = .*|path = <new>|'` anchored
// the pattern at column 0 (`^path`), but the actual line in
// hyprpaper.conf's `wallpaper { ... }` block is indented ("    path =
// ..."), so the substitution never matched anything — every single click
// silently failed to persist, forever leaving whatever path was on disk
// at first install. (A red herring chased first: this system's hyprpaper
// — v0.8.4, built against hyprtoolkit/hyprwire, notably newer/different
// from the classic documented hyprpaper — was wrongly assumed to want
// flat `preload =`/`wallpaper =` lines instead of this nested block;
// tested live and confirmed the nested `wallpaper { monitor; path;
// fit_mode }` shape IS this version's real, working syntax, and a bare
// `hyprctl hyprpaper wallpaper eDP-1,<path>` alone — no separate preload
// call, which this version's IPC doesn't even expose — already applies
// live instantly.) Fixed by rewriting the whole file (not patching one
// line) so indentation can never desync the pattern again.
Item {
    id: wallpaperMonitor

    property string folder: ""
    property var images: []
    // The currently-applied wallpaper's path — read once from hyprpaper's
    // own live IPC state at startup (more reliable than re-parsing the
    // conf file, and self-correcting if the conf was ever hand-edited or,
    // as found live, malformed), then kept in sync locally whenever
    // applyWallpaper() changes it.
    property string currentPath: ""

    readonly property string _confPath: Quickshell.env("HOME") + "/.config/hypr/hyprpaper.conf"

    Process {
        id: currentPathProc
        command: ["hyprctl", "hyprpaper", "listactive"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                // "<monitor>: <path>" per line — this machine has one
                // monitor (eDP-1, same assumption applyWallpaper() makes),
                // so the first line is enough.
                const line = text.split("\n").map(s => s.trim()).find(s => s.length > 0)
                if (!line) return
                const idx = line.indexOf(":")
                if (idx === -1) return
                wallpaperMonitor.currentPath = line.slice(idx + 1).trim()
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: mkdirProc
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                wallpaperMonitor.images = text.split("\n").map(s => s.trim()).filter(s => s.length > 0)
            }
        }
    }

    function refresh() {
        if (!wallpaperMonitor.folder) return
        mkdirProc.command = ["mkdir", "-p", wallpaperMonitor.folder]
        mkdirProc.running = true
        listProc.command = ["find", wallpaperMonitor.folder, "-maxdepth", "1", "-type", "f",
            "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")"]
        listProc.running = true
    }

    onFolderChanged: refresh()

    Process {
        id: applyProc
    }

    Process {
        id: rewriteConfProc
    }

    function applyWallpaper(path) {
        // "eDP-1" is this machine's only monitor (confirmed via
        // hyprpaper.conf's own existing `monitor = eDP-1` line) — a
        // multi-monitor setup would need to target the actual focused
        // output instead, out of scope here since there's only one.
        applyProc.command = ["hyprctl", "hyprpaper", "wallpaper", "eDP-1," + path]
        applyProc.running = true
        wallpaperMonitor.currentPath = path

        // Rewrites the whole file rather than patching one line — see the
        // header comment for why a targeted sed patch is exactly what
        // broke persistence last time (an indentation-sensitive anchor
        // silently never matching). `sh -c` with the path passed as a
        // positional parameter ($1), not interpolated into the script
        // text, keeps this safe for an arbitrary/untrusted path (CLAUDE.md's
        // Process-security convention) while still letting a shell do the
        // file redirection `printf` alone can't.
        rewriteConfProc.command = ["sh", "-c",
            'printf "wallpaper {\\n    monitor = eDP-1\\n    path = %s\\n    fit_mode = cover\\n}\\nsplash = false\\n" "$1" > "$2"',
            "_", path, wallpaperMonitor._confPath]
        rewriteConfProc.running = true
    }
}
