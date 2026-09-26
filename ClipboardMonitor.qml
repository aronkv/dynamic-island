import Quickshell
import Quickshell.Io
import QtQuick

// Clipboard history via cliphist (stored by the two `wl-paste --watch
// cliphist store` watchers in autostart.lua). Lists on demand (the panel
// calls refresh() when it opens), classifies each entry, decodes image
// thumbnails into a cache dir, and copies/deletes/wipes entries.
// Every Process is an argv list; ids are validated as digits and passed as
// positional args to fixed `sh -c` scripts, never spliced into them.
Item {
    id: root
    visible: false

    // [{ id, text, kind: text|link|code|color|image|file, meta }]
    property var entries: []
    property bool loading: false
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/quickshell/cliphist-thumbs"
    // Bumped when thumbnails finish decoding so image sources re-resolve.
    property int thumbVersion: 0

    function classify(t) {
        let m = t.match(/^\[\[ binary data (.+?) ([a-z0-9+]+) (\d+x\d+) \]\]$/i)
        if (m) return { kind: "image", meta: m[3].replace("x", "×") + " · " + m[2].toUpperCase() + " · " + m[1] }
        if (/^\[\[ binary data/.test(t)) return { kind: "file", meta: "Binary data" }
        const s = t.trim()
        if (/^(file:\/\/\S+\s*)+$/.test(s) || /^(~|\/)[^\s]*\/[^\s]*$/.test(s)) return { kind: "file", meta: "" }
        if (/^(https?:\/\/|www\.)\S+$/i.test(s)) {
            const host = s.replace(/^https?:\/\//i, "").split(/[/?#]/)[0]
            return { kind: "link", meta: host }
        }
        if (/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(s)) return { kind: "color", meta: s }
        const fn = s.match(/^(rgba?|hsla?)\(\s*([\d.]+)(%?)[\s,]+([\d.]+)(%?)[\s,]+([\d.]+)(%?)(?:[\s,/]+([\d.]+)(%?))?\s*\)$/i)
        if (fn) {
            // QML colors don't parse rgb()/hsl() strings — convert to a color.
            const a = fn[8] === undefined ? 1 : (fn[9] ? fn[8] / 100 : +fn[8])
            const c = /^rgb/i.test(fn[1])
                ? Qt.rgba((fn[3] ? fn[2] * 2.55 : +fn[2]) / 255, (fn[5] ? fn[4] * 2.55 : +fn[4]) / 255, (fn[7] ? fn[6] * 2.55 : +fn[6]) / 255, a)
                : Qt.hsla((+fn[2] % 360) / 360, fn[4] / 100, fn[6] / 100, a)
            return { kind: "color", meta: c.toString() }
        }
        const codeHints = /(\bfunction\b|\bconst\b|\blet\b|\bdef\b|\bclass\b|\bimport\b|\breturn\b|=>|#include|\bfn\b|\bpub\b|<\/\w+>|\bif\s*\(|;\s*$|\{\s*$|^\s*[\w.]+\s*\(.*\)\s*;?$)/m
        const shell = /^(sudo|git|cd|ls|cat|cp|mv|rm|mkdir|pacman|yay|paru|npm|npx|pnpm|cargo|python3?|pip|node|qs|hyprctl|systemctl|journalctl|curl|wget|ssh|docker|make|chmod|chown|grep|sed|awk|find|echo|export)\b/
        if (shell.test(s) || /^<(\?xml|!doctype|[a-z][\w-]*[\s>])/i.test(s) || (codeHints.test(s) && /[{}();=]/.test(s))) return { kind: "code", meta: "" }
        return { kind: "text", meta: "" }
    }

    function refresh() {
        if (listProc.running) return
        loading = true
        listProc.running = true
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                const imageIds = []
                const lines = text.split("\n")
                for (let i = 0; i < lines.length && out.length < 300; i++) {
                    const line = lines[i]
                    const tab = line.indexOf("\t")
                    if (tab <= 0) continue
                    const id = line.slice(0, tab)
                    if (!/^\d+$/.test(id)) continue
                    const t = line.slice(tab + 1)
                    const c = root.classify(t)
                    out.push({ id: id, text: t, kind: c.kind, meta: c.meta })
                    if (c.kind === "image" && imageIds.length < 40) imageIds.push(id)
                }
                root.entries = out
                root.loading = false
                if (imageIds.length > 0) {
                    thumbProc.command = ["sh", "-c",
                        "d=$1; shift; mkdir -p \"$d\"; for id; do [ -s \"$d/$id.img\" ] || cliphist decode \"$id\" > \"$d/$id.img\"; done",
                        "sh", root.thumbDir].concat(imageIds)
                    thumbProc.running = true
                }
            }
        }
        onExited: (code) => { if (code !== 0) root.loading = false }
    }

    Process {
        id: thumbProc
        onExited: root.thumbVersion++
    }

    function thumbUrl(id) { return "file://" + thumbDir + "/" + id + ".img" }

    Process { id: copyProc }
    function copy(id) {
        if (!/^\d+$/.test(id)) return
        copyProc.command = ["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", id]
        copyProc.running = true
    }

    Process {
        id: deleteProc
        onExited: root.refresh()
    }
    function remove(id) {
        if (!/^\d+$/.test(id)) return
        // Optimistic: drop it from the list right away.
        root.entries = root.entries.filter(e => e.id !== id)
        deleteProc.command = ["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete; rm -f \"$2/$1.img\"", "sh", id, root.thumbDir]
        deleteProc.running = true
    }

    Process {
        id: wipeProc
        onExited: root.refresh()
    }
    function wipe() {
        root.entries = []
        wipeProc.command = ["sh", "-c", "cliphist wipe; rm -rf \"$1\"", "sh", root.thumbDir]
        wipeProc.running = true
    }
}
