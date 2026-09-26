import Quickshell
import Quickshell.Io
import QtQuick

// Named color-theme presets for the Theme panel's carousel: T480 + a
// handful of hand-authored color-family presets, each just a name + an
// accent + kitty's 16 ANSI colors (see theme-profiles.json). "Dynamic" is
// NOT one of these — it's a synthetic carousel entry ThemePanel.qml
// inserts itself, computed live from the current wallpaper via
// applyDynamic() below.
//
// Full redesign (this session) — replaces the old save/delete/manual-hex
// profile system entirely. No more user-created profiles: only these
// preconfigured entries exist, cycled with Left/Right and applied with
// Enter, exactly like the Wallpaper panel's own grid.
Item {
    id: themeProfiles

    property var themeColorMonitor: null
    property var wallpaperMonitor: null
    property var matugenMonitor: null
    property var settingsStore: null

    readonly property var profiles: adapter.profiles

    FileView {
        id: profilesFile
        path: Quickshell.env("HOME") + "/.config/quickshell/theme-profiles.json"
        printErrors: false
        watchChanges: true
        onLoaded: themeProfiles._reconcileStaticProfile()

        JsonAdapter {
            id: adapter
            property var profiles: []
        }
    }

    // Mixes two "#rrggbb" hex colors — amount 0 returns hexA, 1 returns
    // hexB. Same formula used to hand-derive the static presets in
    // theme-profiles.json, reused here at runtime for the Dynamic entry
    // so it looks like a genuine member of the same family rather than a
    // one-off.
    function _mix(hexA, hexB, amount) {
        const a = hexA.replace("#", "")
        const b = hexB.replace("#", "")
        const clamp = (v) => Math.max(0, Math.min(255, Math.round(v)))
        let out = "#"
        for (let i = 0; i < 3; i++) {
            const ca = parseInt(a.substring(i * 2, i * 2 + 2), 16)
            const cb = parseInt(b.substring(i * 2, i * 2 + 2), 16)
            const mixed = clamp(ca + (cb - ca) * amount)
            out += mixed.toString(16).padStart(2, "0")
        }
        return out
    }

    // Builds a full {background, foreground, cursor, colors[16]} payload
    // from a single family-accent hex, following the exact recipe used to
    // hand-author the static presets (fixed near-black/grey/white slots,
    // three accent-derived slots) — see the plan's "Data model" section.
    function _kittyFromAccent(accent) {
        const mid = accent
        const dark = themeProfiles._mix(accent, "#000000", 0.5)
        const bright = themeProfiles._mix(accent, "#ffffff", 0.15)
        // Lighter near-black than the static presets' #1a1a1a/#2a2a2a —
        // explicit user request: the Dynamic entry's black swatch read as
        // blending into the terminal background at a glance.
        const colors = [
            "#262626", mid, dark, "#404040",
            "#808080", "#bfbfbf", bright, "#ffffff",
            "#363636", mid, dark, "#404040",
            "#808080", "#bfbfbf", bright, "#ffffff",
        ]
        return { background: "#0a0a0a", foreground: "#c8c8c8", cursor: bright, colors: colors }
    }

    Process {
        id: kittyWriteProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/kitty_write_theme.py",
            Quickshell.env("HOME") + "/.config/quickshell/.kitty-theme-payload.json",
            Quickshell.env("HOME") + "/.config/kitty/current-theme.conf"]
        onExited: reloadKittyProc.running = true
    }

    Process {
        id: reloadKittyProc
        command: ["sh", "-c", "pkill -SIGUSR1 -x kitty || true"]
    }

    // KDE Frameworks apps (Dolphin, etc.) read ~/.config/kdeglobals'
    // [Colors:*] sections directly via KColorScheme — confirmed live this
    // is completely independent of qt6ct's own colorscheme file, despite
    // QT_QPA_PLATFORMTHEME=qt6ct being set. kdeglobals_write_theme.py
    // patches just the color keys in place (configparser read-modify-
    // write), leaving every unrelated kdeglobals setting untouched.
    Process {
        id: kdeglobalsWriteProc
    }

    function _writeKdeglobals(background, foreground, accent) {
        kdeglobalsWriteProc.command = ["python3",
            Quickshell.env("HOME") + "/.config/quickshell/kdeglobals_write_theme.py",
            background, foreground, accent]
        if (kdeglobalsWriteProc.running) kdeglobalsWriteProc.running = false
        kdeglobalsWriteProc.running = true
    }

    // VS Code's own hand-set "[Vira*]" colorCustomizations block in
    // settings.json used one accent hex repeated across ~40 keys —
    // vscode_write_theme.py patches just that accent (preserving each
    // key's own alpha suffix, and leaving "#000000" contrast colors
    // alone). VS Code live-reloads colorCustomizations from settings.json
    // with no restart needed, unlike Spotify/Qt/GTK.
    Process {
        id: vscodeWriteProc
    }

    function _writeVSCode(accent) {
        vscodeWriteProc.command = ["python3",
            Quickshell.env("HOME") + "/.config/quickshell/vscode_write_theme.py", accent]
        if (vscodeWriteProc.running) vscodeWriteProc.running = false
        vscodeWriteProc.running = true
    }

    FileView {
        id: kittyPayloadFile
        path: Quickshell.env("HOME") + "/.config/quickshell/.kitty-theme-payload.json"
        printErrors: false

        JsonAdapter {
            id: kittyPayloadAdapter
            property string background: "#000000"
            property string foreground: "#ffffff"
            property string cursor: "#ffffff"
            property var colors: []
        }
    }

    // Writes the given {background, foreground, cursor, colors[16]}
    // payload to a temp JSON file (via FileView+JsonAdapter, this
    // project's existing safe pattern for structured data — no color hex
    // ever gets string-interpolated into a shell/QML command) then hands
    // that file to kitty_write_theme.py, which writes the real
    // current-theme.conf and triggers a live reload.
    function _writeKitty(kitty) {
        kittyPayloadAdapter.background = kitty.background
        kittyPayloadAdapter.foreground = kitty.foreground
        kittyPayloadAdapter.cursor = kitty.cursor
        kittyPayloadAdapter.colors = kitty.colors
        kittyPayloadFile.writeAdapter()
        if (kittyWriteProc.running) kittyWriteProc.running = false
        kittyWriteProc.running = true
    }

    // Applies one of the static JSON presets by name (T480, Blue, Purple,
    // Green, Red, Yellow — never "Dynamic", see applyDynamic()).
    function applyProfile(name) {
        const found = adapter.profiles.find(p => p.name === name)
        if (!found) return
        themeProfiles._writeKitty(found.kitty)
        themeProfiles._writeKdeglobals(found.kitty.background, found.kitty.foreground, found.accent)
        if (settingsStore) settingsStore.currentThemeProfile = name
        // Border + island accent straight from the profile, synchronously.
        // Previously this waited for matugen's async seedAccentReady echo,
        // which could land out of order (or from a run orphaned by a `qs`
        // restart) and persist a different theme's border — the stored
        // border ended up purple while the profile was T480 (red).
        themeProfiles._applyAccentToBorders(found.accent)
        if (matugenMonitor) matugenMonitor.applyFromSeedColor(found.accent)
    }

    // Startup reconcile: for a static profile the border/accent are fully
    // determined by the profile, so re-derive them instead of trusting
    // whatever settings.json last stored (ThemeColorMonitor re-applies the
    // stored values on every `qs` start and every `hyprctl reload`).
    function _reconcileStaticProfile() {
        if (!settingsStore || !themeColorMonitor) return
        const found = adapter.profiles.find(p => p.name === settingsStore.currentThemeProfile)
        if (!found) return
        themeColorMonitor.setAccentColor(found.accent)
        themeColorMonitor.setActiveBorderColor(found.accent.replace("#", "") + "ff")
        themeColorMonitor.setInactiveBorderColor(themeProfiles._mix(found.accent, "#595959", 0.5).replace("#", "") + "aa")
    }

    // Applies the synthetic "Dynamic" entry: re-derives everything from
    // the current wallpaper. `matugenMonitor.applyFromWallpaper` both
    // regenerates qt6ct/GTK/spicetify AND (once its Process resolves)
    // reports back the raw dominant color via onWallpaperAccentReady
    // below, which is what actually drives kitty + the border/accent —
    // this path is asynchronous, unlike applyProfile()'s static one.
    function applyDynamic() {
        if (!wallpaperMonitor || !wallpaperMonitor.currentPath || !matugenMonitor) return
        if (settingsStore) settingsStore.currentThemeProfile = "Dynamic"
        matugenMonitor.applyFromWallpaper(wallpaperMonitor.currentPath)
    }

    // Live preview swatches for the Dynamic carousel entry — refreshed
    // whenever the wallpaper changes, independent of actually applying
    // it, so ThemePanel can show an up-to-date 8-color preview while just
    // navigating (before Enter is pressed).
    property var dynamicPreviewColors: []

    function refreshDynamicPreview() {
        if (!wallpaperMonitor || !wallpaperMonitor.currentPath || !matugenMonitor) return
        // Only a real apply when Dynamic is the active theme; otherwise just
        // compute colors for the preview (`--dry-run`) — this used to
        // rewrite GTK/qt6ct/Spotify to the wallpaper's colors on every
        // wallpaper change, even with e.g. T480 active.
        const isDynamic = settingsStore && settingsStore.currentThemeProfile === "Dynamic"
        matugenMonitor.applyFromWallpaper(wallpaperMonitor.currentPath, !isDynamic)
    }

    // One shared place that pushes a known accent hex to the Hyprland
    // border + island token (+ VS Code) — used for both the static-preset
    // path (onSeedAccentReady, an echo of applyProfile's own known
    // found.accent) and the Dynamic path (onWallpaperAccentReady, the
    // value actually extracted from the wallpaper) so there's a single
    // code path for "an accent hex is now known" regardless of source.
    function _applyAccentToBorders(accent) {
        if (!themeColorMonitor) return
        themeColorMonitor.setAccentColor(accent)
        themeColorMonitor.setActiveBorderColor(accent.replace("#", "") + "ff")
        themeColorMonitor.setInactiveBorderColor(themeProfiles._mix(accent, "#595959", 0.5).replace("#", "") + "aa")
        themeProfiles._writeVSCode(accent)
    }

    Connections {
        target: matugenMonitor
        function onWallpaperAccentReady(accent) {
            const kitty = themeProfiles._kittyFromAccent(accent)
            themeProfiles.dynamicPreviewColors = kitty.colors.slice(0, 8)
            // Only actually push to kitty/border/island when Dynamic is
            // the currently-applied theme — a wallpaper change refreshing
            // the *preview* shouldn't silently repaint everything if the
            // user is currently on e.g. "Blue".
            if (settingsStore && settingsStore.currentThemeProfile === "Dynamic") {
                themeProfiles._writeKitty(kitty)
                themeProfiles._writeKdeglobals(kitty.background, kitty.foreground, accent)
                themeProfiles._applyAccentToBorders(accent)
            }
        }
        // seedAccentReady (static profiles) is intentionally ignored: the
        // border is applied synchronously in applyProfile().
    }

    Connections {
        target: wallpaperMonitor
        function onCurrentPathChanged() { themeProfiles.refreshDynamicPreview() }
    }
}
