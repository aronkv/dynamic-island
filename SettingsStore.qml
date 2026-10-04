import Quickshell.Hyprland
import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: settingsStore

    property alias blurEnabled: adapter.blurEnabled
    property alias micIndicatorEnabled: adapter.micIndicatorEnabled
    property alias cameraIndicatorEnabled: adapter.cameraIndicatorEnabled
    property alias doNotDisturb: adapter.doNotDisturb
    // What renders next to the clock in the idle pill while something is
    // actually playing: "art" (album-art thumbnail, no text — the new
    // default), "title" (track title+artist text — the old standalone
    // "mediaMini" behavior), or "lyrics" (current synced/plain lyrics line).
    property alias idlePlayerMode: adapter.idlePlayerMode
    // Auto-switch to Power Saver on battery at <=20% (BatteryMonitor.qml).
    property alias autoLowPower: adapter.autoLowPower
    // Battery badge left of the pill while on battery (BatteryBadge.qml),
    // and whether it shows the percentage next to the glyph.
    property alias batteryBadge: adapter.batteryBadge
    property alias batteryBadgePercent: adapter.batteryBadgePercent
    // Calculator: show the history column permanently (else via its button).
    property alias calcHistoryAlways: adapter.calcHistoryAlways
    // "Rain in ~15 min" alert in the island (WeatherMonitor minutely data).
    property alias rainAlert: adapter.rainAlert
    property alias reduceMotion: adapter.reduceMotion
    // Night Shift (NightLight.qml / hyprsunset).
    property alias nightLight: adapter.nightLight
    // Screen recording (gpu-screen-recorder, read when a recording starts).
    property alias recordResolution: adapter.recordResolution   // "native" | "1080" | "720" | "480"
    property alias recordFps: adapter.recordFps                 // 30 | 60
    property alias recordQuality: adapter.recordQuality         // "medium" | "high" | "very_high" | "ultra"
    property alias recordSystemAudio: adapter.recordSystemAudio
    property alias recordMic: adapter.recordMic
    property alias recordCursor: adapter.recordCursor
    property alias nightLightTemp: adapter.nightLightTemp
    property alias nightLightSchedule: adapter.nightLightSchedule   // "sunset" | "always"
    property alias obsidianFollowTheme: adapter.obsidianFollowTheme   // Island theme: follow accent vs static Apple
    // Folder the Wallpaper switcher browses for images — created on first
    // use if missing, so a fresh install still has somewhere to point at.
    property alias wallpaperFolder: adapter.wallpaperFolder
    // Manual pill/strip preference ("pill"/"strip") — DynamicIsland.qml's
    // pillModeEffective additionally forces "strip" whenever the focused
    // window is fullscreen, regardless of this value, reverting to it once
    // fullscreen ends.
    property alias pillMode: adapter.pillMode
    // Weather manual-location override — when enabled, WeatherMonitor.qml
    // geocodes weatherCity instead of IP-geolocating, since IP geolocation
    // is sometimes inaccurate (ISP-level, confirmed not a code bug). Empty
    // weatherCity with the override on is treated the same as override off.
    property alias weatherManualLocation: adapter.weatherManualLocation
    property alias weatherCity: adapter.weatherCity
    // Hyprland border colors (RRGGBBAA hex, alpha included) + the Island's
    // own accent token, applied live via hyprctl eval in
    // ThemeColorMonitor.qml. Defaults are the REAL values this system's
    // Hyprland config already had before this feature existed (confirmed
    // live via `hyprctl getoption general:col.active_border/inactive_border`
    // — ff0000ff at full opacity, 595959aa at ~67% opacity) so a fresh load
    // re-applies a byte-identical value instead of silently changing the
    // border's look. Driven entirely by ThemeProfiles.applyProfile() now.
    property alias themeActiveBorder: adapter.themeActiveBorder
    property alias themeInactiveBorder: adapter.themeInactiveBorder
    property alias themeAccent: adapter.themeAccent
    // Name of the last-applied Theme-panel carousel entry ("T480",
    // "Dynamic", "Blue", ...) — lets the panel reopen positioned on the
    // actually-active theme and show a checkmark on it. Explicitly
    // persisted on change (see onCurrentThemeProfileChanged below) rather
    // than relying on JsonAdapter's own write-back, since that wasn't
    // reliably observed for a plain property change in this project.
    property alias currentThemeProfile: adapter.currentThemeProfile

    FileView {
        id: settingsFile
        // FileView.path does NOT expand `~` (confirmed the hard way — an
        // earlier version of this file using "~/..." silently created a
        // literal directory named "~" under the process's cwd instead).
        // Quickshell.env(...) is a real, confirmed method on the base
        // Quickshell singleton, so this resolves the home dir properly
        // instead of hardcoding the current user's name.
        path: Quickshell.env("HOME") + "/.config/quickshell/settings.json"
        printErrors: false
        // Saving is debounced (saveTimer) and file watching is off. Verified
        // in an isolated test: writeAdapter() re-reads the file shortly
        // after writing, so a property changed right after a write (e.g.
        // applyProfile setting the profile name, then accent, then borders)
        // snapped back to the just-written old value — theme borders "not
        // changing", or reverting to a stale value. One write after all
        // changes have landed avoids that.
        watchChanges: false
        onAdapterUpdated: saveTimer.restart()

        JsonAdapter {
            id: adapter
            property bool blurEnabled: true
            property bool micIndicatorEnabled: true
            property bool cameraIndicatorEnabled: true
            property bool doNotDisturb: false
            property string idlePlayerMode: "art"
            property bool autoLowPower: true
            property bool batteryBadge: true
            property bool batteryBadgePercent: true
            property bool calcHistoryAlways: false
            property bool rainAlert: true
            property bool reduceMotion: false
            property bool nightLight: false
            property string recordResolution: "native"
            property int recordFps: 60
            property string recordQuality: "very_high"
            property bool recordSystemAudio: true
            property bool recordMic: false
            property bool recordCursor: true
            property int nightLightTemp: 4000
            property string nightLightSchedule: "sunset"
            property bool obsidianFollowTheme: true
            property string wallpaperFolder: Quickshell.env("HOME") + "/Pictures/Wallpapers"
            property string pillMode: "pill"
            property bool weatherManualLocation: false
            property string weatherCity: ""
            property string themeActiveBorder: "ff0000ff"
            property string themeInactiveBorder: "595959aa"
            property string themeAccent: "#ffffff"
            property string currentThemeProfile: "T480"
        }
    }

    Timer {
        id: saveTimer
        interval: 150
        onTriggered: settingsFile.writeAdapter()
    }

    // Applies live via hyprctl (not by editing look-and-feel.lua — that stays
    // the "on-Hyprland-restart default", this is a runtime override only).
    // Re-applied once at startup too, since a fresh `qs` launch otherwise
    // leaves whatever Hyprland's own config last set, ignoring the
    // persisted user choice until they toggle it again.
    //
    // Runs the real hyprglass plugin (github.com/hyprnux/hyprglass) now,
    // not Hyprland's built-in decoration:blur — confirmed from the plugin's
    // own README: the global toggle keyword is
    // `enabled`. Glass on the island's own layer
    // surface additionally needs an explicit namespace whitelist (layer
    // surfaces are opt-in, not covered by the global toggle alone) — see
    // the hg.layer(...) call added to look-and-feel.lua for
    // "quickshell:dynamic-island" (this surface's WlrLayershell.namespace).
    Process {
        id: blurProcess
    }

    // `hyprctl keyword` is rejected by this Lua-config Hyprland ("keyword
    // can't work with non-legacy parsers"), so this uses `eval` with the
    // plugin's own Lua config call. Command assigned imperatively (see
    // CLAUDE.md: a bound command lags one change behind).
    function applyBlur() {
        blurProcess.command = ["hyprctl", "eval",
            "if hl.plugin.hyprglass then hl.plugin.hyprglass.config({ enabled = " + (settingsStore.blurEnabled ? "true" : "false") + " }) end"]
        blurProcess.running = true
    }

    onBlurEnabledChanged: applyBlur()
    // `hyprctl reload` resets hyprglass to the config file's `enabled`
    // default — re-assert the user's choice after every reload.
    Connections {
        target: Hyprland
        function onRawEvent(event) { if (event.name === "configreloaded") settingsStore.applyBlur() }
    }
    Component.onCompleted: applyBlur()

    // JsonAdapter only writes back when a property actually changes — on a
    // fresh install nothing ever assigns to these, so the file would
    // otherwise never get created until the user flips a setting for the
    // first time. A short delay lets the initial (possibly-failing) load
    // resolve, then writes the current in-memory values (defaults, or
    // whatever the file already had) so the file always ends up existing.
    // Unconditional: if the file already existed, its values are loaded into
    // the adapter well within this delay, so this just writes them straight
    // back out (a harmless no-op rewrite); if it didn't exist, this is what
    // actually creates it with the compile-time defaults. `FileView.loaded`
    // turns out not to distinguish "loaded real data" from "load attempt
    // finished after failing" (its real getter is isLoadedOrAsync), so it
    // can't be used to gate this — confirmed by testing, not assumed.
    Timer {
        interval: 200
        running: true
        onTriggered: settingsFile.writeAdapter()
    }
}
