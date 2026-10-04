import Quickshell
import Quickshell.Io
import QtQuick

// Single entry point for matugen — generates qt6ct/GTK/spicetify color
// files (see ~/.config/matugen/config.toml's [templates.*] blocks; kitty
// is deliberately NOT one of them, see ThemeProfiles.qml's own kitty
// writer) and reports back one raw accent hex the rest of the theme
// system applies to Hyprland + this island (ThemeColorMonitor's
// setAccentColor/setActiveBorderColor/setInactiveBorderColor).
//
// Spicetify's `current_theme` is set to `Sleek` (not `marketplace`) so
// this pipeline's color.ini actually renders — confirmed live this
// coexists fine with the Marketplace extension itself (`custom_apps=
// marketplace`, independent config key, keeps working — Marketplace's
// own theme-*install* UI needs current_theme=marketplace specifically,
// but that's a separate concern from the extensions/apps it hosts, e.g.
// adblockify, which run regardless). An earlier attempt at this looked
// broken (no visible color change in Spotify at all) — root cause turned
// out to be a stale spicetify preprocess cache after a spicetify version
// bump, fixed once with `spicetify restore backup apply`, unrelated to
// Marketplace.
//
// Reads `colors.source_color` from matugen's JSON output, not
// `colors.primary` — `primary` is a Material-tonal "on-dark-surface"
// role, deliberately desaturated/pastel by the M3 spec, which is exactly
// what made an earlier kitty-theming attempt look washed-out and wrong
// (see PROGRESS.md/this session's history). `source_color` is the raw,
// unharmonized dominant color matugen actually detected (or, for `color
// hex`, just echoes the input hex back) — the punchy value this project
// actually wants as "the accent".
//
// `--source-color-index 0` is required for `image` mode: without it an
// image with multiple candidate dominant colors opens an interactive
// picker prompt on stdin, which would hang a non-interactive Process
// call. Argv-list commands throughout — the wallpaper path/seed hex never goes through a shell.
Item {
    id: matugenMonitor

    // Separate signals per trigger (not one shared `accentReady`) so
    // ThemeColorMonitor's wallpaper-driven Dynamic entry and
    // ThemeProfiles' static-preset apply don't cross-react to each
    // other's matugen runs.
    signal wallpaperAccentReady(string accent)
    signal seedAccentReady(string accent)

    function _extractAccent(text) {
        try {
            const data = JSON.parse(text)
            const accent = data.colors.source_color.default.color
            return accent || null
        } catch (e) {
            console.log("MatugenMonitor: failed to parse matugen output:", e, text)
            return null
        }
    }

    // Rapid preset switches (arrow+Enter a few times in a row) could
    // otherwise call this while a previous matugen run is still in
    // flight. A "kill the in-flight run and start a new one" approach
    // was tried first and confirmed broken live: setting
    // `running = false` does not reliably kill the process immediately,
    // so rapid preset switches left a growing backlog of stale runs that
    // each eventually finished and fired their own completion out of
    // order — a NEWER preset's accent could get silently overwritten by
    // an OLDER run finishing later. Fixed with a simple pending-value
    // queue instead: while a run is in flight, a new request only
    // updates what's pending and marks the queue dirty; the in-flight
    // run is left alone, and exactly one more run (with whatever is
    // pending *at that moment*, not necessarily every intermediate value)
    // fires right after it exits. Never more than one matugen process
    // in flight at a time, and the result always converges on the
    // latest request.
    property string _pendingSeedHex: ""
    property bool _seedDirty: false
    property bool _seedBusy: false

    property string _pendingWallpaperPath: ""
    property bool _wallpaperDirty: false
    property bool _wallpaperBusy: false
    // Preview-only runs use `--dry-run`: colors come back as JSON but no
    // template (GTK / qt6ct / spicetify) is rewritten. A pending real apply
    // is never downgraded to a dry run.
    property bool _pendingDryRun: false

    Process {
        id: fromWallpaperProc
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const accent = matugenMonitor._extractAccent(text)
                if (accent) matugenMonitor.wallpaperAccentReady(accent)
            }
        }
        onExited: {
            matugenMonitor._wallpaperBusy = false
            if (matugenMonitor._wallpaperDirty) matugenMonitor._runWallpaper()
        }
    }

    Process {
        id: fromSeedProc
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const accent = matugenMonitor._extractAccent(text)
                if (accent) matugenMonitor.seedAccentReady(accent)
            }
        }
        onExited: {
            matugenMonitor._seedBusy = false
            if (matugenMonitor._seedDirty) matugenMonitor._runSeed()
        }
    }

    function _runWallpaper() {
        matugenMonitor._wallpaperBusy = true
        matugenMonitor._wallpaperDirty = false
        const cmd = ["matugen", "image", matugenMonitor._pendingWallpaperPath,
            "--source-color-index", "0", "--mode", "dark", "--json", "hex"]
        if (matugenMonitor._pendingDryRun) cmd.push("--dry-run")
        fromWallpaperProc.command = cmd
        fromWallpaperProc.running = true
    }

    function _runSeed() {
        matugenMonitor._seedBusy = true
        matugenMonitor._seedDirty = false
        fromSeedProc.command = ["matugen", "color", "hex", matugenMonitor._pendingSeedHex,
            "--mode", "dark", "--json", "hex"]
        fromSeedProc.running = true
    }

    function applyFromWallpaper(path, dryRun) {
        if (!path) return
        matugenMonitor._pendingWallpaperPath = path
        const dry = dryRun === true
        if (matugenMonitor._wallpaperBusy) {
            matugenMonitor._pendingDryRun = matugenMonitor._wallpaperDirty ? (matugenMonitor._pendingDryRun && dry) : dry
            matugenMonitor._wallpaperDirty = true
            return
        }
        matugenMonitor._pendingDryRun = dry
        matugenMonitor._runWallpaper()
    }

    function applyFromSeedColor(hex) {
        if (!hex) return
        matugenMonitor._pendingSeedHex = hex
        if (matugenMonitor._seedBusy) { matugenMonitor._seedDirty = true; return }
        matugenMonitor._runSeed()
    }
}
