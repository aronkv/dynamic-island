import Quickshell
import Quickshell.Io
import QtQuick

// Local calendar reminders in ~/.config/quickshell/calendar.json:
//   { "reminders": [{ id, title, date: "YYYY-MM-DD", time: "HH:MM"|"", fired }] }
// Saves are debounced (FileView re-read race). A 30 s timer
// fires due reminders through notify-send — the island's own notification
// server then shows them. All-day reminders fire at 09:00. Reminders more
// than 12 h overdue at startup are marked fired silently (no flood after a
// long shutdown).
Item {
    id: store
    visible: false

    property var reminders: []
    property bool _loaded: false
    // { "YYYY-MM-DD": count } for the month grid's dots.
    readonly property var countsByDay: {
        const c = {}
        for (const r of reminders) c[r.date] = (c[r.date] || 0) + 1
        return c
    }

    function forDay(iso) {
        return reminders.filter(r => r.date === iso)
            .sort((a, b) => (a.time || "99") < (b.time || "99") ? -1 : (a.time || "99") > (b.time || "99") ? 1 : 0)
    }
    // Next reminders from now on (for the "Upcoming" list).
    function upcoming(n) {
        const now = new Date()
        return reminders.filter(r => dueDate(r) >= new Date(now.getFullYear(), now.getMonth(), now.getDate()))
            .sort((a, b) => dueDate(a) - dueDate(b)).slice(0, n)
    }

    function dueDate(r) {
        const d = r.date.split("-").map(Number)
        const t = (r.time || "09:00").split(":").map(Number)
        return new Date(d[0], d[1] - 1, d[2], t[0], t[1])
    }

    function add(title, date, time) {
        const r = { id: Date.now().toString(36) + Math.random().toString(36).slice(2, 6), title: title, date: date, time: time || "", fired: false }
        // Adding something already due (e.g. "in 0 min") shouldn't fire twice.
        reminders = reminders.concat([r])
        saveTimer.restart()
        return r
    }
    function remove(id) {
        reminders = reminders.filter(r => r.id !== id)
        saveTimer.restart()
    }

    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell/calendar.json"
        printErrors: false
        watchChanges: false
        onLoaded: {
            try {
                const j = JSON.parse(text())
                store.reminders = Array.isArray(j.reminders) ? j.reminders : []
            } catch (e) {
                store.reminders = []
            }
            store._loaded = true
            store.check(true)
        }
        onLoadFailed: { store._loaded = true }
    }

    Timer {
        id: saveTimer
        interval: 200
        onTriggered: if (store._loaded) file.setText(JSON.stringify({ reminders: store.reminders }, null, 2))
    }

    Process { id: notifyProc }

    function check(startup) {
        if (!_loaded) return
        const now = new Date()
        let changed = false
        const due = []
        const next = reminders.map(r => {
            if (r.fired) return r
            const d = dueDate(r)
            if (d > now) return r
            changed = true
            if (!startup || now - d < 12 * 3600 * 1000) due.push(r)
            return Object.assign({}, r, { fired: true })
        })
        if (!changed) return
        reminders = next
        saveTimer.restart()
        for (const r of due) {
            notifyProc.command = ["notify-send", "-a", "Calendar", "-i", "x-office-calendar-symbolic",
                r.title, r.time ? "Reminder · " + r.time : "Reminder · today"]
            notifyProc.startDetached()
        }
    }

    Timer {
        interval: 30000
        running: store._loaded
        repeat: true
        onTriggered: store.check(false)
    }
}
