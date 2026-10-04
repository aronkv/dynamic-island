import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Spotlight-style app launcher that grows out of the island
// (displayState "launcher").
//  • Search field on top.
//  • Starred apps as square tiles (only while the query is empty).
//  • A vertical list of apps below — all apps (most launched first) when
//    the query is empty, ranked matches while typing.
//  • A math expression adds a "= result" row (Enter copies it).
// Star/unstar: the ☆ on a row, Ctrl+S on the selected item, or right-click
// a tile. Keys: arrows move (tiles: ←/→, ↓ into the list), Enter launches,
// Esc clears / closes. Stars + launch counts live in launcher-history.json.
FocusScope {
    id: launcher
    property bool active: false
    property var activity: null     // ActivityStore (timer / record commands)
    signal closeRequested()

    property string query: ""
    property int currentIndex: 0
    // Mouse-driven selection must not auto-scroll the list: scrolling moves
    // a different row under the cursor, which re-selects, which scrolls…
    property bool _mouseSelect: false
    function selectFromMouse(i) { _mouseSelect = true; currentIndex = i }

    onActiveChanged: {
        searchInput.text = ""
        currentIndex = 0
        list.positionViewAtBeginning()
        if (active) searchInput.forceActiveFocus()
    }
    onQueryChanged: {
        currentIndex = 0
        list.positionViewAtBeginning()
        fileRows = []
        // Computed from `query` directly: the `fileSearch` binding can still
        // hold its old value inside this handler.
        const q = query.trim()
        if (q.length >= 3 && !/^[:?]/.test(q)) fileTimer.restart()
    }

    // ── Persistence: launch counts + favorites ─────────────────────────
    FileView {
        id: historyFile
        path: Quickshell.shellDir + "/launcher-history.json"
        printErrors: false
        watchChanges: false
        onAdapterUpdated: saveTimer.restart()
        JsonAdapter {
            id: history
            property var counts: ({})
            property var favorites: []
        }
    }
    // Debounced save (writeAdapter re-reads the file).
    Timer { id: saveTimer; interval: 200; onTriggered: historyFile.writeAdapter() }

    function bump(id) {
        const c = Object.assign({}, history.counts)
        c[id] = (c[id] || 0) + 1
        history.counts = c
    }
    function isFavorite(id) { return (history.favorites || []).indexOf(id) !== -1 }
    function toggleFavorite(id) {
        const f = (history.favorites || []).slice()
        const i = f.indexOf(id)
        if (i === -1) f.push(id)
        else f.splice(i, 1)
        history.favorites = f
    }

    // ── Data ───────────────────────────────────────────────────────────
    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay)

    readonly property var favoriteApps: {
        const favs = history.favorites || []
        const out = []
        for (const id of favs) {
            const e = apps.find(a => a.id === id)
            if (e) out.push(e)
        }
        return out
    }

    function score(entry, q) {
        const name = (entry.name || "").toLowerCase()
        const generic = (entry.genericName || "").toLowerCase()
        const kw = (entry.keywords || []).join(" ").toLowerCase()
        const cmd = (entry.command || []).join(" ").toLowerCase()
        if (name === q) return 100
        if (name.startsWith(q)) return 80
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 65
        if (name.includes(q)) return 50
        if (generic.includes(q)) return 35
        if (kw.includes(q)) return 30
        if (cmd.includes(q)) return 20
        let i = 0
        for (const ch of name) if (ch === q[i]) i++
        return i === q.length ? 10 : -1
    }

    readonly property bool searching: query.trim() !== ""
    // ":fire" → emoji search, "?query" → web search only.
    readonly property bool emojiMode: query.replace(/^\s+/, "").startsWith(":")
    readonly property bool webOnly: query.replace(/^\s+/, "").startsWith("?")

    readonly property var listApps: {
        const q = launcher.query.trim().toLowerCase()
        const counts = history.counts || {}
        if (q === "")
            return apps.slice().sort((a, b) => (counts[b.id] || 0) - (counts[a.id] || 0) || a.name.localeCompare(b.name))
        return apps.map(e => ({ entry: e, s: launcher.score(e, q) }))
            .filter(r => r.s >= 0)
            .map(r => ({ entry: r.entry, s: r.s + Math.min(20, (counts[r.entry.id] || 0) * 2) }))
            .sort((a, b) => b.s - a.s || a.entry.name.localeCompare(b.entry.name))
            .map(r => r.entry)
    }

    CalcEngine { id: calc }
    // Date / currency / unit answers ("100 usd", "5 km to mi", "days until
    // xmas") first, then plain math.
    readonly property var calcSmart: {
        const q = launcher.query.trim()
        if (q.length < 3) return null
        const r = calc.smart(q)
        return r && !r.pending && !r.error ? r : null
    }
    readonly property string calcResult: {
        if (calcSmart) return calcSmart.text
        const q = launcher.query.trim()
        if (q.length < 2 || !/[0-9]/.test(q) || !/[+\-*/^%()×÷]|sqrt|sin|cos|log|ln|pi/.test(q)) return ""
        try { return calc.format(calc.evaluate(q)) } catch (e) { return "" }
    }

    // ── Extra rows: commands, calc, emoji (before apps); files, web (after) ──
    // Each: { kind, title, sub, glyph, glyphBg, icon, run: function }
    property var _emoji: []
    FileView {
        path: Quickshell.shellDir + "/emoji.json"
        printErrors: false
        onLoaded: { try { launcher._emoji = JSON.parse(text()) } catch (e) {} }
    }

    readonly property var preRows: {
        const q = query.trim()
        const rows = []
        if (q === "") return rows
        if (emojiMode) {
            const t = q.slice(1).trim().toLowerCase()
            if (t === "") return rows
            const words = t.split(/\s+/)
            // Rank: exact name, then name starting with the query, then a
            // whole word match, then any substring.
            const hits = []
            for (const e of _emoji) {
                const n = e.n.toLowerCase()
                if (!words.every(w => n.indexOf(w) !== -1)) continue
                const rank = n === t ? 0 : n.startsWith(t) ? 1 : (" " + n + " ").indexOf(" " + t + " ") !== -1 ? 2 : 3
                hits.push({ e: e, rank: rank, len: n.length })
            }
            hits.sort((a, b) => a.rank - b.rank || a.len - b.len)
            for (const h of hits.slice(0, 40))
                rows.push({ kind: "emoji", title: h.e.n.charAt(0).toUpperCase() + h.e.n.slice(1), sub: h.e.g + " · Enter copies",
                            glyph: h.e.c, glyphBg: "transparent", copy: h.e.c })
            return rows
        }
        if (webOnly) return [webRow(q.slice(1).trim())]
        const lq = q.toLowerCase()
        // Typed a web address (youtube.com, https://…, localhost:8080) →
        // "Open …" first, so Enter opens the site instead of searching it.
        const url = urlOf(q)
        if (url !== "") rows.push(urlRow(q, url))
        // Live-activity commands.
        if (activity) {
            const m = lq.match(/^(?:timer|t|időzítő)\s+(.+)$/)
            const secs = m ? activity.parseDuration(m[1]) : 0
            if (secs > 0)
                rows.push({ kind: "cmd", title: "Start timer · " + activity.format(secs * 1000), sub: "Counts down in the island",
                            glyph: "⏱", glyphBg: Theme.orange, cmd: "timer", secs: secs })
            const cmds = [
                { w: ["stopwatch", "stopper"], title: "Start stopwatch", cmd: "stopwatch", glyph: "⏱" },
                { w: ["pomodoro"], title: "Start pomodoro · 25 / 5", cmd: "pomodoro", glyph: "🍅" },
                { w: ["record", "screen record", "felvétel"], title: activity.recording ? "Stop screen recording" : "Record screen", cmd: "record", glyph: "●" }
            ]
            for (const c of cmds)
                if (lq.length >= 3 && c.w.some(w => w.startsWith(lq)))
                    rows.push({ kind: "cmd", title: c.title, sub: "Live activity in the island", glyph: c.glyph, glyphBg: c.cmd === "record" ? "#ff453a" : Theme.orange, cmd: c.cmd })
        }
        if (calcResult !== "")
            rows.push({ kind: "calc", title: calcResult, sub: calcSmart && calcSmart.sub ? calcSmart.sub : q, glyph: "=", glyphBg: Theme.orange })
        return rows
    }

    // "youtube.com", "www.x.hu/path", "https://…", "localhost:3000", IPs →
    // a URL; everything else (incl. file names like notes.txt) → "".
    function urlOf(q) {
        const t = q.trim()
        if (t === "" || /\s/.test(t)) return ""
        if (/^https?:\/\/\S+$/i.test(t)) return t
        if (/^(localhost|\d{1,3}(\.\d{1,3}){3})(:\d+)?(\/\S*)?$/i.test(t)) return "http://" + t
        const m = t.match(/^(?:[a-z0-9-]+\.)+([a-z]{2,24})(?::\d+)?(?:[\/?#]\S*)?$/i)
        if (!m) return ""
        const fileExt = /^(txt|md|pdf|png|jpe?g|gif|webp|svg|js|ts|py|qml|lua|sh|json|toml|ya?ml|conf|log|zip|tar|gz|mp3|mp4|mkv|flac|docx?|xlsx?|pptx?|odt|c|h|cpp|rs|go|java|css|html?)$/i
        if (fileExt.test(m[1]) && t.indexOf("/") === -1) return ""
        return "https://" + t
    }
    function urlRow(q, url) {
        const host = url.replace(/^https?:\/\//i, "").split(/[\/?#:]/)[0]
        return { kind: "web", title: "Open " + q.trim(), sub: url, glyph: "🌐", glyphBg: Theme.blue, url: url,
                 favicon: "https://www.google.com/s2/favicons?sz=64&domain=" + encodeURIComponent(host) }
    }

    function webRow(q) {
        return { kind: "web", title: "Search the web for “" + q + "”", sub: "Google", icon: "system-search-symbolic", glyphBg: "transparent", url: "https://www.google.com/search?q=" + encodeURIComponent(q) }
    }

    // Files via plocate (home only, no hidden paths), debounced.
    property var fileRows: []
    readonly property bool fileSearch: searching && !emojiMode && !webOnly && query.trim().length >= 3
    Timer {
        id: fileTimer
        interval: 220
        onTriggered: {
            fileProc.forQuery = launcher.query.trim()
            fileProc.command = ["plocate", "-i", "-l", "60", "--", fileProc.forQuery]
            fileProc.running = true
        }
    }
    Process {
        id: fileProc
        property string forQuery: ""
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (fileProc.forQuery !== launcher.query.trim()) return
                const home = Quickshell.env("HOME") + "/"
                const out = []
                for (const p of text.split("\n")) {
                    if (!p.startsWith(home)) continue
                    const rel = p.slice(home.length)
                    if (/(^|\/)\./.test(rel) || /node_modules|__pycache__|\/target\//.test(rel)) continue
                    const name = rel.split("/").pop()
                    const t = launcher.fileType(name)
                    out.push({ kind: "file", title: name, sub: "~/" + rel.slice(0, rel.length - name.length), path: p,
                               thumbKind: t.thumb, mime: t.icon, glyphBg: "transparent" })
                    if (out.length >= 5) break
                }
                launcher.fileRows = out
            }
        }
    }

    // Thumbnail source kind + fallback icon-theme name by extension.
    function fileType(name) {
        const ext = (name.match(/\.([^.]+)$/) || ["", ""])[1].toLowerCase()
        if (/^(png|jpe?g|webp|gif|bmp|svg|avif|tiff?)$/.test(ext)) return { thumb: "image", icon: "image-x-generic" }
        if (/^(mp3|flac|ogg|opus|m4a|wav|aac|wma)$/.test(ext)) return { thumb: "audio", icon: "audio-x-generic" }
        if (/^(mp4|mkv|webm|mov|avi|m4v)$/.test(ext)) return { thumb: "video", icon: "video-x-generic" }
        if (ext === "pdf") return { thumb: "pdf", icon: "application-pdf" }
        if (/^(docx?|odt|rtf|pptx?|odp|xlsx?|ods)$/.test(ext)) return { thumb: "", icon: "x-office-document" }
        if (/^(sh|py|js|qml|lua|c|cpp|h|rs|go|java|ts)$/.test(ext)) return { thumb: "", icon: "text-x-script" }
        if (/^(zip|tar|gz|xz|zst|7z|rar)$/.test(ext)) return { thumb: "", icon: "package-x-generic" }
        if (name.indexOf(".") === -1) return { thumb: "", icon: "folder" }
        return { thumb: "", icon: "text-x-generic" }
    }

    readonly property string thumbDir: Quickshell.env("HOME") + "/.cache/quickshell/thumbs"
    Process { command: ["mkdir", "-p", launcher.thumbDir]; running: true }

    readonly property var postRows: {
        if (!searching || emojiMode || webOnly) return []
        return fileRows.concat([webRow(query.trim())])
    }

    // One flat selection index: [tiles] + [preRows] + [apps] + [postRows].
    readonly property int tileCount: searching ? 0 : favoriteApps.length
    readonly property var shownApps: emojiMode || webOnly ? [] : listApps
    readonly property int preCount: preRows.length
    readonly property int itemCount: tileCount + preCount + shownApps.length + postRows.length
    function rowAt(r) {
        if (r < preCount) return preRows[r]
        r -= preCount
        if (r < shownApps.length) return { kind: "app", entry: shownApps[r] }
        return postRows[r - shownApps.length] || null
    }

    function itemAt(i) {
        if (i < tileCount) return { kind: "tile", entry: favoriteApps[i] }
        return rowAt(i - tileCount) || { kind: "none" }
    }

    function moveH(d) {
        if (currentIndex < tileCount) currentIndex = Math.max(0, Math.min(tileCount - 1, currentIndex + d))
    }
    function moveV(d) {
        if (itemCount === 0) return
        if (currentIndex < tileCount) {
            const cols = tilesFlow.columns
            const next = currentIndex + d * cols
            if (d > 0 && next >= tileCount) currentIndex = tileCount       // into the list
            else if (next >= 0) currentIndex = next
            return
        }
        const next = currentIndex + d
        if (next < tileCount) currentIndex = Math.max(0, tileCount - 1)  // back up into the tiles
        else currentIndex = Math.max(0, Math.min(itemCount - 1, next))
    }

    function launchEntry(entry) {
        if (!entry) return
        bump(entry.id)
        if (entry.runInTerminal) {
            termProc.command = ["kitty", "-e"].concat(entry.command)
            termProc.startDetached()
        } else {
            entry.execute()
        }
        launcher.closeRequested()
    }

    // `alt` = Ctrl+Enter: open the file's folder instead of the file.
    function activate(i, alt) {
        const it = itemAt(i)
        switch (it.kind) {
        case "tile":
        case "app":
            launchEntry(it.entry)
            return
        case "calc":
            copyProc.command = ["wl-copy", "--", calcSmart ? calcSmart.copy : calcResult.replace(/ /g, "")]
            copyProc.running = true
            break
        case "emoji":
            copyProc.command = ["wl-copy", "--", it.copy]
            copyProc.running = true
            break
        case "file":
            openProc.command = ["xdg-open", alt ? it.path.slice(0, it.path.lastIndexOf("/")) : it.path]
            openProc.startDetached()
            break
        case "web":
            openProc.command = ["xdg-open", it.url]
            openProc.startDetached()
            break
        case "cmd":
            if (!activity) return
            if (it.cmd === "timer") activity.startTimer(it.secs)
            else if (it.cmd === "stopwatch") activity.startStopwatch()
            else if (it.cmd === "pomodoro") activity.startPomodoro()
            else if (it.cmd === "record") activity.toggleRecording()
            break
        default:
            return
        }
        launcher.closeRequested()
    }

    Process { id: openProc }
    Process { id: copyProc }
    Process { id: termProc }

    component AppIcon: IconImage {
        property var entry: null
        source: entry ? Quickshell.iconPath(entry.icon, "application-x-executable") : ""
        asynchronous: true
        smooth: true
        mipmap: true
    }

    // File preview for a launcher file row. Images load directly; other
    // media first look for an existing thumbnail (freedesktop cache, then
    // ours), otherwise one is generated (ffmpeg cover art / ffmpegthumbnailer
    // / pdftoppm, argv only) and looked up again — music also falls back to
    // cover.jpg/folder.jpg next to the file. Existence is checked by a probe
    // Process (paths as positional args) so missing files never hit Image's
    // "Cannot open" warnings. Nothing found → the icon theme's mime icon.
    component FileThumb: Item {
        id: ft
        property var info: null
        readonly property string path: info && info.path ? info.path : ""
        readonly property string kind: info && info.thumbKind ? info.thumbKind : ""
        readonly property string hash: path !== "" ? Qt.md5("file://" + encodeURI(path)) : ""
        readonly property string cacheFile: launcher.thumbDir + "/" + hash + ".png"
        property string found: ""

        function covers() {
            if (kind !== "audio") return []
            const dir = path.slice(0, path.lastIndexOf("/") + 1)
            return ["cover.jpg", "folder.jpg", "front.jpg", "Cover.jpg", "cover.png"].map(c => dir + c)
        }
        function start() {
            found = ""
            probe.running = false
            gen.running = false
            if (path === "" || kind === "") return
            if (kind === "image") { found = path; return }
            const xdg = Quickshell.env("HOME") + "/.cache/thumbnails/"
            probe.afterGen = false
            probe.forPath = path
            probe.command = ["sh", "-c", "for f; do [ -s \"$f\" ] && { echo \"$f\"; exit 0; }; done; exit 1", "sh",
                             xdg + "normal/" + hash + ".png", xdg + "large/" + hash + ".png", cacheFile]
            probe.running = true
        }
        onPathChanged: start()
        Component.onCompleted: start()

        Process {
            id: probe
            property string forPath: ""
            property bool afterGen: false
            stdout: StdioCollector {
                onStreamFinished: {
                    if (probe.forPath !== ft.path) return
                    const f = text.trim()
                    if (f !== "") ft.found = f
                    else if (!probe.afterGen) ft.generate()
                }
            }
        }
        function generate() {
            gen.forPath = path
            if (kind === "audio")
                gen.command = ["ffmpeg", "-loglevel", "error", "-y", "-i", path, "-an", "-frames:v", "1", "-vf", "scale=128:-2", cacheFile]
            else if (kind === "video")
                gen.command = ["ffmpegthumbnailer", "-i", path, "-o", cacheFile, "-s", "128"]
            else if (kind === "pdf")
                gen.command = ["pdftoppm", "-png", "-singlefile", "-scale-to", "128", path, cacheFile.slice(0, -4)]
            else return
            gen.running = true
        }
        Process {
            id: gen
            property string forPath: ""
            onExited: {
                if (gen.forPath !== ft.path) return
                probe.afterGen = true
                probe.forPath = ft.path
                probe.command = ["sh", "-c", "for f; do [ -s \"$f\" ] && { echo \"$f\"; exit 0; }; done; exit 1", "sh",
                                 ft.cacheFile].concat(ft.covers())
                probe.running = true
            }
        }

        ClippingRectangle {
            anchors.fill: parent
            radius: 7
            color: "transparent"
            visible: thumbImg.status === Image.Ready
            Image {
                id: thumbImg
                anchors.fill: parent
                source: ft.found !== "" ? "file://" + ft.found : ""
                sourceSize.width: 64
                sourceSize.height: 64
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
        }
        IconImage {
            anchors.fill: parent
            visible: thumbImg.status !== Image.Ready
            source: ft.info ? Quickshell.iconPath(ft.info.mime || "text-x-generic", "text-x-generic") : ""
            asynchronous: true
            smooth: true
            mipmap: true
        }
    }

    component SectionLabel: Text {
        color: "#ffffff"
        opacity: 0.4
        font.pixelSize: 11
        font.weight: 600
        font.letterSpacing: 0.4
        font.family: Theme.fontText
    }

    // Star button used on list rows.
    component StarButton: Item {
        id: star
        property bool on: false
        property bool shown: true
        signal toggled()
        implicitWidth: 26
        implicitHeight: 26
        opacity: shown || on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: star.on ? "★" : "☆"
            color: star.on ? Theme.yellow : "#ffffff"
            opacity: star.on ? 1 : (starMouse.containsMouse ? 0.9 : 0.45)
            font.pixelSize: 16
            scale: starMouse.pressed ? 0.8 : 1
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
        }
        MouseArea {
            id: starMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: star.toggled()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 12
        spacing: 12

        // ── Search field ──────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: 22
            color: Theme.card
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.14 : 0.06)

            Item {
                id: searchIconSlot
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                IconImage {
                    id: searchIcon
                    anchors.fill: parent
                    source: "image://icon/system-search-symbolic"
                    visible: false
                    layer.enabled: true
                    smooth: true
                    mipmap: true
                }
                Rectangle { id: searchFill; anchors.fill: searchIcon; color: "#ffffff"; visible: false }
                MultiEffect {
                    anchors.fill: searchIcon
                    source: searchFill
                    maskEnabled: true
                    maskSource: searchIcon
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.0
                    maskThresholdMax: 1.0
                    maskSpreadAtMax: 0.0
                    opacity: 0.5
                }
            }

            TextInput {
                id: searchInput
                anchors.left: searchIconSlot.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                color: "#ffffff"
                font.pixelSize: 17
                font.family: Theme.font
                focus: true
                clip: true
                selectByMouse: true
                onTextChanged: launcher.query = text

                Keys.onDownPressed: launcher.moveV(1)
                Keys.onUpPressed: launcher.moveV(-1)
                Keys.onRightPressed: (event) => {
                    if (launcher.currentIndex < launcher.tileCount) launcher.moveH(1)
                    else event.accepted = false
                }
                Keys.onLeftPressed: (event) => {
                    if (launcher.currentIndex < launcher.tileCount) launcher.moveH(-1)
                    else event.accepted = false
                }
                Keys.onTabPressed: launcher.currentIndex = (launcher.currentIndex + 1) % Math.max(1, launcher.itemCount)
                Keys.onReturnPressed: (event) => launcher.activate(launcher.currentIndex, (event.modifiers & Qt.ControlModifier) !== 0)
                Keys.onEnterPressed: (event) => launcher.activate(launcher.currentIndex, (event.modifiers & Qt.ControlModifier) !== 0)
                Keys.onEscapePressed: {
                    if (text !== "") text = ""
                    else launcher.closeRequested()
                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                        const it = launcher.itemAt(launcher.currentIndex)
                        if (it.entry) launcher.toggleFavorite(it.entry.id)
                        event.accepted = true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length === 0
                    text: "Search apps, files, :emoji, ?web, timer 5m…"
                    color: "#ffffff"
                    opacity: 0.35
                    font: searchInput.font
                }
            }
        }

        // ── Favorite tiles ────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: launcher.tileCount > 0
            spacing: 8

            SectionLabel { text: "Favorites" }

            Grid {
                id: tilesFlow
                Layout.fillWidth: true
                columns: 6
                columnSpacing: 8
                rowSpacing: 8
                readonly property real tileSize: (width - columnSpacing * (columns - 1)) / columns

                Repeater {
                    model: launcher.searching ? [] : launcher.favoriteApps

                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        // Keyboard selection and mouse hover are separate and
                        // purely visual here: hover never changes the selection
                        // (that coupling made the tiles twitch while moving
                        // across them), it just lightens the tile instantly.
                        readonly property bool selected: launcher.currentIndex === index
                        readonly property bool hovered: tileHover.hovered
                        width: tilesFlow.tileSize
                        height: tilesFlow.tileSize
                        radius: 16
                        color: hovered ? Qt.rgba(1, 1, 1, 0.14) : Theme.card
                        border.width: 1.5
                        border.color: selected ? Qt.rgba(1, 1, 1, 0.45) : "transparent"
                        scale: tileMouse.pressed ? 0.95 : 1

                        AppIcon {
                            id: tileIcon
                            entry: tile.modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: parent.height * 0.16
                            implicitSize: parent.width * 0.42
                        }
                        Text {
                            anchors.top: tileIcon.bottom
                            anchors.topMargin: 5
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.name
                            color: "#ffffff"
                            opacity: tile.selected || tile.hovered ? 1 : 0.8
                            font.pixelSize: 10
                            font.weight: 500
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }

                        HoverHandler { id: tileHover }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) launcher.toggleFavorite(tile.modelData.id)
                                else launcher.activate(tile.index)
                            }
                        }
                    }
                }
            }
        }

        SectionLabel {
            visible: !launcher.searching
            text: "All Apps"
        }

        // ── App list ──────────────────────────────────────────────────
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: launcher.itemCount - launcher.tileCount
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400

            readonly property int selectedRow: launcher.currentIndex - launcher.tileCount
            onSelectedRowChanged: {
                if (selectedRow >= 0 && !launcher._mouseSelect) positionViewAtIndex(selectedRow, ListView.Contain)
                launcher._mouseSelect = false
            }

            delegate: Item {
                id: row
                required property int index
                readonly property var info: launcher.rowAt(index)
                readonly property bool isSpecial: info !== null && info.kind !== "app"
                readonly property bool isCalc: info !== null && info.kind === "calc"
                readonly property var entry: info && info.kind === "app" ? info.entry : null
                readonly property bool selected: list.selectedRow === index
                readonly property bool hovered: rowHover.hovered
                width: list.width
                height: 44

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: row.selected ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                }

                // HoverHandler instead of MouseArea hover: it keeps reporting
                // while the cursor is over the ☆ (a child MouseArea), so the
                // star no longer vanishes exactly when you point at it.
                HoverHandler {
                    id: rowHover
                    onHoveredChanged: if (hovered) launcher.selectFromMouse(launcher.tileCount + row.index)
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcher.activate(launcher.tileCount + row.index)
                }

                Item {
                    id: iconSlot
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30

                    AppIcon {
                        anchors.fill: parent
                        visible: !row.isSpecial
                        entry: row.entry
                    }
                    FileThumb {
                        anchors.fill: parent
                        visible: row.isSpecial && row.info.kind === "file"
                        info: visible ? row.info : null
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: row.isSpecial && row.info.kind !== "file"
                        // Symbolic icon (web search), flat white via alpha mask.
                        Item {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            visible: !!(row.info && row.info.icon)
                            IconImage {
                                id: rowSymIcon
                                anchors.fill: parent
                                source: row.info && row.info.icon ? "image://icon/" + row.info.icon : ""
                                visible: false
                                layer.enabled: true
                                smooth: true
                                mipmap: true
                            }
                            Rectangle { id: rowSymFill; anchors.fill: parent; color: "#ffffff"; visible: false }
                            MultiEffect {
                                anchors.fill: parent
                                source: rowSymFill
                                maskEnabled: true
                                maskSource: rowSymIcon
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 0.0
                                maskThresholdMax: 1.0
                                maskSpreadAtMax: 0.0
                            }
                        }
                        // Site favicon over the glyph once it has loaded.
                        Image {
                            id: favicon
                            anchors.centerIn: parent
                            width: 20
                            height: 20
                            source: row.info && row.info.favicon ? row.info.favicon : ""
                            sourceSize.width: 64
                            sourceSize.height: 64
                            asynchronous: true
                            smooth: true
                            visible: status === Image.Ready
                        }
                        radius: 8
                        color: favicon.visible ? "#ffffff" : row.info && row.info.glyphBg ? row.info.glyphBg : Theme.cardElevated
                        Text {
                            anchors.centerIn: parent
                            visible: !favicon.visible && !(row.info && row.info.icon)
                            text: row.info && row.info.glyph ? row.info.glyph : ""
                            color: "#ffffff"
                            font.pixelSize: row.info && row.info.kind === "emoji" ? 24 : 16
                            font.weight: 700
                        }
                    }
                }

                Column {
                    anchors.left: iconSlot.right
                    anchors.leftMargin: 12
                    anchors.right: trailing.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: row.isSpecial ? row.info.title : (row.entry ? row.entry.name : "")
                        color: "#ffffff"
                        font.pixelSize: row.isCalc ? 17 : 14
                        font.weight: 600
                        font.family: Theme.font
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: row.isSpecial ? (row.info.sub || "")
                            : row.entry ? (row.entry.genericName || row.entry.comment || "") : ""
                        color: "#ffffff"
                        opacity: 0.45
                        font.pixelSize: 11
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.selected && row.info && (row.isCalc || row.info.kind === "emoji")
                        width: hintText.implicitWidth + 14
                        height: 22
                        radius: 6
                        color: Qt.rgba(1, 1, 1, 0.1)
                        Text {
                            id: hintText
                            anchors.centerIn: parent
                            text: "Copy ↵"
                            color: "#ffffff"
                            opacity: 0.7
                            font.pixelSize: 10
                            font.weight: 600
                            font.family: Theme.fontText
                        }
                    }

                    StarButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.isSpecial
                        on: row.entry ? launcher.isFavorite(row.entry.id) : false
                        shown: row.selected || row.hovered
                        onToggled: if (row.entry) launcher.toggleFavorite(row.entry.id)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: "No results for “" + launcher.query.trim() + "”"
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 13
                font.family: Theme.fontText
            }
        }
    }
}
