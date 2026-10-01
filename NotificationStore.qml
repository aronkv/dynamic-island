import Quickshell
import Quickshell.Io
import QtQuick

// Notification history (SUPER+N panel). Every incoming notification is
// copied into `items` (newest first, max 100) and persisted, debounced, to
// notifications.json so the history survives restarts. The live
// Notification objects of the 20 newest stay tracked (in `_live`, by uid) so
// clicking an entry can still invoke its default action; older ones are
// released. `unread` counts entries added since the panel was last opened.
Item {
    id: store

    property var items: []            // [{ uid, app, summary, body, icon, time }]
    property var _live: ({})          // uid -> Notification (tracked)
    property int unread: 0
    readonly property int maxItems: 100
    readonly property int maxLive: 20
    property int _seq: 0

    FileView {
        id: file
        path: Quickshell.shellDir + "/notifications.json"
        printErrors: false
        watchChanges: false
        onAdapterUpdated: saveTimer.restart()
        onLoaded: {
            store.items = adapter.items || []
            store.unread = adapter.unread || 0
            store._seq = store.items.reduce((m, it) => Math.max(m, it.uid || 0), 0)
        }
        JsonAdapter {
            id: adapter
            property var items: []
            property int unread: 0
        }
    }
    // Debounced (writeAdapter re-reads the file — see CLAUDE.md).
    Timer { id: saveTimer; interval: 300; onTriggered: file.writeAdapter() }
    function _persist() {
        adapter.items = store.items
        adapter.unread = store.unread
    }

    // Content picture/icon of a notification. Real pictures (image hint,
    // file path) come back as a loadable URL; theme icon names only when the
    // theme actually has them (e.g. CachyOS's "system-reboot" doesn't exist
    // and would render as the magenta "missing icon" checkerboard).
    // Quickshell hands both over as "image://icon/<name or /abs/path>".
    function _resolve(src) {
        src = String(src || "")
        if (src.startsWith("image://icon/")) src = src.slice("image://icon/".length)
        if (src === "") return ""
        if (src.startsWith("/")) return "file://" + src
        if (src.indexOf("://") !== -1) return src          // file://, image://qsimage/…
        return Quickshell.iconPath(src, true)              // theme name → "" if missing
    }
    function _iconFor(n) {
        return _resolve(n.image) || _resolve(n.appIcon)
    }

    // The sending app's own icon (shown top-left of the banner and next to
    // each group in the history), separate from the notification's content
    // icon/image. CachyOS's updater sends a generic "system-reboot" icon,
    // so it gets the CachyOS logo; everything else resolves through its
    // desktop entry (by id, then a heuristic name match). "" = no icon.
    function appIconFor(app, desktopEntryId) {
        const a = String(app || "").toLowerCase()
        if (a.indexOf("cachyos") !== -1) return "file:///usr/share/icons/cachyos.svg"
        let e = desktopEntryId ? DesktopEntries.byId(desktopEntryId) : null
        if (!e && app) e = DesktopEntries.heuristicLookup(app)
        if (e && e.icon) {
            if (e.icon.startsWith("/")) return "file://" + e.icon
            return Quickshell.iconPath(e.icon, true)
        }
        return ""
    }

    function add(n) {
        const uid = ++_seq
        const entry = {
            uid: uid,
            app: n.appName || "Notification",
            summary: n.summary || "",
            body: (n.body || "").replace(/<[^>]*>/g, ""),
            icon: _iconFor(n),
            appIcon: appIconFor(n.appName, n.desktopEntry),
            time: Date.now()
        }
        const list = [entry].concat(items)
        // Release live objects that fall out of the tracked window / list.
        const keep = {}
        for (let i = 0; i < Math.min(maxLive, list.length); i++) keep[list[i].uid] = true
        const live = Object.assign({}, _live)
        live[uid] = n
        for (const k in live) if (!keep[k]) { try { live[k].tracked = false } catch (e) {} delete live[k] }
        n.tracked = true
        _live = live
        items = list.slice(0, maxItems)
        unread = unread + 1
        _persist()
        return uid
    }

    function isLive(uid) { return _live[uid] !== undefined }

    // Default action if the app still listens, then drop it from the list.
    function activate(uid) {
        const n = _live[uid]
        if (n) {
            const act = (n.actions || []).find(a => a.identifier === "default") || (n.actions || [])[0]
            try { if (act) act.invoke() } catch (e) {}
        }
        remove(uid)
    }

    function remove(uid) {
        const n = _live[uid]
        if (n) {
            try { n.dismiss() } catch (e) {}
            const live = Object.assign({}, _live)
            delete live[uid]
            _live = live
        }
        items = items.filter(it => it.uid !== uid)
        _persist()
    }

    function clearApp(app) {
        for (const it of items.filter(x => x.app === app)) {
            const n = _live[it.uid]
            if (n) try { n.dismiss() } catch (e) {}
        }
        const live = Object.assign({}, _live)
        for (const it of items) if (it.app === app) delete live[it.uid]
        _live = live
        items = items.filter(it => it.app !== app)
        _persist()
    }

    function clearAll() {
        for (const k in _live) try { _live[k].dismiss() } catch (e) {}
        _live = ({})
        items = []
        unread = 0
        _persist()
    }

    function markRead() {
        if (unread === 0) return
        unread = 0
        _persist()
    }
}
