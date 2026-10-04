import Quickshell.Hyprland
import Quickshell
import Quickshell.Io
import QtQuick

// Hyprland border colors + the Island's own accent token — persisted via
// SettingsStore and applied live via `hyprctl eval`. Driven entirely by
// ThemeProfiles.applyProfile() now (the Theme panel's carousel is the
// only entry point — no more separate Manual/Adaptive mode or manual hex
// fields, those were removed in this redesign). This component just
// holds the current values and knows how to push them to the running
// compositor; it no longer decides *when* they change.
//
// Border colors are stored as 8-hex-digit RRGGBBAA strings (not plain
// RRGGBB) so the real live alpha values already in use
// (general:col.active_border was fully opaque, general:col.inactive_border
// was ~67% opaque) are preserved exactly rather than silently flattened to
// full opacity.
Item {
    id: themeColorMonitor

    property var settingsStore: null

    readonly property string activeBorderColor: settingsStore ? settingsStore.themeActiveBorder : "ff0000ff"
    readonly property string inactiveBorderColor: settingsStore ? settingsStore.themeInactiveBorder : "595959aa"
    readonly property color accentColor: settingsStore ? settingsStore.themeAccent : "#ffffff"

    function setActiveBorderColor(hex) { if (settingsStore) settingsStore.themeActiveBorder = hex }
    function setInactiveBorderColor(hex) { if (settingsStore) settingsStore.themeInactiveBorder = hex }
    function setAccentColor(hex) { if (settingsStore) settingsStore.themeAccent = hex }

    // `hyprctl keyword` refuses to run at all on this system — real, live-
    // tested finding: this Hyprland config is Lua-based (hl.config(...) in
    // look-and-feel.lua), and hyprctl itself reports "keyword can't work
    // with non-legacy parsers. Use eval." for EVERY keyword, not just these
    // two (confirmed the same failure on an unrelated existing keyword too).
    // `hyprctl eval '<lua expression>'` is the real, confirmed-working
    // mechanism for a Lua-configured Hyprland — it re-runs an hl.config(...)
    // call exactly like the one already in look-and-feel.lua, live, without
    // touching that file. Mirrors that file's own structure: active_border
    // is a table with a `colors` array, inactive_border is a plain string.
    // One queued runner for all border evals. Re-setting `running = true`
    // on a Process that is still running is a no-op in Quickshell (see
    // MatugenMonitor), so switching themes quickly silently dropped the
    // second border change — the "border doesn't always change" bug.
    // Commands queue here and run one after another; only the newest
    // pending command per key is kept.
    property var _pending: ({})
    property var _order: []
    function _queue(key, cmd) {
        const p = _pending
        if (!(key in p)) _order.push(key)
        p[key] = cmd
        _pending = p
        _next()
    }
    function _next() {
        if (borderProc.running || _order.length === 0) return
        const key = _order.shift()
        const cmd = _pending[key]
        delete _pending[key]
        borderProc.command = cmd
        borderProc.running = true
    }
    Process {
        id: borderProc
        onExited: themeColorMonitor._next()
    }

    // `command` is computed here from the already-current value (a bound
    // command lags one change behind).
    onActiveBorderColorChanged: _queue("active", ["hyprctl", "eval",
        "hl.config({general={col={active_border={colors={\"rgba(" + activeBorderColor + ")\"}}}}})"])
    onInactiveBorderColorChanged: _queue("inactive", ["hyprctl", "eval",
        "hl.config({general={col={inactive_border=\"rgba(" + inactiveBorderColor + ")\"}}})"])
    Component.onCompleted: {
        activeBorderColorChanged()
        inactiveBorderColorChanged()
    }

    // `hyprctl reload` resets the borders to the .lua file's defaults —
    // re-apply the theme's colors after every reload.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded") return
            themeColorMonitor.activeBorderColorChanged()
            themeColorMonitor.inactiveBorderColorChanged()
        }
    }
}
