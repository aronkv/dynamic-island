import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes

PanelWindow {
    id: island
    screen: Quickshell.screens[0]

    anchors {
        top: true
    }

    color: "transparent"
    // Reserves a small CONSTANT amount of screen space — always the idle
    // pill's own baseline size, never the notch's live size in other
    // states (mediaExpanded/overview/etc. still overlap windows exactly as
    // before). Bound to the idle pill's fixed height (island.idleHeight)
    // rather than to notch.height directly, since notch.height
    // varies across every displayState and binding to it here would make
    // the reserved zone grow every time the island expands — defeating the
    // entire point of a stable reservation. ExclusionMode.Auto was
    // considered but rejected: it computes the zone from the actual Wayland
    // surface's own size, which is a fixed 520x340 in this project's
    // architecture (only the inner notch Rectangle animates, per CLAUDE.md)
    // — Auto would reserve the full 340px height, not the visually-idle
    // ~36px. Normal + an explicit exclusiveZone is the only combination
    // that reserves just the idle size.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: island.idleHeight
    // Normally non-focusable (a status overlay shouldn't steal keyboard focus
    // from whatever the user is actually working in). Granted only while a
    // real text-entry view is open, not globally — today that's the Wi-Fi
    // password field, the Calculator's expression input, or the Settings
    // panel's manual weather-location city field. `focus: true` on an inner
    // TextInput only wins *internal* QML focus-scope arbitration; without the
    // surface itself asking Hyprland for keyboard focus here, that inner
    // focus is moot and no key events ever arrive.
    readonly property bool textEntryActive: quickOverviewPanel.wifiPasswordEntryOpen
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "calculator")
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "settings")
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "theme")
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "calendar")
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "shortcuts")
    // Wallpaper's own FocusScope already had arrow-key/Enter handling
    // wired up, but never actually received key events — this property
    // (despite its name, really "should this surface hold keyboard
    // focus", not just text entry) gates the ONLY place that asks
    // Hyprland for focus at all, so without adding it here every key
    // press was going to whatever window was focused before the panel
    // opened, not this one.
    readonly property bool wallpaperNavActive: island.overviewPanelOpen && quickOverviewPanel.activeView === "wallpaper"
    // Real bug found live (2026-09-20): a plain `focusable: true` binding
    // left the Wallpaper grid's arrow keys dead until the user clicked
    // into the panel first — `focusable`'s own setter always drives the
    // surface to WlrKeyboardFocus.OnDemand internally, which per wlr-
    // layer-shell semantics only grants real keyboard focus once the
    // compositor sees the surface *interacted with* (e.g. clicked), not
    // just mapped/visible. Fine for a password field (you'd click it
    // before typing anyway) but wrong for arrow-key grid navigation, which
    // the user expects to work the instant the panel opens.
    //
    // Tried WlrKeyboardFocus.Exclusive for this case (grants focus
    // immediately, no click needed) — reverted after explicit user
    // feedback: Exclusive keeps this surface holding ALL keyboard input
    // even after the user clicks into a completely different window (a
    // terminal, say), so their keystrokes silently went nowhere visible
    // until they closed this panel. OnDemand behaves like a normal
    // window's focus instead (click in to type, click elsewhere to hand
    // focus away cleanly) at the cost of needing that first click before
    // arrow keys respond — the same trade-off every other focusable panel
    // here already accepts.
    //
    // Also found live along the way: `focusable`'s own setter and a
    // directly-set `WlrLayershell.keyboardFocus` both write the same
    // underlying state, and fighting over it silently lost whichever
    // wrote second. Keeping only the direct WlrKeyboardFocus binding (no
    // `focusable` anywhere) avoids that regardless of which value is used.
    WlrLayershell.keyboardFocus: (island.textEntryActive || island.wallpaperNavActive || island.powerMenuOpen || island.launcherOpen || island.clipboardOpen || island.notificationsOpen || island.systemOpen)
        ? WlrKeyboardFocus.OnDemand
        : WlrKeyboardFocus.None

    // "Type-first" panels (calculator, launcher, power menu): a Hyprland
    // focus grab gives the island keyboard focus the moment they open (plain
    // OnDemand only got it after a click), and clicking anywhere outside the
    // island clears the grab → the panel closes and the clicked window gets
    // the focus (Spotlight behavior). An Exclusive→OnDemand hand-off was
    // tried first: Hyprland drops the layer's focus on that switch.
    readonly property bool typeFirstPanelOpen: island.launcherOpen || island.powerMenuOpen || island.clipboardOpen || island.notificationsOpen || island.systemOpen
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "calculator")
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "calendar")
        || (island.overviewPanelOpen && quickOverviewPanel.activeView === "shortcuts")
    HyprlandFocusGrab {
        id: focusGrab
        windows: [island]
        active: island.typeFirstPanelOpen
        onCleared: if (island.typeFirstPanelOpen) island.closeAllPanels()
    }

    // Live accent override (Extension 39's Theme system) — threaded only
    // into the handful of DynamicIsland.qml's own inline color literals and
    // into MediaControls.qml (which already took a parameterized color for
    // its active-state icons). The default itself is now white, not red
    // (2026-09-19 minimalist redesign: every panel's decorative "#ff453a"
    // accent was replaced with monochrome white/grey — see PROGRESS.md —
    // the color literal that remains in a handful of files is reserved
    // exclusively for genuine error states now, e.g. a failed connection or
    // an invalid calculator expression, never plain UI accent).
    readonly property color accentColor: themeColorMonitor.accentColor
    // Dominant vivid color of the current album cover (ArtColor.qml), used
    // by the cava visualizers; the theme accent when nothing is playing.
    readonly property color artAccent: mprisMonitor.anyPlayer && mprisMonitor.anyPlayer.trackArtUrl
        ? artColor.color : accentColor

    // Text/icon color to put ON TOP of a filled accentColor background —
    // the accent is user-configurable via the Theme system (defaults to
    // white, per the settings.json "themeAccent" default), so a hardcoded
    // white label goes invisible on it. Real bug found live: the LocalSend
    // incoming-transfer "Accept" button filled with accentColor and had a
    // hardcoded white "Accept" label, so with the (default) white accent
    // the button rendered with no visible text at all. Standard luminance
    // formula picks black or white, whichever actually contrasts.
    readonly property color accentContrastColor: {
        const c = island.accentColor
        const luminance = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
        return luminance > 0.5 ? "#000000" : "#ffffff"
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:dynamic-island"

    // Declared early (before any property bindings reference them by id) so a
    // live QML reload can't evaluate those bindings before these ids exist —
    // that ordering gap has caused a real "X is not defined" reload error.
    MprisMonitor {
        id: mprisMonitor
    }

    MicMonitor {
        id: micMonitor
    }

    ClipboardMonitor { id: clipboardMonitor }
    CalendarStore { id: calendarStore }

    LyricsProvider {
        id: lyricsProvider
        player: mprisMonitor.anyPlayer
    }

    CameraMonitor {
        id: cameraMonitor
    }

    CapsLockMonitor {
        id: capsLockMonitor
    }

    CavaMonitor {
        id: cavaMonitor
        enabled: mprisMonitor.anyPlayer !== null && mprisMonitor.anyPlayer.isPlaying
        appKeys: mprisMonitor.appKeys(mprisMonitor.activePlayer)
    }

    ScreenshotMonitor {
        id: screenshotMonitor
    }

    // Discovery + send + receive — see LocalSendMonitor.qml's own header
    // comment for the full history across Extensions 16 and 24.
    LocalSendMonitor {
        id: localSendMonitor
    }

    // Declared before BatteryMonitor since that now takes settingsStore as
    // a property (for TLP-mode persistence) — must exist first per the
    // early-id convention (a forward reference here would evaluate before
    // settingsStore's id exists on hot-reload).
    SettingsStore {
        id: settingsStore
    }

    // Declared after settingsStore since it reads settingsStore.wallpaperFolder.
    WallpaperMonitor {
        id: wallpaperMonitor
        folder: settingsStore.wallpaperFolder
    }

    // Runs matugen for the Adaptive wallpaper mode and every theme preset
    // — no dependencies of its own, declared before the two monitors that
    // reference it by id.
    MatugenMonitor {
        id: matugenMonitor
    }

    NotificationStore {
        id: notificationStore
    }

    Binding {
        target: Theme
        property: "reduceMotion"
        value: settingsStore.reduceMotion
    }

    ArtColor {
        id: artColor
        x: 0
        y: 0
        source: mprisMonitor.anyPlayer ? mprisMonitor.anyPlayer.trackArtUrl : ""
        fallback: themeColorMonitor.accentColor
    }

    // Declared after settingsStore since it holds/applies the border+
    // accent tokens ThemeProfiles.applyProfile() drives.
    ThemeColorMonitor {
        id: themeColorMonitor
        settingsStore: settingsStore
    }

    // Declared after settingsStore/wallpaperMonitor/matugenMonitor/
    // themeColorMonitor since it reads all four for the Theme panel
    // carousel's static-preset apply and its "Dynamic" entry.
    ThemeProfiles {
        id: themeProfiles
        themeColorMonitor: themeColorMonitor
        wallpaperMonitor: wallpaperMonitor
        matugenMonitor: matugenMonitor
        settingsStore: settingsStore
    }

    BatteryMonitor {
        id: batteryMonitor
        settingsStore: settingsStore
    }

    // Session lock screen (LockScreen.qml / LockContent.qml).
    LockScreen {
        id: lockScreen
        wallpaperPath: wallpaperMonitor.currentPath
        player: mprisMonitor.anyPlayer
        batteryPercent: batteryMonitor.device ? batteryMonitor.percentage : -1
        charging: batteryMonitor.charging
    }

    // Declared after settingsStore since it reads settingsStore.weatherCity/
    // weatherManualLocation for the manual-location override.
    WeatherMonitor {
        id: weatherMonitor
        settingsStore: settingsStore
    }

    // System stats, polled only while the System panel is open.
    SystemMonitor {
        id: systemMonitor
        active: island.systemOpen
    }

    // Night Shift (hyprsunset), driven by Settings.
    NightLight {
        id: nightLight
        settingsStore: settingsStore
        weather: weatherMonitor
    }

    // Live activities: screen recording, timers (ActivityStore.qml).
    ActivityStore {
        id: activityStore
        settingsStore: settingsStore
    }

    // Rain alert: notify once when rain becomes imminent.
    Connections {
        target: weatherMonitor
        function onRainSoonChanged() {
            if (weatherMonitor.rainSoon && settingsStore.rainAlert)
                activityStore.notify("Rain soon", "Rain expected in about " + Math.max(1, weatherMonitor.rainInMinutes) + " minutes.", "weather-showers-symbolic")
        }
    }

    NetworkMonitor {
        id: networkMonitor
    }

    BluetoothMonitor {
        id: bluetoothMonitor
    }

    VolumeMonitor {
        id: volumeMonitor
    }

    MicMuteMonitor {
        id: micMuteMonitor
    }

    BrightnessMonitor {
        id: brightnessMonitor
    }

    IconCacheMonitor {}

    ScreenShareMonitor {
        id: screenShareMonitor
    }

    property var currentNotification: null
    property bool notificationActive: false
    property bool mediaExpandedRequested: false
    property bool overviewPanelOpen: false
    // Power menu (PowerMenu.qml). Opening any other panel closes it.
    property bool powerMenuOpen: false
    // App launcher (LauncherPanel.qml), same exclusivity as the power menu.
    property bool launcherOpen: false
    // Clipboard history (ClipboardPanel.qml), same exclusivity.
    property bool clipboardOpen: false
    // Notification history (NotificationsPanel.qml).
    property bool notificationsOpen: false
    // Expanded live activities (ActivityPanel.qml).
    property bool activityOpen: false
    // System monitor (SystemPanel.qml).
    property bool systemOpen: false
    // `qs ipc call weather preview <code> <day>` override for the backdrop.
    property int weatherPreviewCode: -1
    property bool weatherPreviewDay: true
    onMediaExpandedRequestedChanged: if (mediaExpandedRequested) { powerMenuOpen = false; launcherOpen = false; clipboardOpen = false; notificationsOpen = false; activityOpen = false; systemOpen = false }
    property bool volumeActive: false
    property bool brightnessActive: false
    property bool screenshotActive: false
    property bool screenshotCopyFeedback: false
    property bool capslockActive: false
    property bool micMuteActive: false
    property bool chargingActive: false
    property bool workspaceActive: false
    // Island fill: solid black by default; with Liquid Glass on, a
    // translucent dark tint so hyprglass's "island" preset (look-and-feel.lua)
    // shows through, macOS Tahoe style. Shared by notch, its ears and the
    // side badges so the whole silhouette reads as one surface.
    readonly property color surfaceColor: settingsStore.blurEnabled ? Qt.rgba(0, 0, 0, 0.25) : "#000000"
    // Width of that translucent frosted rim; the island's body inside it
    // stays solid black (see notchCore).
    readonly property real glassRim: settingsStore.blurEnabled ? 7 : 0
    // Floating badges beside the pill (charging / recording / tray / mic /
    // camera) sit idleBadgeGap below the screen's top edge so they never
    // touch it (user request), and end exactly on the pill's bottom edge
    // (pill height - gap): centering them with a gap on both sides (32 px)
    // read as too small, and hanging past the pill's bottom looked off.
    readonly property int idleBadgeGap: 3

    // The media card's final size. Its content (ambient blur, cava bars,
    // controls, lyrics) is laid out at this fixed size and clipped by notch
    // while notch morphs, instead of anchors.fill-ing the animating notch:
    // that re-laid-out every word-wrapped lyric line (the ListView keeps
    // them all, cacheBuffer 5000), re-ran glideToCurrent() and re-blurred
    // the cover and the lyrics texture on every frame of the open/close
    // animation, which is what made opening the island lag during playback.
    readonly property int mediaCardWidth: 460
    readonly property int mediaCardHeight: mprisMonitor.anyPlayer !== null ? 410 : 170
    // The idle pill's height (also the reserved exclusive zone).
    readonly property int idleHeight: 40
    readonly property int idleBadgeSize: idleHeight - idleBadgeGap
    // Set by dropping a file onto the pill (see the DropArea inside notch
    // below) — stays open (no auto-collapse timer) while the user picks a
    // device, since forcing it away before they've acted would defeat the
    // point; only auto-hides a few seconds after a send actually finishes
    // (success or error), via localSendResultTimer further down.
    property bool localSendActive: false
    property string localSendFilePath: ""
    property string localSendFileName: ""
    // A dropped web link / plain text is sent as a LocalSend text message
    // (localSendFilePath = "text:<payload>", see localsend_send.py).
    property bool localSendIsText: false
    // Pill/strip: settingsStore.pillMode is the user's manual pick, but a
    // fullscreen focused window always forces "strip" regardless (so the
    // clock doesn't sit on top of fullscreen content), reverting to the
    // manual setting once fullscreen ends. Real push-based fullscreen
    // detection via Quickshell.Hyprland's IPC module — live-verified against
    // two real fullscreen toggles which property actually tracks it:
    // Hyprland.activeToplevel.lastIpcObject.fullscreen looked promising from
    // the qmltypes alone but never updated in practice (stuck at 0 through a
    // confirmed real 0→2→0 toggle, checked via a polling probe) — Quickshell
    // apparently doesn't refresh a toplevel's lastIpcObject on a pure
    // fullscreen event. Hyprland.focusedWorkspace.hasFullscreen, by
    // contrast, tracked both real toggles correctly (false→true→false) —
    // this is the property actually used below.
    readonly property bool activeWindowFullscreen: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.hasFullscreen : false
    readonly property string pillModeEffective: activeWindowFullscreen ? "strip" : settingsStore.pillMode
    property bool stripHovered: false
    // Skip the very first activeToplevelChanged (the initial connection
    // handshake handing us whatever window already had focus at qs launch,
    // not a real focus-change action) — same "_xReady" guard pattern used
    // for volume/brightness/screenshot/capslock/micmute above.
    property bool _focusReady: false
    // Skip the very first volume/mute/brightness change: that's just the
    // backing service handing us the real starting value once it connects
    // (or the first sysfs read completing), not a user action — without
    // this guard the OSD would flash briefly on every qs launch. Same
    // reasoning for screenshots: ScreenshotMonitor's first poll reports
    // whatever screenshot already existed before qs even started, which
    // isn't a "new screenshot just taken" event.
    property bool _volumeReady: false
    property bool _brightnessReady: false
    property bool _screenshotReady: false
    property bool _capslockReady: false
    property bool _micMuteReady: false
    property bool _chargingReady: false
    property bool _workspaceReady: false
    readonly property bool mediaPlaying: mprisMonitor.activePlayer !== null
    readonly property bool hasAnyPlayer: mprisMonitor.anyPlayer !== null

    // Closes every panel the user can manually open, back to the plain idle
    // pill. Deliberately leaves notificationActive/volumeActive/
    // brightnessActive untouched — those are transient auto-shown overlays
    // with their own collapse timers, not "opened" state in the same sense.
    // SUPER+<key> for an overview sub-view: pressing it while another panel
    // is open switches straight to this view (the island stays open and
    // morphs) instead of closing everything; only the same key again closes.
    function toggleOverviewView(view) {
        if (island.overviewPanelOpen && quickOverviewPanel.activeView === view) {
            island.closeAllPanels()
            return
        }
        if (island.overviewPanelOpen) {
            quickOverviewPanel.switchTo(view)
            return
        }
        // From another panel (launcher, media card…) straight to the view:
        // no closeAllPanels() first, which passed through "idle" and made
        // the island start collapsing before growing again.
        if (island.displayState !== "idle") Theme.switching = true
        quickOverviewPanel.activeView = view
        island.overviewPanelOpen = true        // also closes the exclusive panels
        island.mediaExpandedRequested = false
    }

    // Exclusive panels (launcher, clipboard, notifications, activity,
    // system, power): same key closes, another panel switches straight
    // over — the new flag is raised before the others drop, so displayState
    // never passes through "idle" (which morphed back toward the pill and
    // then reopened: 503 → 355 → 463 px in a recording).
    readonly property var _exclusiveFlags: ["powerMenuOpen", "launcherOpen", "clipboardOpen", "notificationsOpen", "activityOpen", "systemOpen"]
    function toggleExclusive(flag) {
        if (island[flag]) { island.closeAllPanels(); return }
        if (island.displayState !== "idle") Theme.switching = true
        island[flag] = true
        for (const f of island._exclusiveFlags) if (f !== flag) island[f] = false
        island.overviewPanelOpen = false
        island.mediaExpandedRequested = false
        island.localSendActive = false
    }
    Connections {
        target: Theme
        function onSwitchingChanged() { if (Theme.switching) switchingReset.restart() }
    }
    Timer { id: switchingReset; interval: 450; onTriggered: Theme.switching = false }

    function closeAllPanels() {
        island.mediaExpandedRequested = false
        island.overviewPanelOpen = false
        island.powerMenuOpen = false
        island.launcherOpen = false
        island.clipboardOpen = false
        island.notificationsOpen = false
        island.activityOpen = false
        island.systemOpen = false
        island.localSendActive = false
    }

    // Drives the idle pill's "lyrics" now-playing mode (settingsStore.
    // idlePlayerMode === "lyrics") — same position-poll-timer pattern as the
    // media-expanded card's lyrics view, since MPRIS position isn't reactive.
    // Only synced lyrics are shown — without timing there is no "current
    // line", and plain lyrics used to dump the whole song into the pill.
    // Otherwise the pill falls back to the "title — artist" text.
    property int idleLyricsLineIndex: -1
    readonly property bool idleLyricsSynced: lyricsProvider.state === "synced"
    // What the idle pill shows for media: "none" (no player — just the
    // clock), "art" ([cover] [clock] [cava]), "title" ([cover] [title]
    // [cava]) or "lyrics" (only the current line, over cover-tinted cava
    // bars). Lyrics mode without synced lyrics falls back to "title".
    readonly property bool idleShowsCover: idleMediaMode === "art" || idleMediaMode === "title"
    readonly property string idleMediaMode: !hasAnyPlayer ? "none"
        : settingsStore.idlePlayerMode === "lyrics" ? (idleLyricsSynced ? "lyrics" : "title")
        : settingsStore.idlePlayerMode === "title" ? "title" : "art"
    readonly property string idleLyricsText: {
        if (!idleLyricsSynced) return ""
        const lines = lyricsProvider.syncedLines
        const t = idleLyricsLineIndex >= 0 && idleLyricsLineIndex < lines.length ? lines[idleLyricsLineIndex].text.trim() : ""
        return t !== "" ? t : "♪"   // before the first line / instrumental gap
    }

    Timer {
        interval: 300
        running: true
        onTriggered: island._volumeReady = true
    }

    Timer {
        interval: 300
        running: true
        onTriggered: island._brightnessReady = true
    }

    Timer {
        interval: 1200
        running: true
        onTriggered: island._screenshotReady = true
    }

    Timer {
        interval: 700
        running: true
        onTriggered: island._capslockReady = true
    }

    Timer {
        interval: 300
        running: true
        onTriggered: island._micMuteReady = true
    }

    // UPower reports its initial state shortly after startup — ignore that
    // first transition so a fresh `qs` launch on AC doesn't play the
    // "just plugged in" animation.
    Timer {
        interval: 2000
        running: true
        onTriggered: island._chargingReady = true
    }

    Timer {
        interval: 300
        running: true
        onTriggered: island._focusReady = true
    }

    // Click-away/type-elsewhere collapse: closes any manually-opened panel
    // when focus moves to a real window. This covers both requested
    // triggers at "focus-change" granularity, not true per-keystroke —
    // clicking another window changes Hyprland's active toplevel (click-to-
    // focus is this compositor's default), and typing implies focus already
    // moved there first, which this same signal already caught. A finer,
    // literal per-keystroke hook isn't exposed by Quickshell.Hyprland's IPC
    // module (confirmed: HyprlandToplevel has no raw-key signal, only
    // title/activated/workspace/monitor changes) — documented here rather
    // than silently overclaiming a level of granularity that isn't real.
    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            if (!island._focusReady) return
            if (Hyprland.activeToplevel !== null) island.closeAllPanels()
        }
    }

    Timer {
        id: volumeCollapseTimer
        interval: 1500
        onTriggered: island.volumeActive = false
    }

    Timer {
        id: brightnessCollapseTimer
        interval: 1500
        onTriggered: island.brightnessActive = false
    }

    Timer {
        id: screenshotCollapseTimer
        interval: 3500
        onTriggered: island.screenshotActive = false
    }

    Timer {
        id: capslockCollapseTimer
        interval: 1200
        onTriggered: island.capslockActive = false
    }

    Timer {
        interval: 1500
        running: true
        onTriggered: island._workspaceReady = true
    }

    Timer {
        id: workspaceCollapseTimer
        interval: 1200
        onTriggered: island.workspaceActive = false
    }

    // Workspace switch → brief WorkspaceOsd. Special workspaces (negative
    // ids, e.g. scratchpads) are ignored.
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() {
            if (!island._workspaceReady || !Hyprland.focusedWorkspace || Hyprland.focusedWorkspace.id < 1) return
            island.workspaceActive = true
            workspaceCollapseTimer.restart()
        }
    }

    Timer {
        id: chargingCollapseTimer
        interval: 3400
        onTriggered: island.chargingActive = false
    }

    // ── Low battery (LowBatteryView) ──────────────────────────────────
    // Fires once per threshold (20 → 10 → 5 → 1 %) as the level drops on
    // battery; plugging in resets it. Every level collapses by itself
    // (the Dismiss button was removed). Startup never fires: the bucket
    // the battery is already in counts as announced.
    property bool lowBatteryActive: false
    property int lowBatteryLevel: 20
    property int _lowBatteryAnnounced: 101
    readonly property var _lowBatteryThresholds: [20, 10, 5, 1]
    function _lowBatteryBucket(pct) {
        let b = 101
        for (const t of _lowBatteryThresholds) if (pct <= t) b = t
        return b
    }
    // quiet: re-show without sound / Low Power switch (pill tap, IPC test).
    function showLowBattery(level, quiet) {
        lowBatteryLevel = level
        lowBatteryActive = true
        lowBatteryCollapseTimer.restart()
        if (quiet) return
        // Auto Low Power already switches at 20 % (BatteryMonitor). Level 10
        // nudges once more in case it was turned back off since then.
        if (level === 10 && settingsStore.autoLowPower) batteryMonitor.forceLowPower()
        lowBatterySound.command = ["pw-play", "/usr/share/sounds/freedesktop/stereo/" + (level >= 10 ? "dialog-warning.oga" : "dialog-error.oga")]
        lowBatterySound.running = true
    }
    // Power Saver dims the display a little (user request): down to step 9
    // of 20 (≈ 18 % raw), gentler than the 5 % alert's "Dim Display" (step
    // 6). Leaving Power Saver restores the previous level, but only if the
    // brightness wasn't changed by hand in the meantime.
    readonly property int powerSaverBrightnessStep: 9
    property int _brightnessBeforeSaver: -1
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            const target = island.powerSaverBrightnessStep
            if (PowerProfiles.profile === PowerProfile.PowerSaver) {
                if (brightnessMonitor.stepIndex > target) {
                    island._brightnessBeforeSaver = brightnessMonitor.stepIndex
                    island.quietBrightnessStep(target - brightnessMonitor.stepIndex)
                }
            } else if (island._brightnessBeforeSaver >= 0) {
                if (brightnessMonitor.stepIndex === target)
                    island.quietBrightnessStep(island._brightnessBeforeSaver - target)
                island._brightnessBeforeSaver = -1
            }
        }
    }

    Timer {
        id: lowBatteryCollapseTimer
        interval: island.lowBatteryLevel >= 20 ? 7000 : 9000
        onTriggered: island.lowBatteryActive = false
    }
    Timer { id: lowBatteryReadyTimer; interval: 2500; running: true; onTriggered: island._lowBatteryAnnounced = batteryMonitor.onBattery ? island._lowBatteryBucket(batteryMonitor.percentage) : 101 }
    Process { id: lowBatterySound }
    Connections {
        target: batteryMonitor
        function onPercentageChanged() {
            if (lowBatteryReadyTimer.running || !batteryMonitor.onBattery) return
            const b = island._lowBatteryBucket(batteryMonitor.percentage)
            if (b < island._lowBatteryAnnounced) {
                island._lowBatteryAnnounced = b
                island.showLowBattery(b)
            }
        }
        function onPluggedInChanged() {
            if (!batteryMonitor.pluggedIn) return
            island._lowBatteryAnnounced = 101
            island.lowBatteryActive = false
        }
    }

    Timer {
        id: micMuteCollapseTimer
        interval: 1500
        onTriggered: island.micMuteActive = false
    }

    // Only fires after a send actually resolves (success or error) — while
    // sendStatus is "" (still picking a device) or "sending", this timer
    // never starts, so the picker stays open until the user acts or backs
    // out via closeAllPanels().
    Timer {
        id: localSendResultTimer
        interval: 3000
        onTriggered: island.localSendActive = false
    }

    Connections {
        target: localSendMonitor
        function onSendStatusChanged() {
            if (localSendMonitor.sendStatus === "success" || localSendMonitor.sendStatus === "error") {
                localSendResultTimer.restart()
            }
        }
    }

    Timer {
        interval: 500
        repeat: true
        triggeredOnStart: true
        running: island.displayState === "idle" && island.mediaPlaying && settingsStore.idlePlayerMode === "lyrics" && lyricsProvider.state === "synced"
        onTriggered: {
            if (mprisMonitor.anyPlayer) {
                island.idleLyricsLineIndex = lyricsProvider.currentLineIndex(mprisMonitor.anyPlayer.position)
            }
        }
    }

    Connections {
        target: volumeMonitor
        function onVolumeChanged() {
            if (!island._volumeReady) return
            island.volumeActive = true
            volumeCollapseTimer.restart()
            // Mutually exclusive with brightness's OSD — without this, a
            // volume change followed quickly by a brightness change left
            // volumeActive stuck true (its own timer still counting down
            // from the volume change), so displayState kept showing the
            // stale volume OSD instead of switching to brightness.
            island.brightnessActive = false
            brightnessCollapseTimer.stop()
        }
        function onMutedChanged() {
            if (!island._volumeReady) return
            island.volumeActive = true
            volumeCollapseTimer.restart()
            island.brightnessActive = false
            brightnessCollapseTimer.stop()
        }
    }

    Connections {
        target: brightnessMonitor
        function onLevelChanged() { island.showBrightnessOsd() }
        // Key presses at the ends don't change the level but still show
        // the OSD (the sun just doesn't turn).
        function onStepped(direction, moved) {
            if (moved && !island._brightnessQuiet) brightnessContent.spin(direction)
            island.showBrightnessOsd()
        }
    }
    // Brightness changes the island makes on its own (Power Saver dim /
    // restore, which also happens on plugging in) don't pop the OSD: set
    // for 1.5 s around them, since the level change arrives with the
    // sysfs re-read a bit later.
    property bool _brightnessQuiet: false
    Timer { id: brightnessQuietTimer; interval: 1500; onTriggered: island._brightnessQuiet = false }
    function quietBrightnessStep(delta) {
        _brightnessQuiet = true
        brightnessQuietTimer.restart()
        brightnessMonitor.step(delta)
    }
    function showBrightnessOsd() {
        if (!island._brightnessReady || island._brightnessQuiet) return
        island.brightnessActive = true
        brightnessCollapseTimer.restart()
        island.volumeActive = false
        volumeCollapseTimer.stop()
    }

    IpcHandler {
        target: "brightness"
        function up(): void { island._brightnessKey(1) }
        function down(): void { island._brightnessKey(-1) }
        // One call per key event (the brightness keys' own repeat while
        // held); see _brightnessPress for the hold ramp.
        function press(direction: string): void { island._brightnessPress(direction === "down" ? -1 : 1) }
    }
    // Each tap is exactly one level (the old tap-streak acceleration made
    // quick tapping overshoot).
    function _brightnessKey(dir) { brightnessMonitor.step(dir) }
    // Holding the key: this laptop's brightness keys never report a held
    // key — every event is press + release within a few ms (logged), and
    // holding just repeats that: the 2nd event ~520 ms after the 1st, then
    // one every ~260 ms. So a hold is recognised by that cadence: the
    // initial-repeat gap (450–620 ms) followed by a repeat gap (230–320 ms),
    // same direction — quick manual tapping doesn't start that way. Then
    // qs ramps one level every 60 ms for as long as the repeats keep
    // coming (stops 350 ms after the last one, at either end, or after 3 s).
    property int _brightnessHoldDir: 0
    property real _brightnessLastTime: 0
    property real _brightnessPrevGap: 1e9
    function _brightnessPress(dir) {
        const now = Date.now()
        const gap = dir === _brightnessHoldDir ? now - _brightnessLastTime : 1e9
        const prevGap = _brightnessPrevGap
        _brightnessLastTime = now
        _brightnessPrevGap = gap
        _brightnessHoldDir = dir
        if (brightnessHoldRamp.running) {
            if (gap < 350) { brightnessHoldAlive.restart(); return }
            _brightnessHoldStop()
        }
        _brightnessKey(dir)
        if (gap >= 230 && gap <= 320 && prevGap >= 450 && prevGap <= 620) _brightnessStartRamp()
    }
    function _brightnessStartRamp() {
        brightnessHoldRamp.ticks = 0
        brightnessHoldRamp.start()
        brightnessHoldAlive.restart()
    }
    function _brightnessHoldStop() {
        brightnessHoldRamp.stop()
        brightnessHoldAlive.stop()
    }
    Timer {
        id: brightnessHoldAlive
        interval: 350
        onTriggered: island._brightnessHoldStop()
    }
    Timer {
        id: brightnessHoldRamp
        property int ticks: 0
        interval: 60
        repeat: true
        onTriggered: {
            const before = brightnessMonitor.stepIndex
            brightnessMonitor.step(island._brightnessHoldDir)
            if (brightnessMonitor.stepIndex === before || ++ticks > 50) island._brightnessHoldStop()
        }
    }

    Connections {
        target: screenshotMonitor
        function onLatestPathChanged() {
            if (!island._screenshotReady) return
            island.screenshotActive = true
            screenshotCollapseTimer.restart()
        }
    }

    Connections {
        target: capsLockMonitor
        function onActiveChanged() {
            if (!island._capslockReady) return
            island.capslockActive = true
            capslockCollapseTimer.restart()
        }
    }

    // Charger plugged in → brief "Charging" island + outline sweep. Keyed on
    // pluggedIn (not charging) so plugging in at 100% still gets feedback.
    Connections {
        target: batteryMonitor
        function onPluggedInChanged() {
            if (!island._chargingReady || !batteryMonitor.pluggedIn) return
            island.showChargingAnimation()
        }
    }

    function showChargingAnimation() {
        island.chargingActive = true
        chargingCollapseTimer.restart()
    }

    Connections {
        target: micMuteMonitor
        function onMutedChanged() {
            if (!island._micMuteReady) return
            island.micMuteActive = true
            micMuteCollapseTimer.restart()
        }
    }

    // overviewPanelOpen is checked before mediaExpanded (but still below the
    // transient volume/brightness/notification overlays) so the plain
    // overview panel is reachable even while music is playing. "mediaMini"
    // no longer exists as its own displayState — the old "replace the clock
    // with title/artist text whenever something plays" behavior is now just
    // conditional content inside the idle row itself (art thumbnail / title
    // / lyrics, per settingsStore.idlePlayerMode), so idle is the single
    // terminal fallback regardless of whether anything is playing.
    readonly property string displayState: {
        if (volumeActive) return "volume"
        if (brightnessActive) return "brightness"
        if (micMuteActive) return "micmute"
        if (capslockActive) return "capslock"
        if (chargingActive) return "charging"
        if (lowBatteryActive) return "lowbattery"
        if (powerMenuOpen) return "power"
        if (launcherOpen) return "launcher"
        if (clipboardOpen) return "clipboard"
        if (notificationsOpen) return "notifications"
        if (activityOpen) return "activity"
        if (systemOpen) return "system"
        if (notificationActive) return "notification"
        if (screenshotActive) return "screenshot"
        // An incoming transfer awaiting accept/reject (Extension 24) needs
        // the same top-priority treatment as an outbound send in progress —
        // both share this one displayState, branching internally on
        // whether localSendMonitor.pendingIncoming is set.
        if (localSendActive || localSendMonitor.pendingIncoming !== null) return "localsend"
        if (overviewPanelOpen) return "overview"
        // No mediaPlaying gate here on purpose: the expanded card now also
        // covers "player exists but paused" and "no player at all" (via
        // anyPlayer inside mediaExpandedContent), so requesting it must work
        // regardless of whether anything is actually playing right now.
        if (mediaExpandedRequested) return "mediaExpanded"
        return "idle"
    }

    // Only notification/media taking priority should force the overview
    // panel closed — checking the root causes (not displayState itself)
    // avoids immediately undoing the toggle the moment "overview" becomes
    // the active displayState.
    onMediaPlayingChanged: {
        if (mediaPlaying) overviewPanelOpen = false
    }
    onNotificationActiveChanged: if (notificationActive) overviewPanelOpen = false
    // Reset on "no player left at all" rather than "not currently playing" —
    // a pause should never close the expanded card, only the player actually
    // disappearing should clear a stale request so the *next* unrelated
    // playback session doesn't jump straight to expanded.
    onHasAnyPlayerChanged: if (!hasAnyPlayer) mediaExpandedRequested = false
    // Every way of closing the overview panel (clicking blank space from a
    // sub-view, the settings/overview IPC toggles, a notification or media
    // start forcing it shut) leaves quickOverviewPanel.activeView wherever
    // it last was. Without this reset, the next time the panel opens by a
    // different route (e.g. clicking the idle island after having drilled
    // into Battery and closed from there) would jump straight back into
    // that stale sub-view instead of the plain root.
    // Back to the root view only once the panel has faded out: resetting
    // on close made the root (clock, Ethernet/Bluetooth tiles) slide in over
    // the closing Wi-Fi / Bluetooth / Shortcuts view, so their text seemed
    // to vanish oddly (seen frame by frame in a recording).
    onOverviewPanelOpenChanged: {
        if (!overviewPanelOpen) overviewResetTimer.restart()
        else {
            overviewResetTimer.stop()
            powerMenuOpen = false; launcherOpen = false; clipboardOpen = false; notificationsOpen = false; activityOpen = false; systemOpen = false
        }
    }
    Timer {
        id: overviewResetTimer
        interval: 400
        onTriggered: if (!island.overviewPanelOpen) quickOverviewPanel.activeView = "overview"
    }

    // Fixed window size: the actual Wayland surface never resizes, only the
    // notch Rectangle (and the independently-positioned badges) inside it do.
    // Resizing the real surface every animation frame causes compositor-level
    // stutter and re-centering jumps.
    // Must stay wider than the widest state (+ spring overshoot): a state
    // wider than the surface gets its sides and corners cut off square.
    implicitWidth: 640
    // 460, not 340 — the real bug behind "the panel's bottom never rounds"
    // (2026-09-19): several overview sub-panels need MORE height than this
    // fixed surface had (bluetooth: 440, theme: 460, settings: 400, all
    // >340), so their bottom portion was being hard-clipped by the actual
    // Wayland surface's own rectangular edge — always square, regardless
    // of any radius set on notch — before notch's own rounded corner ever
    // got there. Raised to 620 for the Weather panel (560) plus headroom
    // for the spring morph's overshoot; raise again if a state needs more.
    implicitHeight: 620

    // Five regions: notch (the resizable pill/card), idleBadgeLeft
    // (charging, left of notch), idleBadgeRight (mic/camera, right of
    // notch), and the two anti-corner ears — each visible/clickable area
    // needs its own entry or clicks/compositing behave oddly outside
    // whatever's actually listed here.
    mask: Region {
        Region { item: notch }
        Region { item: idleBadgeLeft }
        Region { item: idleBadgeRight }
        Region { item: notchEarLeft }
        Region { item: notchEarRight }
    }

    NotificationServer {
        id: notifServer
        // Don't carry notifications over a `qs` reload — with the default
        // (true) the last tracked one was re-shown after every reload.
        keepOnReload: false

        onNotification: (n) => {
            // History (NotificationStore) keeps it tracked — the 20 newest
            // stay live so their actions can still be invoked from SUPER+N.
            notificationStore.add(n)
            island.currentNotification = n
            // Do Not Disturb still tracks the notification (available to
            // whatever reads currentNotification later) — it only suppresses
            // the visual takeover of the island itself.
            if (!settingsStore.doNotDisturb) {
                island.notificationActive = true
                collapseTimer.restart()
                pulseAnim.restart()
            }
        }
    }

    Timer {
        id: collapseTimer
        interval: 5000
        onTriggered: island.notificationActive = false
    }

    IpcHandler {
        target: "settings"
        function toggle() {
            island.toggleOverviewView("settings")
        }
    }

    // Direct-open handlers for panels that used to be reachable only via a
    // root overview row (Extension 26) — same toggle shape as "settings"
    // above: an unconditional overviewPanelOpen flip, activeView set only
    // when now open. "shortcuts" (Extension 27) follows the identical
    // pattern for the new keyboard-shortcuts help panel.
    IpcHandler {
        target: "calendar"
        function toggle(): void {
            island.toggleOverviewView("calendar")
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void {
            island.toggleExclusive("clipboardOpen")
        }
    }

    IpcHandler {
        target: "system"
        function toggle(): void {
            island.toggleExclusive("systemOpen")
        }
    }

    IpcHandler {
        target: "activity"
        function toggle(): void {
            island.toggleExclusive("activityOpen")
        }
        function record(): void { activityStore.toggleRecording() }
        // `qs ipc call activity timer 5m` — also "90s", "1h30m", "25", "1:30".
        function timer(duration: string): void {
            const secs = activityStore.parseDuration(duration)
            if (secs > 0) activityStore.startTimer(secs)
        }
        function stopwatch(): void { activityStore.startStopwatch() }
        function pomodoro(): void { activityStore.startPomodoro() }
        function stop(): void { activityStore.stopTimer() }
    }

    IpcHandler {
        target: "notifications"
        function clear(): void { notificationStore.clearAll() }
        function toggle(): void {
            island.toggleExclusive("notificationsOpen")
        }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            island.toggleExclusive("launcherOpen")
        }
    }

    IpcHandler {
        target: "power"
        function toggle(): void {
            island.toggleExclusive("powerMenuOpen")
        }
    }

    IpcHandler {
        target: "wifi"
        function toggle(): void {
            island.toggleOverviewView("wifi")
        }
        // Opens the Wi-Fi panel and toggles the password-share sheet (QR).
        function share(): void {
            quickOverviewPanel.activeView = "wifi"
            island.overviewPanelOpen = true
            island.mediaExpandedRequested = false
            quickOverviewPanel.wifiShare()
        }
    }

    IpcHandler {
        target: "battery"
        // Plays the plug-in animation without touching the charger.
        function chargeTest() { island.showChargingAnimation() }
        // Shows the low-battery alert for 20 / 10 / 5 / 1 (no profile or
        // brightness change, no sound).
        function lowTest(level: int) { island.showLowBattery(level, true) }
        function lowDismiss() { island.lowBatteryActive = false }
        function toggle() {
            island.toggleOverviewView("battery")
        }
    }

    IpcHandler {
        target: "calculator"
        function toggle() {
            island.toggleOverviewView("calculator")
        }
        // Open the calculator with an expression typed in.
        function open(expr: string) {
            quickOverviewPanel.activeView = "calculator"
            island.overviewPanelOpen = true
            island.mediaExpandedRequested = false
            quickOverviewPanel.calcSetExpression(expr)
        }
        // Open the calculator with its "what can I type" help sheet.
        function help() {
            quickOverviewPanel.activeView = "calculator"
            island.overviewPanelOpen = true
            island.mediaExpandedRequested = false
            quickOverviewPanel.calcShowHelp()
        }
    }

    IpcHandler {
        target: "tray"
        function toggle() {
            island.toggleOverviewView("tray")
        }
    }

    IpcHandler {
        target: "weather"
        function toggle() {
            island.toggleOverviewView("weather")
        }
        // Preview a weather scene: code = WMO code (-1 = live), day = true/false.
        function preview(code: int, day: bool): void {
            island.weatherPreviewCode = code
            island.weatherPreviewDay = day
            island.closeAllPanels()
            if (code >= 0) { quickOverviewPanel.activeView = "weather"; island.overviewPanelOpen = true }
        }
    }

    IpcHandler {
        target: "theme"
        // `qs ipc call theme apply Blue` — "Dynamic" or any preset name.
        function apply(name: string): void {
            if (name === "Dynamic") themeProfiles.applyDynamic()
            else themeProfiles.applyProfile(name)
        }
        function toggle() {
            island.toggleOverviewView("theme")
        }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle() {
            island.toggleOverviewView("wallpaper")
        }
    }

    IpcHandler {
        target: "shortcuts"
        function toggle() {
            island.toggleOverviewView("shortcuts")
        }
    }


    IpcHandler {
        target: "overview"
        // Bare-SUPER: closes whatever's currently open (media card or
        // overview/any sub-view) back to idle in one press. When opening
        // fresh, a live/paused player takes over the summon entirely (no
        // separate "media" trigger anymore — SUPER+M was removed since it
        // was a redundant second way to reach the exact same card) so the
        // now-playing card appears immediately instead of the plain root;
        // the root is still reachable via the media card's own close (X).
        // Open a specific overview sub-view ("wifi", "bluetooth", …).
        function open(view: string): void {
            island.closeAllPanels()
            quickOverviewPanel.activeView = view
            island.overviewPanelOpen = true
        }
        function toggle() {
            if (island.mediaExpandedRequested || island.overviewPanelOpen) {
                island.closeAllPanels()
            } else if (mprisMonitor.anyPlayer !== null) {
                island.mediaExpandedRequested = true
            } else {
                quickOverviewPanel.activeView = "overview"
                island.overviewPanelOpen = true
            }
        }
    }

    SequentialAnimation {
        id: pulseAnim
        NumberAnimation { target: notch; property: "scale"; to: 1.06; duration: 90; easing.type: Easing.OutQuad }
        NumberAnimation { target: notch; property: "scale"; to: 1.0; duration: 120; easing.type: Easing.InQuad }
    }

    // ClippingRectangle, not plain Rectangle — a plain Rectangle's rounded
    // corners never render in this environment (Qt 6.11.2/OpenGL) either;
    // ClippingRectangle is required for content to actually clip to the
    // rounded shape.
    //
    // The per-corner radii below looked completely broken for a while
    // (2026-09-19) — every combination, and even a large uniform radius,
    // rendered as a flat 90° bottom corner. The real cause turned out to
    // be unrelated to radius at all: the actual Wayland surface (this
    // PanelWindow's implicitHeight, see above) was fixed at 340px while
    // this state needs 440-460px, so the bottom of the rounded shape was
    // being hard-clipped by the surface's own square edge before it ever
    // got there. Fixed by growing implicitHeight instead — per-corner
    // radii work fine now that the surface is actually tall enough.
    ClippingRectangle {
        id: notch
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter

        color: island.surfaceColor
        Behavior on color { ColorAnimation { duration: 300 } }
        topLeftRadius: 0
        topRightRadius: 0
        // The collapsed strip is only 10 px tall, so its corners take half
        // its height (fully round ends) instead of the pill's 18 px.
        readonly property real cornerRadius: Math.min(18, height / 2)
        bottomLeftRadius: cornerRadius
        bottomRightRadius: cornerRadius

        // Solid black body with a soft glass edge. With Liquid Glass on,
        // `notch` itself is only a translucent frosted fill
        // (island.surfaceColor); on top of it, stacked rings inset step by
        // step darken it toward the solid black core — a gradient from the
        // frosted rim into black instead of a hard line. With glass off
        // glassRim is 0 and everything collapses into plain black.
        Repeater {
            model: 4
            Rectangle {
                required property int index
                readonly property real inset: island.glassRim * index / 4
                z: -1
                anchors.fill: parent
                anchors.leftMargin: inset
                anchors.rightMargin: inset
                anchors.bottomMargin: inset
                color: Qt.rgba(0, 0, 0, island.glassRim > 0 ? 0.3 : 1)
                topLeftRadius: 0
                topRightRadius: 0
                bottomLeftRadius: Math.max(0, notch.bottomLeftRadius - inset)
                bottomRightRadius: Math.max(0, notch.bottomRightRadius - inset)
                visible: island.glassRim > 0 || index === 0
            }
        }
        Rectangle {
            id: notchCore
            z: -1
            anchors.fill: parent
            anchors.leftMargin: island.glassRim
            anchors.rightMargin: island.glassRim
            anchors.bottomMargin: island.glassRim
            color: "#000000"
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Math.max(0, notch.bottomLeftRadius - island.glassRim)
            bottomRightRadius: Math.max(0, notch.bottomRightRadius - island.glassRim)
        }

        // Spring-animated size (animW/animH carry the Behaviors below). When
        // collapsing into an OSD the size never goes under the OSD's own
        // size: the spring's undershoot made the notch's bottom edge slide
        // over the slider for a few frames.
        property real animW: targetWidth
        property real animH: targetHeight
        property real _floorW: 0
        property real _floorH: 0
        width: Math.max(animW, _floorW)
        height: Math.max(animH, _floorH)
        Connections {
            target: island
            function onDisplayStateChanged() {
                notch.idleArrived = false
                notch._floorW = notch.osdMorph && notch.width > notch.targetWidth ? notch.targetWidth : 0
                notch._floorH = notch.osdMorph && notch.height > notch.targetHeight ? notch.targetHeight : 0
            }
        }
        // True once the spring morph has (nearly) arrived — idle content
        // waits for this so it never appears inside a still-shrinking card.
        readonly property bool settled: Math.abs(width - targetWidth) < 90 && Math.abs(height - targetHeight) < 30
        // Latches once idle has settled and stays true until the state
        // changes, so idle→idle width changes (the pill springing to fit
        // each lyric line) don't hide and re-fade the whole idle row.
        property bool idleArrived: false
        // The strip ↔ pill switch (fullscreen on/off, hovering the strip)
        // stays in displayState "idle", so it must reset the latch too —
        // otherwise the clock and cover showed, cut off, while the notch
        // was still growing from the 10 px strip (seen frame by frame).
        readonly property bool stripCollapsed: island.pillModeEffective === "strip" && !island.stripHovered
        onStripCollapsedChanged: idleArrived = false
        onSettledChanged: if (settled && island.displayState === "idle") idleArrived = true
        Component.onCompleted: {
            idleArrived = settled && island.displayState === "idle"
            morphState = island.displayState
        }
        // The plain idle pill's width ([cover] [clock] [cava]), used for
        // the workspace dots whatever the now-playing mode shows.
        readonly property real plainPillWidth: artSlot.implicitWidth * 2 + idleClock.implicitWidth + clockRow.spacing * 2 + 36
        // The state the notch's size follows. Opening a heavy panel from the
        // pill lags displayState by ~3 frames: the panel's content is created
        // on the first frame (a ~100 ms hitch), and with the morph already
        // running the animation clock jumped ahead — the first visible frame
        // showed the panel two-thirds open (seen in a recording). Starting
        // the morph after that frame makes it grow smoothly from the pill.
        // Light states (OSDs, banners, collapsing) follow immediately.
        // Plain value, set only by _setMorph — NOT bound to displayState: a
        // live binding made it follow displayState instantly, so the start
        // delay and the open/close/switch timings silently never applied.
        property string morphState: "idle"
        readonly property var _heavyStates: ["overview", "mediaExpanded", "launcher", "clipboard", "notifications", "activity", "system", "power", "localsend"]
        readonly property var _osdStates: ["volume", "brightness", "capslock", "micmute"]
        // What kind of morph is about to run: "open" (pill → panel),
        // "close" (→ pill), "switch" (panel → another panel or sub-view),
        // "osd", or "idle" (pill ↔ pill, e.g. a lyric line's width). Set
        // imperatively *before* morphState changes, so both axes' Behaviors
        // read the same, current value when they start — a binding could
        // still hold its old value then, and the height once ran on the
        // open timing while the width used the close timing (a tall narrow
        // box lingering on close, seen in a recording).
        property string morphKind: "idle"
        function _kindFor(from, to) {
            if (_osdStates.indexOf(to) !== -1 || _osdStates.indexOf(from) !== -1) return "osd"
            if (to === "idle") return from === "idle" ? "idle" : "close"
            if (from === "idle") return "open"
            return "switch"
        }
        function _setMorph(st) {
            notch.morphKind = notch._kindFor(notch.morphState, st)
            notch.morphState = st
        }
        Connections {
            target: island
            // Coalesced: one user action can flip several flags in a row;
            // only the final state of the tick should drive the morph.
            function onDisplayStateChanged() { Qt.callLater(notch._onStateChanged) }
        }
        function _onStateChanged() {
            const st = island.displayState
            if (st === notch.morphState && !morphDelay.running) return
            if (notch._heavyStates.indexOf(st) !== -1 && notch.morphState === "idle" && !Theme.reduceMotion) {
                morphDelay.restart()
            } else {
                morphDelay.stop()
                notch._setMorph(st)
            }
        }
        // A sub-view change inside the open overview (Settings → Battery)
        // only changes the target size, not the state.
        Connections {
            target: quickOverviewPanel
            function onActiveViewChanged() { if (notch.morphState === "overview") notch.morphKind = "switch" }
        }
        Timer {
            id: morphDelay
            interval: 33
            onTriggered: notch._setMorph(island.displayState)
        }
        readonly property real targetWidth: widthFor(notch.morphState)
        function widthFor(state) {
            switch (state) {
                case "notification": return 380
                case "mediaExpanded": return island.mediaCardWidth
                case "overview":
                    // Bluetooth's device grid needs real room — DynamicGlacier's
                    // own reference implementation ships this exact width (500)
                    // for the same 2-column device-tile grid; every other
                    // sub-view keeps the original 300 for now.
                    if (quickOverviewPanel.activeView === "bluetooth") return 500
                    // Wifi now shares Bluetooth's 2-column card grid (see
                    // WifiPanel.qml) per explicit user request — same width
                    // for the same reason.
                    if (quickOverviewPanel.activeView === "wifi") return 500
                    if (quickOverviewPanel.activeView === "shortcuts") return 560
                    // Extension 39: color swatches + hex fields + mode
                    // toggle + profile list need more room than a plain
                    // theme-name list did.
                    if (quickOverviewPanel.activeView === "theme") return 440
                    // Wider tiles, explicit user request — matches
                    // Bluetooth/Wifi's own 500.
                    if (quickOverviewPanel.activeView === "wallpaper") return 500
                    if (quickOverviewPanel.activeView === "weather") return 420
                    if (quickOverviewPanel.activeView === "battery") return 470
                    if (quickOverviewPanel.activeView === "calculator") return 560
                    if (quickOverviewPanel.activeView === "calendar") return 580
                    if (quickOverviewPanel.activeView === "settings") return 620
                    if (quickOverviewPanel.activeView === "tray") return 400
                    return 340
                case "volume": return 300
                case "brightness": return 300
                case "charging": return 240
                case "lowbattery": return 260
                case "power": return 520
                case "launcher": return 540
                case "notifications": return 460
                case "activity": return 460
                case "system": return 500
                case "clipboard": return 560
                case "screenshot": return 220
                case "localsend": return localSendMonitor.pendingIncoming !== null ? 360 : 280
                default:
                    // A workspace switch shows the dots at the plain pill's
                    // size ([cover] [clock] [cava]) whatever the now-playing
                    // mode — a long lyric line or title used to stretch the
                    // dots across a wide pill, a short one squeezed them.
                    if (island.workspaceActive)
                        return notch.plainPillWidth
                    // The collapsed strip has the plain pill's fixed width,
                    // independent of what now-playing shows — following a
                    // lyric line it resized on every line. Hovering it
                    // reveals the real pill at its content width.
                    if (island.pillModeEffective === "strip" && !island.stripHovered)
                        return notch.plainPillWidth
                    return idleRow.implicitWidth + 36
            }
        }
        readonly property real targetHeight: heightFor(notch.morphState)
        function heightFor(state) {
            switch (state) {
                // 300 (original, header-less) + ~36 for the header row and
                // its spacing (24px row + 12px spacing) — the wifi/bluetooth
                // status row that briefly lived here as a separate row was
                // folded into the header itself, so it no longer adds its
                // own ~32px on top.
                // Empty state (no player at all) only ever shows the header
                // + the cover/placeholder row — no controls, no lyrics — so
                // it gets its own, much shorter height instead of leaving a
                // large dead black area below the content (confirmed via the
                // same live debug-measurement technique used to fix this
                // row's vertical position: measured content height ~117 +
                // margins ~32, rounded up for comfortable padding).
                case "mediaExpanded": return island.mediaCardHeight
                case "overview":
                    // Grown from 280 to fit the right-click expanded detail
                    // section (Security/Band/Channel/Frequency/Speed/BSSID)
                    // added to each network card without immediately
                    // forcing a scroll for the common one-expanded-card case
                    // — the list still scrolls for anything beyond that.
                    // Grown from 340 (2026-09-20): the right-click detail
                    // view now shows up to 13 rows (Technology/Security/IP
                    // address/Subnet mask/Router/Proxy/IP settings/Privacy/
                    // Band/Channel/Frequency/Max speed/BSSID) plus the
                    // Disconnect/Forget row for the connected network's own
                    // card — 340 cut off the buttons entirely with no
                    // visible scroll affordance. The list still scrolls for
                    // anything beyond this.
                    if (quickOverviewPanel.activeView === "wifi") return 422
                    // Matched to Wifi's height per explicit user request —
                    // both share the same 2-column device-card grid width
                    // (500), so keeping their heights equal too makes them
                    // feel like one consistent panel size, not two
                    // arbitrarily-different ones.
                    if (quickOverviewPanel.activeView === "bluetooth") return 422
                    if (quickOverviewPanel.activeView === "battery") return 385
                    if (quickOverviewPanel.activeView === "settings") return 520
                    if (quickOverviewPanel.activeView === "calculator") return Math.max(quickOverviewPanel.calcHistoryVisible ? 300 : 0, Math.ceil(quickOverviewPanel.calcNaturalHeight) + 28)
                    if (quickOverviewPanel.activeView === "weather") return 522
                    if (quickOverviewPanel.activeView === "calendar") return 400
                    // Shrunk from 460 (2026-09-20): that height was sized for
                    // the old manual-hex-fields + GTK-theme-list + profiles-
                    // list design. The carousel replacing it is just a
                    // header + one row of cards — explicit user request to
                    // bring the height down to match.
                    if (quickOverviewPanel.activeView === "theme") return 372
                    if (quickOverviewPanel.activeView === "wallpaper") return 262
                    if (quickOverviewPanel.activeView === "shortcuts") return 470
                    if (quickOverviewPanel.activeView === "tray") return Math.ceil(quickOverviewPanel.trayNaturalHeight) + 28
                    // Plain root: header row (~18) + spacing (8) + clock/
                    // date + wifi/bluetooth summary row (~43) + panel
                    // margins (36, widened for a more modern, less cramped
                    // look per explicit user request — see
                    // QuickOverviewPanel.qml's root ColumnLayout margins) ≈
                    // 105 of real content, plus comfortable padding; +10 for
                    // the two connectivity rows with round icons.
                    return 155
                case "notification": return island.currentNotification && String(island.currentNotification.body || "").trim() !== "" ? 86 : 66
                case "volume": return 64
                case "brightness": return 64
                case "charging": return island.idleHeight
                case "lowbattery": return island.idleHeight
                case "power": return 196
                case "launcher": return 470
                case "system": return 620
                case "activity": return activityStore.timerActive ? (activityStore.recording ? 190 : 150) : (activityStore.recording ? 190 : 150)
                case "notifications": return notificationStore.items.length === 0 ? 200 : Math.min(560, 90 + notificationStore.items.length * 84)
                case "clipboard": return 480
                case "screenshot": return 150
                case "localsend": return localSendMonitor.pendingIncoming !== null ? 172 : 190
                default:
                    if (island.pillModeEffective === "strip" && !island.stripHovered) return 10
                    // Bumped from 36, explicit user request.
                    return island.idleHeight
            }
        }

        // Spring, not a fixed-duration ease: the iPhone island's signature
        // slightly-elastic morph between states.
        // Reduce motion: a stiff, critically damped spring = quick, no overshoot.
        // OSDs (volume, brightness, Caps Lock, mic) morph in with a stiffer,
        // better-damped spring: collapsing e.g. the media card into the
        // volume pill with the regular spring left a big empty black box
        // shrinking for ~130 ms.
        readonly property bool osdMorph: island.displayState === "volume" || island.displayState === "brightness"
            || island.displayState === "capslock" || island.displayState === "micmute"
        // Timed ease-out instead of a spring. An underdamped spring
        // overshot and pulled back (a "jump" at the end of every open); a
        // critically damped one either crept into place slowly or, made
        // stiff enough to end quickly, burst from the pill to a 410 px card
        // in ~80 ms. A fixed-duration OutCubic grows at a readable pace and
        // ends exactly on time, never past the target. Collapsing into the
        // pill is quicker than opening (user request); OSDs are short.
        // Opening 300 ms OutQuad (OutCubic covered most of the distance in
        // the first frames and panels seemed to pop out); closing into the
        // pill 280 ms OutCubic; switching between panels 320 ms InOutCubic,
        // so the frame glides from one size to the other.
        readonly property int morphDuration: Theme.reduceMotion ? 120
            : morphKind === "open" ? 300 : morphKind === "switch" ? 320 : morphKind === "osd" ? 200 : 280
        readonly property int morphEasing: morphKind === "open" ? Easing.OutQuad
            : morphKind === "switch" ? Easing.InOutCubic : Easing.OutCubic
        Behavior on animW { NumberAnimation { duration: notch.morphDuration; easing.type: notch.morphEasing } }
        Behavior on animH { NumberAnimation { duration: notch.morphDuration; easing.type: notch.morphEasing } }

        // Purely hover-tracking, not a click-consuming MouseArea — a
        // HoverHandler never intercepts press/click events, so it can sit
        // over notch without affecting expandToggle/overviewToggle/DropArea
        // beneath. Only meaningful during idle+strip mode, but harmless to
        // track unconditionally.
        HoverHandler {
            onHoveredChanged: island.stripHovered = hovered
        }

        // Strip mode: a thin black bar (as wide as the island) replacing the whole idle pill (clock,
        // badges, cava, everything) while collapsed. Hovering it (the
        // HoverHandler above) reveals the full pill for as long as the
        // cursor stays over it; idleRow/idleBadgeLeft/idleBadgeRight below
        // all fade out in this same collapsed state via their own opacity
        // bindings, so nothing overlaps this bar.
        Item {
            anchors.fill: parent
            opacity: (island.displayState === "idle" && island.pillModeEffective === "strip" && !island.stripHovered) ? 1 : 0
            visible: opacity > 0

            FadeBehavior on opacity {}

            // Nothing drawn on top: the strip is just the black notch itself,
            // island-wide and a few px tall.
        }

        MouseArea {
            id: expandToggle
            anchors.fill: parent
            z: 0
            enabled: island.hasAnyPlayer && island.displayState !== "notification" && island.displayState !== "volume" && island.displayState !== "brightness" && island.displayState !== "overview"
            onClicked: island.mediaExpandedRequested = !island.mediaExpandedRequested
        }

        // expandToggle wins whenever a player exists at all — playing or
        // paused (clicking the idle pill should open the media card even for
        // a paused track, matching the reference project's own
        // hasActiveMedia()-driven behavior); overviewToggle only claims idle
        // clicks when there's truly no player. Both also exclude every
        // non-idle displayState, so exactly one of the two is ever enabled
        // at once.
        MouseArea {
            id: overviewToggle
            anchors.fill: parent
            z: 0
            enabled: (island.displayState === "idle" && !island.hasAnyPlayer) || island.displayState === "overview"
            onClicked: island.overviewPanelOpen = !island.overviewPanelOpen
        }

        // Drop a file anywhere on the pill to send it via LocalSend — always
        // enabled regardless of current displayState (matches how a
        // notification can already interrupt whatever's showing; dropping a
        // file is just as deliberate a user action).
        //
        // `keys` (QQuickDropArea's own filter property) only matches a QML
        // Drag.keys tag set by an in-app drag SOURCE — it does nothing for a
        // real external/OS file drag, which carries no such tag. The actual
        // format check for "is this really a file" is `drag.hasUrls` on the
        // entered/dropped QQuickDragEvent (confirmed via the real Qt6
        // qmltypes: QQuickDragEvent has hasUrls/hasText/hasHtml/hasColor,
        // QQuickDropArea has no separate MIME filter). Rejecting non-file
        // drags in onEntered stops containsDrag (and therefore the "Drop
        // here" swap below) from ever going true for a text/link/image drag.
        DropArea {
            id: fileDropArea
            anchors.fill: parent
            onEntered: (drag) => { if (!drag.hasUrls && !drag.hasText) drag.accepted = false }
            onDropped: (drop) => {
                const first = drop.urls.length > 0 ? drop.urls[0].toString() : ""
                if (first.startsWith("file://")) {
                    const path = decodeURIComponent(first.substring(7))
                    island.localSendIsText = false
                    island.localSendFilePath = path
                    island.localSendFileName = path.substring(path.lastIndexOf("/") + 1)
                } else {
                    // A link dragged from the browser (or any plain text):
                    // send it as a message, not as a "file" named after the
                    // URL's last segment (e.g. "watch?v=…"), which failed.
                    const text = (first !== "" ? first : (drop.text || "")).trim()
                    if (text === "") return
                    island.localSendIsText = true
                    island.localSendFilePath = "text:" + text
                    island.localSendFileName = text
                }
                localSendMonitor.sendStatus = ""
                localSendMonitor.sendErrorMessage = ""
                island.localSendActive = true
            }
        }

        // "Drop here" now swaps in at the clock's own position instead of
        // tinting the whole pill — see idleRow's opacity condition below
        // (gains "&& !fileDropArea.containsDrag") and this Text's matching
        // anchor formula. The old whole-notch translucent overlay used to
        // render UNDER idleRow (declared before it in source order), so
        // idleRow's own opaque clock/art content painted straight over the
        // "Drop here" label instead of being replaced by it — a real visual
        // collision, not just a cosmetic preference.
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 18 - height / 2
            text: "Drop here"
            color: "#ffffff"
            font.pixelSize: 13
            font.weight: 600
            font.family: "SF Pro Display"
            opacity: (island.displayState === "idle" && fileDropArea.containsDrag) ? 1 : 0
            visible: opacity > 0

            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }

        // Lyrics mode background: the full 20-band cava spread across the
        // pill behind the line, in the cover's colour. Inset by the pill's
        // corner radius so no bar pokes out of the rounded ends; x comes
        // from a fraction of the (springing) notch width — no anchors.fill
        // on per-bar random values. No height Behavior (see barsArea).
        Item {
            id: lyricsCava
            x: island.idleHeight / 2
            y: 0
            width: notch.width - island.idleHeight
            height: island.idleHeight
            opacity: island.displayState === "idle" && island.idleMediaMode === "lyrics" && cavaMonitor.enabled
                && !island.workspaceActive && !(island.pillModeEffective === "strip" && !island.stripHovered)
                && (notch.settled || notch.idleArrived) ? 1 : 0
            visible: opacity > 0
            FadeBehavior on opacity {}

            // Fixed bar size (4 px every 7 px) across the whole pill: a
            // short line shows fewer bars, a long one more, but every bar
            // looks the same. The 20 bands are stretched over however many
            // bars fit, so the spectrum always spans the full width.
            readonly property int count: Math.max(0, Math.floor((width + 3) / 7))
            readonly property real barsX: (width - count * 7 + 3) / 2
            Repeater {
                model: lyricsCava.count
                Rectangle {
                    required property int index
                    x: lyricsCava.barsX + index * 7
                    width: 4
                    // Interpolated between neighbouring bands, so a wide
                    // pill shows a smooth spectrum, not blocky pairs.
                    readonly property real t: index * (cavaMonitor.barCount - 1) / Math.max(1, lyricsCava.count - 1)
                    readonly property real level: {
                        const b = cavaMonitor.bars, i = Math.floor(t), f = t - i
                        return (b[i] || 0) * (1 - f) + (b[Math.min(i + 1, cavaMonitor.barCount - 1)] || 0) * f
                    }
                    height: Math.max(2, level * lyricsCava.height * 0.8)
                    y: lyricsCava.height - height
                    radius: 2
                    color: Qt.rgba(island.artAccent.r, island.artAccent.g, island.artAccent.b, 0.35)
                }
            }
        }

        RowLayout {
            id: idleRow
            // Pinned to a fixed point within the idle-height band, not centered
            // in the live (currently animating) parent height —
            // anchors.centerIn tracked the growing box as it resized for
            // "overview"/other states, dragging the still-fading-out row
            // visibly downward with it.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 18 - height / 2
            spacing: 8
            opacity: (island.displayState === "idle" && (notch.settled || notch.idleArrived) && !island.workspaceActive && !(island.pillModeEffective === "strip" && !island.stripHovered) && !fileDropArea.containsDrag) ? 1 : 0
            scale: island.displayState === "idle" ? 1 : 0.8
            visible: opacity > 0

            // Scale and fade together, over the same duration as the notch's
            // own resize, so content visibly shrinks/grows with the box
            // instead of popping or fading in place while the box resizes.
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}

            // Center: the clock, plus — whenever a player exists at all
            // (hasAnyPlayer — a paused track still counts, matching how
            // clicking the idle pill also now opens the media card for a
            // paused track, not just an actively-playing one) — the art
            // thumbnail, per settingsStore.idlePlayerMode. No automatic
            // title/artist swap by default; that's now an opt-in mode
            // instead of the always-on behavior the old standalone
            // "mediaMini" state had.
            //
            // The art slot (left) and its mirror spacer (right) are always
            // present at a fixed size — only the slot's *inner* content
            // (Rectangle+Image) toggles visibility, not the Item itself.
            // Toggling the outer Item's own visible used to let it collapse
            // to zero width whenever art mode had nothing to show, which
            // resized the whole pill and visibly shifted the clock sideways
            // the moment a paused Spotify track appeared — reserving the
            // same fixed width unconditionally on both sides keeps the
            // clock's position and the pill's width constant regardless of
            // whether a cover is actually showing.
            RowLayout {
                id: clockRow
                spacing: 12

                // Live activity (timer / rain) — click expands. Recording and
                // low battery have their own badges outside the pill.
                LiveActivityChip {
                    store: activityStore
                    weather: weatherMonitor
                    rainEnabled: settingsStore.rainAlert
                    accent: island.accentColor
                    onOpenRequested: { island.closeAllPanels(); island.activityOpen = true }
                }

                Item {
                    id: artSlot
                    visible: island.idleMediaMode !== "lyrics"
                    implicitWidth: 28
                    implicitHeight: 28

                    Rectangle {
                        id: artPlaceholder
                        anchors.fill: parent
                        radius: 8
                        color: "#1a1a1a"
                        visible: island.idleShowsCover
                    }

                    // Rounded via the same recolor-pattern shape already used
                    // for icons elsewhere in this project (an invisible
                    // source feeding a MultiEffect), just using
                    // maskEnabled/maskSource for alpha-masking instead of
                    // colorization — a plain Image has square corners
                    // regardless of a rounded Rectangle placed behind it,
                    // since it isn't clipped to that shape on its own.
                    Image {
                        id: artImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                        source: (island.idleShowsCover && mprisMonitor.anyPlayer)
                            ? mprisMonitor.anyPlayer.trackArtUrl : ""
                    }

                    Rectangle {
                        id: artMask
                        anchors.fill: parent
                        radius: 8
                        visible: false
                        layer.enabled: true
                    }

                    MultiEffect {
                        anchors.fill: artImage
                        source: artImage
                        maskEnabled: true
                        maskSource: artMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.0
                        maskThresholdMax: 1.0
                        maskSpreadAtMax: 0.0
                        visible: island.idleShowsCover
                    }

                    // No cover (e.g. a browser tab without the Plasma
                    // integration extension's player), or a cover file that
                    // is already gone (that extension deletes its /tmp
                    // artwork on track change / tab close while the player
                    // still advertises it): the app's own icon instead of an
                    // empty grey square.
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 20
                        visible: island.idleShowsCover
                            && (!mprisMonitor.anyPlayer.trackArtUrl || artImage.status === Image.Error)
                        source: {
                            const p = mprisMonitor.anyPlayer
                            if (!p) return ""
                            const e = DesktopEntries.heuristicLookup(p.desktopEntry || p.identity)
                            return Quickshell.iconPath(e ? e.icon : "", "audio-x-generic")
                        }
                    }
                }

                Clock {
                    id: idleClock
                    visible: island.idleMediaMode === "none" || island.idleMediaMode === "art"
                }

                // Title mode: the track takes the clock's place, centred
                // between the cover and the cava bars.
                Text {
                    visible: island.idleMediaMode === "title"
                    text: {
                        const p = mprisMonitor.anyPlayer
                        if (!p) return ""
                        return p.trackArtist ? (p.trackTitle + " — " + p.trackArtist) : p.trackTitle
                    }
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.weight: 600
                    font.family: "SF Pro Display"
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.maximumWidth: 240
                }

                // Right-side mirror of the art slot above — same fixed
                // reserved size (not the old separate 44px circular badge)
                // so the pill's width stays constant whether or not cava is
                // actually drawing anything, matching the art slot's own
                // "always reserve, only fill conditionally" anti-jank
                // pattern. Moved in from the old idleBadgeRight/cavaBadge
                // (a separate floating circle) into the pill itself, per
                // explicit user request — mic/camera badges stay in
                // idleBadgeRight, only the bars moved.
                Item {
                    visible: island.idleMediaMode !== "lyrics"
                    implicitWidth: artSlot.implicitWidth
                    implicitHeight: artSlot.implicitHeight

                    Item {
                        id: barsArea
                        anchors.centerIn: parent
                        width: cavaMonitor.pillCount * 5 - 2
                        height: 20
                        opacity: cavaMonitor.enabled ? 1 : 0
                        visible: opacity > 0

                        FadeBehavior on opacity {}

                        Repeater {
                            model: cavaMonitor.pillCount

                            Rectangle {
                                required property int index
                                width: 3
                                radius: 1
                                height: Math.max(3, (cavaMonitor.pillBars[index] !== undefined ? cavaMonitor.pillBars[index] : 0) * barsArea.height)
                                x: index * 5
                                y: barsArea.height - height
                                // Album-cover color while playing (theme
                                // accent otherwise).
                                color: island.artAccent

                                // No height Behavior: cava already smooths
                                // (noise_reduction), and an 80 ms animation
                                // per 30 Hz update kept the island
                                // repainting at 60 fps for the whole song —
                                // every frame recomposited by Hyprland,
                                // which is what made opening it stutter.
                                Behavior on color { ColorAnimation { duration: 220 } }
                            }
                        }
                    }
                }

                // Current synced line. The pill's width follows idleRow's
                // implicitWidth (notch.targetWidth), so it springs to fit
                // each line up to maxW; a longer line scrolls once (after a
                // short pause) so its end is readable, then holds.
                Item {
                    id: lyricsBox
                    visible: island.idleMediaMode === "lyrics"
                    readonly property real maxW: 380
                    readonly property real overflow: Math.max(0, lyricLine.implicitWidth - maxW)
                    implicitWidth: Math.min(lyricLine.implicitWidth, maxW)
                    implicitHeight: lyricLine.implicitHeight
                    Layout.preferredWidth: implicitWidth
                    clip: true

                    Text {
                        id: lyricLine
                        text: island.idleLyricsText
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.weight: 600
                        font.family: "SF Pro Display"
                        onTextChanged: {
                            marquee.stop()
                            x = 0
                            if (!Theme.reduceMotion) lineIn.restart()
                            if (lyricsBox.overflow > 0 && lyricsBox.visible) marquee.restart()
                        }
                    }
                    NumberAnimation { id: lineIn; target: lyricLine; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                    SequentialAnimation {
                        id: marquee
                        PauseAnimation { duration: 900 }
                        NumberAnimation {
                            target: lyricLine
                            property: "x"
                            to: -lyricsBox.overflow
                            duration: Math.max(600, lyricsBox.overflow * 22)
                            easing.type: Easing.InOutSine
                        }
                    }
                }
            }
        }

        // Notification banner (iOS-style): the sending app's icon top-left,
        // title + "now", up to two lines of body, and a real picture (album
        // art, screenshot…) as a thumbnail on the right when it has one.
        Item {
            id: notifContent
            anchors.fill: parent
            opacity: island.displayState === "notification" ? 1 : 0
            scale: island.displayState === "notification" ? 1 : 0.8
            visible: opacity > 0

            FadeBehavior on opacity {}
            ScaleBehavior on scale {}

            readonly property var n: island.currentNotification
            readonly property string appIcon: n ? notificationStore.appIconFor(n.appName, n.desktopEntry) : ""
            // A real picture (image hint / image file) → thumbnail on the right;
            // a theme icon → used as the lead icon when the app has none.
            readonly property string picture: n ? notificationStore.pictureFor(n) : ""
            readonly property string _content: n ? notificationStore._iconFor(n) : ""
            readonly property string contentIcon: _content !== picture ? _content : ""
            readonly property string leadIcon: appIcon !== "" ? appIcon : contentIcon

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                anchors.topMargin: 12
                anchors.bottomMargin: 12
                spacing: 12

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 38
                    implicitHeight: 38
                    IconImage {
                        anchors.fill: parent
                        visible: notifContent.leadIcon !== ""
                        source: notifContent.leadIcon
                        asynchronous: true
                        mipmap: true
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: notifContent.leadIcon === ""
                        radius: 10
                        color: Theme.cardElevated
                        Text {
                            anchors.centerIn: parent
                            text: notifContent.n && notifContent.n.appName ? notifContent.n.appName.charAt(0).toUpperCase() : "•"
                            color: "#ffffff"
                            font.pixelSize: 17
                            font.weight: 700
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: notifContent.n ? (notifContent.n.summary || notifContent.n.appName) : ""
                            color: "#ffffff"
                            font.pixelSize: 14
                            font.weight: 600
                            font.family: "SF Pro Display"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "now"
                            color: "#ffffff"
                            opacity: 0.4
                            font.pixelSize: 11
                            font.family: "SF Pro Text"
                        }
                    }
                    Text {
                        visible: text !== ""
                        text: notifContent.n ? String(notifContent.n.body || "").replace(/<[^>]*>/g, "") : ""
                        color: "#ffffff"
                        opacity: 0.75
                        font.pixelSize: 12
                        font.family: "SF Pro Text"
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                ClippingRectangle {
                    visible: notifContent.picture !== ""
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 44
                    implicitHeight: 44
                    radius: 9
                    color: Theme.cardElevated
                    Image {
                        anchors.fill: parent
                        source: notifContent.picture
                        sourceSize.width: 88
                        sourceSize.height: 88
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }
            }
        }

        // Brief preview after SUPER+SHIFT+A captures+saves a screenshot —
        // ScreenshotMonitor.latestPath only updates the transient thumbnail
        // shown here, the actual capture/annotate/save pipeline lives
        // entirely in the Hyprland keybind, not in this QML. The keybind
        // itself now also copies straight to the clipboard on save (see
        // keybindings.lua), but a click here re-copies the same file — a
        // fallback for a screenshot taken before that existed, or just a
        // quick way to get it back on the clipboard without retaking it.
        Item {
            anchors.fill: parent
            anchors.margins: 10
            opacity: island.displayState === "screenshot" ? 1 : 0
            scale: island.displayState === "screenshot" ? 1 : 0.8
            visible: opacity > 0

            FadeBehavior on opacity {}
            ScaleBehavior on scale {}

            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "#1a1a1a"
                clip: true

                // The new file is often picked up while the screenshot tool is
                // still writing it ("Unable to read image data") → retry a
                // few times instead of showing an empty preview.
                Image {
                    id: shotPreview
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    cache: false
                    asynchronous: true
                    readonly property string path: screenshotMonitor.latestPath.length > 0 ? "file://" + screenshotMonitor.latestPath : ""
                    property int tries: 0
                    source: path
                    onPathChanged: tries = 0
                    onStatusChanged: if (status === Image.Error && tries < 6) shotRetry.restart()
                    Timer {
                        id: shotRetry
                        interval: 250
                        onTriggered: { shotPreview.tries++; shotPreview.source = ""; shotPreview.source = shotPreview.path }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "#000000"
                    opacity: island.screenshotCopyFeedback ? 0.55 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "Copied to clipboard"
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.weight: 600
                    font.family: "SF Pro Display"
                    opacity: island.screenshotCopyFeedback ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: screenshotMonitor.latestPath.length > 0
                    onClicked: {
                        screenshotCopyProc.command = ["sh", "-c", "wl-copy -t image/png < \"$1\"", "sh", screenshotMonitor.latestPath]
                        screenshotCopyProc.running = true
                        island.screenshotCopyFeedback = true
                        screenshotCopyFeedbackTimer.restart()
                        screenshotCollapseTimer.restart()
                    }
                }
            }
        }

        Process {
            id: screenshotCopyProc
        }

        Timer {
            id: screenshotCopyFeedbackTimer
            interval: 900
            onTriggered: island.screenshotCopyFeedback = false
        }

        // Device picker + send status, shown after dropping a file on the
        // pill (see the DropArea above). Real protocol send flow lives in
        // LocalSendMonitor.sendFile() / localsend_send.py — this is purely
        // the picker UI + status text. Shares the "localsend" displayState
        // with the incoming accept/reject prompt below (Extension 24) —
        // only one of the two is ever visible, keyed on whether
        // localSendMonitor.pendingIncoming is currently set.
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 6
            opacity: island.displayState === "localsend" ? 1 : 0
            scale: island.displayState === "localsend" ? 1 : 0.8
            visible: opacity > 0

            FadeBehavior on opacity {}
            ScaleBehavior on scale {}

            // Outbound: dropped a file on the pill, pick which discovered
            // device to send it to.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: localSendMonitor.pendingIncoming === null

                Text {
                    visible: island.localSendIsText
                    text: /^https?:\/\//i.test(island.localSendFileName)
                        ? "Link · " + island.localSendFileName.replace(/^https?:\/\/(www\.)?/i, "").split("/")[0]
                        : "Text"
                    color: "#ffffff"
                    opacity: 0.5
                    font.pixelSize: 10
                    font.weight: 600
                    font.family: "SF Pro Display"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    text: island.localSendFileName
                    color: "#ffffff"
                    font.pixelSize: 12
                    font.weight: 600
                    font.family: "SF Pro Display"
                    elide: island.localSendIsText ? Text.ElideMiddle : Text.ElideRight
                    Layout.fillWidth: true
                }

                Text {
                    visible: localSendMonitor.sendStatus === ""
                    text: localSendMonitor.devices.length > 0 ? "Send to:" : "No devices found nearby"
                    color: "#ffffff"
                    opacity: 0.6
                    font.pixelSize: 11
                    font.family: "SF Pro Display"
                }

                Repeater {
                    model: localSendMonitor.sendStatus === "" ? localSendMonitor.devices : []

                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: 6
                        color: "#1a1a1a"

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: parent.modelData.alias
                            color: "#ffffff"
                            font.pixelSize: 11
                            font.family: "SF Pro Display"
                            elide: Text.ElideRight
                            width: parent.width - 16
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: localSendMonitor.sendFile(parent.modelData, island.localSendFilePath)
                        }
                    }
                }

                Text {
                    visible: localSendMonitor.sendStatus === "sending"
                    text: "Sending…"
                    color: "#ffffff"
                    opacity: 0.7
                    font.pixelSize: 12
                    font.family: "SF Pro Display"
                }

                Text {
                    visible: localSendMonitor.sendStatus === "success"
                    text: "Sent"
                    color: "#32d74b"
                    font.pixelSize: 12
                    font.weight: 600
                    font.family: "SF Pro Display"
                }

                Text {
                    visible: localSendMonitor.sendStatus === "error"
                    text: "Failed: " + localSendMonitor.sendErrorMessage
                    color: island.accentColor
                    font.pixelSize: 11
                    font.family: "SF Pro Display"
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            // Inbound: another LocalSend device wants to push a file to us.
            // No silent auto-accept, per explicit user decision — this is
            // the only way an incoming transfer ever completes.
            // AirDrop-style card: sender avatar + name, the file(s) with a
            // type icon and size, then Decline / Accept pills.
            ColumnLayout {
                id: incomingCard
                Layout.fillWidth: true
                spacing: 10
                visible: localSendMonitor.pendingIncoming !== null

                readonly property var req: localSendMonitor.pendingIncoming
                readonly property var files: req ? req.files : []
                readonly property real totalSize: files.reduce((a, f) => a + (f.size || 0), 0)
                function fmtSize(b) {
                    const u = ["B", "KB", "MB", "GB"]
                    let i = 0
                    while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
                    return (i === 0 || b >= 100 ? Math.round(b) : b.toFixed(1)) + " " + u[i]
                }
                function mimeIcon(name) {
                    const ext = (String(name).match(/\.([^.]+)$/) || ["", ""])[1].toLowerCase()
                    if (/^(png|jpe?g|webp|gif|bmp|svg|heic|avif)$/.test(ext)) return "image-x-generic"
                    if (/^(mp3|flac|ogg|opus|m4a|wav|aac)$/.test(ext)) return "audio-x-generic"
                    if (/^(mp4|mkv|webm|mov|avi|m4v)$/.test(ext)) return "video-x-generic"
                    if (ext === "pdf") return "application-pdf"
                    if (/^(zip|tar|gz|xz|zst|7z|rar)$/.test(ext)) return "package-x-generic"
                    if (/^(docx?|odt|rtf|pptx?|xlsx?)$/.test(ext)) return "x-office-document"
                    return "text-x-generic"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    // Sender avatar: device glyph in a circle.
                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 21
                        color: Theme.cardElevated
                        IconImage {
                            id: lsDeviceIcon
                            anchors.centerIn: parent
                            implicitSize: 20
                            source: "image://icon/" + (incomingCard.req && incomingCard.req.deviceType === "mobile" ? "phone-symbolic" : "computer-symbolic")
                            visible: false
                            layer.enabled: true
                        }
                        Rectangle { id: lsDeviceFill; anchors.fill: lsDeviceIcon; color: "#ffffff"; visible: false }
                        MultiEffect {
                            anchors.fill: lsDeviceIcon
                            source: lsDeviceFill
                            maskEnabled: true
                            maskSource: lsDeviceIcon
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 0.0
                            maskThresholdMax: 1.0
                            maskSpreadAtMax: 0.0
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: incomingCard.req ? incomingCard.req.alias : ""
                            color: "#ffffff"
                            font.pixelSize: 15
                            font.weight: 700
                            font.family: "SF Pro Display"
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: "wants to share " + (incomingCard.files.length === 1 ? "a file" : incomingCard.files.length + " files")
                            color: "#ffffff"
                            opacity: 0.5
                            font.pixelSize: 11
                            font.family: "SF Pro Text"
                        }
                    }
                }

                // File card.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: 12
                    color: Theme.card
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 12
                        spacing: 10
                        IconImage {
                            implicitSize: 26
                            source: incomingCard.files.length > 0
                                ? Quickshell.iconPath(incomingCard.files.length === 1 ? incomingCard.mimeIcon(incomingCard.files[0].fileName) : "folder", "text-x-generic")
                                : ""
                            asynchronous: true
                            mipmap: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: incomingCard.files.length === 1 ? incomingCard.files[0].fileName
                                : incomingCard.files.length + " files · " + incomingCard.files.map(f => f.fileName).join(", ")
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.weight: 600
                            font.family: "SF Pro Text"
                            elide: Text.ElideMiddle
                        }
                        Text {
                            text: incomingCard.fmtSize(incomingCard.totalSize)
                            color: "#ffffff"
                            opacity: 0.45
                            font.pixelSize: 11
                            font.family: "SF Pro Text"
                            font.features: { "tnum": 1 }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 17
                        color: declineMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)
                        scale: declineMouse.pressed ? 0.97 : 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 110 } }
                        Text {
                            anchors.centerIn: parent
                            text: "Decline"
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.weight: 600
                            font.family: "SF Pro Text"
                        }
                        MouseArea {
                            id: declineMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: localSendMonitor.rejectIncoming()
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 34
                        radius: 17
                        color: acceptMouse.containsMouse ? "#e6e6e6" : "#ffffff"
                        scale: acceptMouse.pressed ? 0.97 : 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on scale { NumberAnimation { duration: 110 } }
                        Text {
                            anchors.centerIn: parent
                            text: "Accept"
                            color: "#000000"
                            font.pixelSize: 13
                            font.weight: 700
                            font.family: "SF Pro Text"
                        }
                        MouseArea {
                            id: acceptMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: localSendMonitor.acceptIncoming()
                        }
                    }
                }
            }
        }

        // Volume / brightness / Caps Lock / mic mute — one shared OSD, same
        // size for all four (see OsdPill.qml).
        // Laid out at its final size (the notch's target size while shown,
        // frozen afterwards) and pinned to the top center: with
        // anchors.fill it stretched to e.g. the media card's size and
        // shrank along with the morph — a giant slider for the first frames.
        // The morphing notch just clips it.
        component IslandOsd: OsdPill {
            id: islandOsd
            anchors.horizontalCenter: parent.horizontalCenter
            // Centered while the notch is taller than the OSD (collapsing
            // from the media card), settling onto the top edge as it shrinks.
            y: Math.max(0, (notch.height - height) / 2)
            property real fixedW: 300
            property real fixedH: 64
            // Captured once per appearance (after the state change settles),
            // never while hiding: a live `Binding … when: shown` picked up the
            // *next* state's size for one frame on the way out (the slider
            // visibly jumped smaller before fading).
            // growIn: appearing from something smaller than the OSD (the idle
            // pill) → scale with the notch. From something bigger (the media
            // card) it stays at full size — scaling with the notch there made
            // the slider shrink and pop back on the spring's undershoot.
            property bool growIn: true
            onShownChanged: if (shown) {
                growIn = notch.height < 64
                Qt.callLater(() => { islandOsd.fixedW = notch.targetWidth; islandOsd.fixedH = notch.targetHeight })
            }
            width: fixedW
            height: fixedH
            opacity: shown ? 1 : 0
            // Grows/shrinks with the morphing notch instead of its own scale
            // animation, so it always fits inside it: no half-clipped slider
            // while the notch is still narrower than the OSD.
            scale: growIn ? Math.max(0.5, Math.min(1, notch.width / Math.max(1, fixedW), notch.height / Math.max(1, fixedH))) : 1
            transformOrigin: Item.Top          // the notch grows down from the top edge
            visible: opacity > 0
            FadeBehavior on opacity {}
        }

        IslandOsd {
            id: volumeContent
            kind: "volume"
            shown: island.displayState === "volume"
            level: volumeMonitor.volume
            muted: volumeMonitor.muted
        }

        IslandOsd {
            id: brightnessContent
            kind: "brightness"
            shown: island.displayState === "brightness"
            level: brightnessMonitor.level
        }

        IslandOsd {
            id: capslockContent
            kind: "capslock"
            shown: island.displayState === "capslock"
            on: capsLockMonitor.active
        }

        IslandOsd {
            id: micMuteContent
            kind: "mic"
            shown: island.displayState === "micmute"
            on: micMuteMonitor.muted
        }

        // Low battery alert — see LowBatteryView.qml.
        LowBatteryView {
            id: lowBatteryContent
            anchors.fill: parent
            battery: batteryMonitor
            level: island.lowBatteryLevel
            shown: island.displayState === "lowbattery"
            lowPowerOn: PowerProfiles.profile === PowerProfile.PowerSaver
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.8
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        // Charger connected — see ChargingView.qml.
        ChargingView {
            id: chargingContent
            anchors.fill: parent
            battery: batteryMonitor
            shown: island.displayState === "charging"
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.8
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        // Apple Music style ambient background: the album art, heavily
        // blurred and dimmed, filling the whole card behind its content.
        Item {
            id: mediaAmbient
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: island.mediaCardWidth
            // Follows the notch while its spring overshoots past the card
            // height, so no black strip shows under the art.
            height: Math.max(island.mediaCardHeight, notch.height)
            // The blur must stay inside the card: with MultiEffect's auto
            // padding the blurred cover spilled ~blurMax px below it, and
            // while the notch's spring overshot past the card height that
            // spill showed as a bright band under the dark gradient.
            clip: true
            opacity: island.displayState === "mediaExpanded" && mprisMonitor.anyPlayer !== null
                && ambientArt.status === Image.Ready ? 1 : 0
            visible: opacity > 0
            FadeBehavior on opacity {}

            Image {
                id: ambientArt
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                source: mprisMonitor.anyPlayer ? mprisMonitor.anyPlayer.trackArtUrl : ""
                sourceSize.width: 128
                sourceSize.height: 128
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: ambientArt
                blurEnabled: true
                blur: 1.0
                blurMax: 64
                autoPaddingEnabled: false
                saturation: 0.3
                opacity: 0.55
            }

            // Darken toward the bottom so lyrics/controls stay readable.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.25) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.7) }
                }
            }
        }

        // Background cava visualizer across the top of the media card, in the
        // album cover's color, hanging from the top edge behind the content.
        Item {
            id: mediaViz
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: island.mediaCardWidth
            height: 110
            opacity: island.displayState === "mediaExpanded" && mprisMonitor.anyPlayer !== null ? 1 : 0
            visible: opacity > 0
            FadeBehavior on opacity {}

            readonly property real gap: 4
            readonly property real barW: (width - 24 - gap * (cavaMonitor.barCount - 1)) / cavaMonitor.barCount

            Repeater {
                model: cavaMonitor.barCount
                Rectangle {
                    required property int index
                    x: 12 + index * (mediaViz.barW + mediaViz.gap)
                    y: 0
                    width: mediaViz.barW
                    height: Math.max(4, (cavaMonitor.bars[index] || 0) * mediaViz.height)
                    radius: Math.min(4, width / 2)
                    topLeftRadius: 0
                    topRightRadius: 0
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(island.artAccent.r, island.artAccent.g, island.artAccent.b, 0.55) }
                        GradientStop { position: 1.0; color: Qt.rgba(island.artAccent.r, island.artAccent.g, island.artAccent.b, 0.08) }
                    }
                    // No height Behavior — see the pill bars above.
                }
            }
        }

        ColumnLayout {
            id: mediaExpandedContent
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            width: island.mediaCardWidth - 32
            height: island.mediaCardHeight - 32
            spacing: 12
            z: 1
            opacity: island.displayState === "mediaExpanded" ? 1 : 0
            scale: island.displayState === "mediaExpanded" ? 1 : 0.8
            visible: opacity > 0

            FadeBehavior on opacity {}
            ScaleBehavior on scale {}

            IslandHeaderRow {
                Layout.fillWidth: true
                batteryMonitor: batteryMonitor
                settingsStore: settingsStore
                networkMonitor: networkMonitor
                bluetoothMonitor: bluetoothMonitor
                // Clock moved down into the title row (next to the track
                // title, matching the reference layout) instead of sitting
                // up here.
                showClock: false
                // Navigating away from the media card while it's showing:
                // leave mediaExpanded and let the overview panel take over
                // at the requested sub-view. Coming back to the media card
                // afterward goes through QuickOverviewPanel.backToNowPlaying
                // (see quickOverviewPanel's onBackToNowPlaying below) rather
                // than remembered per-path round-tripping.
                onNavigate: (target) => {
                    island.mediaExpandedRequested = false
                    quickOverviewPanel.activeView = target
                    island.overviewPanelOpen = true
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item {
                    Layout.preferredWidth: 72
                    Layout.preferredHeight: 72
                    Layout.alignment: Qt.AlignTop
                    // Slight "breathing": the cover is a touch smaller while
                    // paused, like Apple Music.
                    scale: mprisMonitor.anyPlayer && mprisMonitor.anyPlayer.isPlaying ? 1 : 0.9
                    Behavior on scale { SpringAnimation { spring: 3; damping: 0.28; epsilon: 0.002 } }

                    // Explicit dark-grey placeholder behind the art, not just
                    // the notch's own black background showing through an
                    // empty source — reads as a real "empty slot", not as
                    // nothing having rendered at all. Real art (once loaded)
                    // fully covers it, no state-tracking needed.
                    Rectangle {
                        id: mediaArtBase
                        anchors.fill: parent
                        radius: 14
                        color: "#1a1a1a"
                        // Stays visible (it's the placeholder art shows on
                        // top of) AND needs layer.enabled so MultiEffect's
                        // maskSource below has a rendered texture to sample
                        // — without this the mask has nothing to read and
                        // the art composites to nothing (confirmed real
                        // regression from the 84x84->54x54 resize, which
                        // dropped this line).
                        layer.enabled: true
                    }

                    Image {
                        id: mediaArtImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        source: mprisMonitor.anyPlayer ? mprisMonitor.anyPlayer.trackArtUrl : ""
                        visible: false
                        layer.enabled: true
                    }

                    // Rounded-square mask (radius 18, matching the reference)
                    // via the same MultiEffect maskSource technique used for
                    // icon recoloring elsewhere — more general than a
                    // dedicated clip widget since it also works for the
                    // plain-color placeholder underneath.
                    MultiEffect {
                        anchors.fill: mediaArtImage
                        source: mediaArtImage
                        maskEnabled: true
                        maskSource: mediaArtBase
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.0
                        maskThresholdMax: 1.0
                        maskSpreadAtMax: 0.0
                    }

                    // No cover / cover file already deleted: the app's icon
                    // on the placeholder (same fallback as the idle pill).
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 30
                        visible: mprisMonitor.anyPlayer !== null
                            && (!mprisMonitor.anyPlayer.trackArtUrl || mediaArtImage.status === Image.Error)
                        source: {
                            const p = mprisMonitor.anyPlayer
                            if (!p) return ""
                            const e = DesktopEntries.heuristicLookup(p.desktopEntry || p.identity)
                            return Quickshell.iconPath(e ? e.icon : "", "audio-x-generic")
                        }
                    }
                }

                // Single always-present title column: the top row (title +
                // clock + close) renders regardless of player state so the
                // close button stays reachable even with nothing playing;
                // artist/album are the only parts that toggle per-state.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: mprisMonitor.anyPlayer ? mprisMonitor.anyPlayer.trackTitle : "Nothing playing"
                            color: "#ffffff"
                            opacity: mprisMonitor.anyPlayer !== null ? 1 : 0.4
                            font.pixelSize: 17
                            font.weight: 700
                            font.family: "SF Pro Display"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Clock {
                            font.pixelSize: 15
                            font.weight: 700
                            font.family: "SF Pro Display"
                            font.letterSpacing: 0
                        }

                        // Close: returns to the plain overview root, not a
                        // full closeAllPanels() — a third, shallower exit
                        // distinct from "‹ Back" (root-or-nowplaying) and
                        // the full idle collapse.
                        Item {
                            implicitWidth: 28
                            implicitHeight: 28

                            IconImage {
                                id: mediaCloseIcon
                                anchors.fill: parent
                                anchors.margins: 6
                                source: "image://icon/window-close-symbolic"
                                visible: false
                                layer.enabled: true
                                smooth: true
                                mipmap: true
                            }

                            Rectangle {
                                id: mediaCloseFill
                                anchors.fill: mediaCloseIcon
                                color: "#ffffff"
                                visible: false
                            }

                            MultiEffect {
                                anchors.fill: mediaCloseIcon
                                source: mediaCloseFill
                                maskEnabled: true
                                maskSource: mediaCloseIcon
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 0.0
                                maskThresholdMax: 1.0
                                maskSpreadAtMax: 0.0
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    island.mediaExpandedRequested = false
                                    quickOverviewPanel.activeView = "overview"
                                    island.overviewPanelOpen = true
                                }
                            }
                        }
                    }

                    Text {
                        text: mprisMonitor.anyPlayer ? mprisMonitor.anyPlayer.trackArtist : ""
                        color: "#ffffff"
                        opacity: 0.7
                        font.pixelSize: 14
                        font.weight: 500
                        font.family: "SF Pro Display"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        visible: mprisMonitor.anyPlayer !== null
                    }

                    Text {
                        text: mprisMonitor.anyPlayer ? mprisMonitor.anyPlayer.trackAlbum : ""
                        color: "#ffffff"
                        opacity: 0.4
                        font.pixelSize: 12
                        font.family: "SF Pro Display"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        visible: mprisMonitor.anyPlayer !== null
                    }
                }
            }

            MediaControls {
                Layout.fillWidth: true
                player: mprisMonitor.anyPlayer
                visible: mprisMonitor.anyPlayer !== null
                accentColor: island.artAccent
            }

            // Empirically confirmed (via temporary debug logging against the
            // real running instance): when there's no player, MediaControls
            // and the lyrics Item below correctly collapse to zero height
            // once hidden — but that leaves *zero* fillHeight children in
            // this ColumnLayout, and with none, QtQuick.Layouts centers the
            // remaining (non-fillHeight) content as a group in the leftover
            // space instead of packing it to the top. This spacer becomes
            // the layout's only fillHeight child exactly in that situation,
            // so header+row stay pinned to the top like they are when a
            // player exists (where the lyrics Item itself plays this role).
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: mprisMonitor.anyPlayer === null
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: mprisMonitor.anyPlayer !== null

                // Synced lyrics have no timing without live position updates
                // (MPRIS doesn't push those continuously), so poll while the
                // panel is actually open and there's something synced to show.
                Timer {
                    interval: 500
                    running: island.displayState === "mediaExpanded" && lyricsProvider.state === "synced" && mprisMonitor.anyPlayer !== null
                    repeat: true
                    triggeredOnStart: true
                    onTriggered: {
                        // lyricsView glides to the new line itself (see its
                        // onCurrentIndexChanged).
                        if (mprisMonitor.anyPlayer)
                            lyricsView.currentIndex = lyricsProvider.currentLineIndex(mprisMonitor.anyPlayer.position)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: lyricsProvider.state === "notFound" || lyricsProvider.state === "loading"
                    text: lyricsProvider.state === "loading" ? "Loading lyrics…" : "No lyrics found"
                    color: "#ffffff"
                    opacity: 0.4
                    font.pixelSize: 12
                    font.family: "SF Pro Display"
                }

                Flickable {
                    anchors.fill: parent
                    visible: lyricsProvider.state === "plain"
                    contentWidth: width
                    contentHeight: plainLyricsText.implicitHeight
                    clip: true

                    Text {
                        id: plainLyricsText
                        width: parent.width
                        text: lyricsProvider.plainLyrics
                        color: "#ffffff"
                        opacity: 0.6
                        font.pixelSize: 12
                        font.family: "SF Pro Display"
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Apple Music style: every line bold and large, the current
                // one full white, past lines faint, upcoming dimmed; the
                // view keeps the current line in the upper third and glides
                // to it. Top/bottom edges fade out via a gradient mask.
                ListView {
                    id: lyricsView
                    anchors.fill: parent
                    clip: true
                    visible: lyricsProvider.state === "synced"
                    model: lyricsProvider.syncedLines
                    spacing: 10
                    interactive: true
                    cacheBuffer: 5000
                    highlightFollowsCurrentItem: false
                    // Spacers so the first/last lines can also sit at the
                    // 30% "sharp" band — without them the opening lines were
                    // stuck inside the blurred top edge.
                    header: Item { width: lyricsView.width; height: lyricsView.height * 0.3 }
                    footer: Item { width: lyricsView.width; height: lyricsView.height * 0.6 }

                    // Explicit eased scroll so the current line sits at ~30%
                    // of the view height (the highlight-range modes didn't
                    // follow reliably with a 0-size highlight).
                    NumberAnimation {
                        id: lyricsScroll
                        target: lyricsView
                        property: "contentY"
                        duration: 600
                        easing.type: Easing.OutCubic
                    }
                    // While the panel opens (and right after a track
                    // change) the view jumps straight to the current line
                    // instead of scrolling there from wherever it was left;
                    // only line-to-line moves while open are animated.
                    property bool snapping: true
                    readonly property bool panelOpen: island.displayState === "mediaExpanded"
                    onPanelOpenChanged: if (panelOpen) snapFor.restart(); else snapping = true
                    Timer {
                        id: snapFor
                        interval: 900
                        onTriggered: lyricsView.snapping = false
                    }
                    function glideToCurrent() {
                        let target = originY
                        // Before the first line: rest at the top, which (with
                        // the header spacer) puts line 0 in the sharp band.
                        if (currentIndex >= 0) {
                            const item = itemAtIndex(currentIndex)
                            if (!item) return
                            const maxY = Math.max(originY, originY + contentHeight - height)
                            target = Math.max(originY, Math.min(maxY, item.y - height * 0.3))
                        }
                        if (snapping) {
                            lyricsScroll.stop()
                            contentY = target
                            return
                        }
                        if (Math.abs(target - contentY) < 1) return
                        lyricsScroll.to = target
                        lyricsScroll.restart()
                    }
                    onCurrentIndexChanged: glideToCurrent()
                    onModelChanged: resetForTrack()
                    onCountChanged: resetForTrack()
                    function resetForTrack() {
                        snapping = true
                        currentIndex = -1
                        contentY = originY
                        if (panelOpen) snapFor.restart()
                    }
                    onHeightChanged: glideToCurrent()

                    delegate: Text {
                        required property var modelData
                        required property int index
                        readonly property int distance: index - lyricsView.currentIndex
                        width: lyricsView.width
                        text: modelData.text
                        color: "#ffffff"
                        opacity: distance === 0 ? 1 : distance < 0 ? 0.22 : Math.max(0.18, 0.5 - (distance - 1) * 0.1)
                        font.pixelSize: 16
                        font.weight: 700
                        font.family: "SF Pro Display"
                        wrapMode: Text.WordWrap
                        horizontalAlignment: Text.AlignLeft
                        // Only opacity animates (never font size — see CLAUDE.md).
                        Behavior on opacity { enabled: !lyricsView.snapping; NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
                    }
                }

                // Soft edges: the list renders into a texture (its own
                // drawing hidden, input still live), shown twice — sharp in
                // the middle, blurred toward the top/bottom where the two
                // masks cross-fade — so lines scrolling out get defocused
                // instead of cut off at the box edge.
                ShaderEffectSource {
                    id: lyricsTexture
                    anchors.fill: lyricsView
                    sourceItem: lyricsView
                    hideSource: true
                    visible: false
                    live: true
                }

                MultiEffect {
                    anchors.fill: lyricsView
                    visible: lyricsView.visible
                    source: lyricsTexture
                    maskEnabled: true
                    maskSource: lyricsSharpMask
                    // 0.5 + spread 1.0 = smoothstep(0, 1, maskAlpha): a true
                    // soft ramp. (0.0 + 1.0 made every alpha fully visible.)
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                MultiEffect {
                    anchors.fill: lyricsView
                    visible: lyricsView.visible
                    source: lyricsTexture
                    blurEnabled: true
                    blur: 0.8
                    blurMax: 20
                    maskEnabled: true
                    maskSource: lyricsBlurMask
                    // 0.5 + spread 1.0 = smoothstep(0, 1, maskAlpha): a true
                    // soft ramp. (0.0 + 1.0 made every alpha fully visible.)
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                Item {
                    id: lyricsSharpMask
                    anchors.fill: lyricsView
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.08; color: "transparent" }
                            GradientStop { position: 0.24; color: "white" }
                            GradientStop { position: 0.7; color: "white" }
                            GradientStop { position: 0.9; color: "transparent" }
                        }
                    }
                }

                Item {
                    id: lyricsBlurMask
                    anchors.fill: lyricsView
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            // Fades to 0 at the very edge, so the clip boundary is
                            // never visible — lines dissolve instead of being cut.
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.1; color: Qt.rgba(1, 1, 1, 0.6) }
                            GradientStop { position: 0.24; color: "transparent" }
                            GradientStop { position: 0.7; color: "transparent" }
                            GradientStop { position: 0.88; color: Qt.rgba(1, 1, 1, 0.6) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                    }
                }
            }
        }

        // Workspace dots, shown inside the idle pill (it keeps its size)
        // for a moment after a workspace switch, replacing the idle row.
        // Fixed width (the plain pill's), centred — anchored to the notch's
        // edges the dots slid and re-spaced while the notch sprang between
        // the lyric line's width and the plain pill.
        WorkspaceOsd {
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.plainPillWidth
            anchors.top: parent.top
            height: island.idleHeight
            z: 1
            accent: island.accentColor
            readonly property bool shown: island.displayState === "idle" && island.workspaceActive
                && !(island.pillModeEffective === "strip" && !island.stripHovered)
            opacity: shown ? 1 : 0
            scale: shown ? 1 : 0.85
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        SystemPanel {
            // Laid out at its own final size, revealed by the notch's clip — with
            // anchors.fill it followed the morphing notch and its content slid
            // and re-laid out during panel-to-panel switches.
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.widthFor("system")
            height: notch.heightFor("system")
            z: 1
            mon: systemMonitor
            battery: batteryMonitor
            active: island.displayState === "system"
            accent: island.accentColor
            onCloseRequested: island.systemOpen = false
            opacity: island.displayState === "system" ? 1 : 0
            scale: island.displayState === "system" ? 1 : 0.9
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        ActivityPanel {
            // Laid out at its own final size, revealed by the notch's clip — with
            // anchors.fill it followed the morphing notch and its content slid
            // and re-laid out during panel-to-panel switches.
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.widthFor("activity")
            height: notch.heightFor("activity")
            z: 1
            store: activityStore
            weather: weatherMonitor
            accent: island.accentColor
            onCloseRequested: island.activityOpen = false
            opacity: island.displayState === "activity" ? 1 : 0
            scale: island.displayState === "activity" ? 1 : 0.9
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        NotificationsPanel {
            // Laid out at its own final size, revealed by the notch's clip — with
            // anchors.fill it followed the morphing notch and its content slid
            // and re-laid out during panel-to-panel switches.
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.widthFor("notifications")
            height: notch.heightFor("notifications")
            z: 1
            store: notificationStore
            active: island.displayState === "notifications"
            onCloseRequested: island.notificationsOpen = false
            opacity: island.displayState === "notifications" ? 1 : 0
            scale: island.displayState === "notifications" ? 1 : 0.9
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        // Unread-notifications dot in the idle pill's top-right corner.
        Rectangle {
            z: 2
            width: 6
            height: 6
            radius: 3
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 8
            color: island.accentColor
            opacity: island.displayState === "idle" && notificationStore.unread > 0 && notch.settled ? 1 : 0
            visible: opacity > 0
            FadeBehavior on opacity {}
        }

        LauncherPanel {
            id: launcherPanel
            activity: activityStore
            // Laid out at its own final size, revealed by the notch's clip — with
            // anchors.fill it followed the morphing notch and its content slid
            // and re-laid out during panel-to-panel switches.
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.widthFor("launcher")
            height: notch.heightFor("launcher")
            z: 1
            active: island.displayState === "launcher"
            onCloseRequested: island.launcherOpen = false
            opacity: island.displayState === "launcher" ? 1 : 0
            scale: island.displayState === "launcher" ? 1 : 0.9
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        ClipboardPanel {
            id: clipboardPanel
            // Laid out at its own final size, revealed by the notch's clip — with
            // anchors.fill it followed the morphing notch and its content slid
            // and re-laid out during panel-to-panel switches.
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.widthFor("clipboard")
            height: notch.heightFor("clipboard")
            z: 1
            monitor: clipboardMonitor
            active: island.displayState === "clipboard"
            onCloseRequested: island.clipboardOpen = false
            opacity: island.displayState === "clipboard" ? 1 : 0
            scale: island.displayState === "clipboard" ? 1 : 0.9
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        PowerMenu {
            id: powerMenu
            // Laid out at its own final size, revealed by the notch's clip — with
            // anchors.fill it followed the morphing notch and its content slid
            // and re-laid out during panel-to-panel switches.
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: notch.widthFor("power")
            height: notch.heightFor("power")
            z: 1
            active: island.displayState === "power"
            onCloseRequested: island.powerMenuOpen = false
            onLockRequested: lockScreen.lock()
            opacity: island.displayState === "power" ? 1 : 0
            scale: island.displayState === "power" ? 1 : 0.9
            visible: opacity > 0
            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }

        // Animated sky behind the Weather sub-view (WeatherBackdrop.qml).
        WeatherBackdrop {
            // Fixed to the weather view's size (420×522) so the scene
            // doesn't stretch while the island morphs open — it's revealed.
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 420
            height: 522
            code: island.weatherPreviewCode >= 0 ? island.weatherPreviewCode : weatherMonitor.weatherCode
            isDay: island.weatherPreviewCode >= 0 ? island.weatherPreviewDay : weatherMonitor.isDay
            active: island.displayState === "overview" && quickOverviewPanel.activeView === "weather"
            opacity: active ? 1 : 0
            visible: opacity > 0
            FadeBehavior on opacity {}
        }

        // Laid out at the overview's final size and revealed by the notch's
        // clip, never at the springing notch's live size: with anchors.fill
        // every sub-view (battery, Wi-Fi, …) re-laid itself out on every
        // frame of the morph, and the first of those layouts stalled the
        // opening (~100 ms). The size follows the target only while the
        // overview is the morph state, so it keeps its last size while it
        // fades out on close.
        // Sized imperatively, straight to the new view's size on a switch:
        // the incoming view must lay out at its own size from its first
        // frame (a delayed resize made it jump after 90 ms); the outgoing
        // view fades out in 70 ms, too fast to notice its relayout.
        // When opening, the size is applied as soon as the overview is the
        // display state — inside the morph's start delay — so its first
        // layout happens before the frame starts to grow.
        readonly property real _overviewW: island.displayState === "overview" ? notch.widthFor("overview") : 0
        readonly property real _overviewH: island.displayState === "overview" ? notch.heightFor("overview") : 0
        function _applyOverviewSize() {
            if (island.displayState !== "overview") return
            quickOverviewPanel.width = notch._overviewW
            quickOverviewPanel.height = notch._overviewH
        }
        Connections {
            target: notch
            function on_OverviewWChanged() { notch._applyOverviewSize() }
            function on_OverviewHChanged() { notch._applyOverviewSize() }
        }
        QuickOverviewPanel {
            id: quickOverviewPanel
            panelOpen: island.overviewPanelOpen
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            z: 1
            batteryMonitor: batteryMonitor
            networkMonitor: networkMonitor
            bluetoothMonitor: bluetoothMonitor
            settingsStore: settingsStore
            weatherMonitor: weatherMonitor
            nightLight: nightLight
            calendarStore: calendarStore
            themeProfiles: themeProfiles
            wallpaperMonitor: wallpaperMonitor
            mediaPlaying: island.mediaPlaying
            onBackToNowPlaying: {
                island.overviewPanelOpen = false
                island.mediaExpandedRequested = true
            }
            onCloseRequested: island.closeAllPanels()

            opacity: island.displayState === "overview" ? 1 : 0
            scale: island.displayState === "overview" ? 1 : 0.9
            visible: opacity > 0

            FadeBehavior on opacity {}
            ScaleBehavior on scale {}
        }
    }

    // Anti-corner "ears": two small concave flares that merge notch's top
    // corners into the flat screen edge, instead of the hard 90° corners a
    // plain rectangle has there (the classic phone-camera-notch look).
    // Each ear's own drawing is static (painted once) — a solid RxR square
    // with a quarter-circle punched out of the corner touching notch, via
    // globalCompositeOperation "destination-out", leaving an L-shaped
    // sliver whose inner edge traces a smooth, tangent arc into both the
    // flat top line and notch's own vertical edge. Only each ear's X
    // position is reactive (bound to notch.x/notch.width), so they track
    // notch's live position through every displayState resize animation
    // without needing to redraw every frame — notch's y is always 0
    // (top-anchored) for every state, so no y binding is needed.
    component NotchEar: Shape {
        id: ear
        property bool rightSide: false
        anchors.top: notch.top
        // Clamped to notch's own live height: at every normal displayState
        // notch.height is well above 10, so this is a no-op (width/height
        // stay 10 exactly as before). Strip mode shrinks notch down to a
        // few px, and the ear used to stay a fixed 10x10 regardless — the
        // flare then stuck out past notch's own bottom edge, reading as an
        // oversized, disconnected curve next to the thin strip bar.
        width: Math.min(10, notch.height)
        height: Math.min(10, notch.height)
        // A vector Shape, not a Canvas: the Canvas version (black square
        // minus a destination-out quarter circle) left a light fringe along
        // its anti-aliased edges, plainly visible as light triangles at the
        // strip's corners over a dark fullscreen app (found frame by frame
        // in a screen recording).
        preferredRendererType: Shape.CurveRenderer
        // The sliver between the screen's top edge, notch's side and a
        // quarter circle centred on the far bottom corner (radius = the
        // ear's size), so its curve runs tangent into both edges.
        ShapePath {
            // Glass mode: same translucency as the notch's outer rim
            // (surface 0.25 + first ring 0.3 ≈ 0.47).
            fillColor: island.glassRim > 0 ? Qt.rgba(0, 0, 0, 0.47) : "#000000"
            strokeColor: "transparent"
            startX: ear.rightSide ? ear.width : 0
            startY: 0
            PathLine { x: ear.rightSide ? 0 : ear.width; y: 0 }
            PathLine { x: ear.rightSide ? 0 : ear.width; y: ear.height }
            PathArc {
                x: ear.rightSide ? ear.width : 0
                y: 0
                radiusX: ear.width
                radiusY: ear.height
                direction: ear.rightSide ? PathArc.Clockwise : PathArc.Counterclockwise
            }
        }
    }

    NotchEar {
        id: notchEarLeft
        x: notch.x - width
    }

    NotchEar {
        id: notchEarRight
        rightSide: true
        x: notch.x + notch.width
    }

    // Charging: green light running around the pill, ears included —
    // outside notch because notch clips its children.
    ChargingOutline {
        x: notch.x - ear
        y: notch.y
        width: notch.width + 2 * ear
        height: notch.height
        ear: notchEarLeft.width
        cornerRadius: notch.bottomLeftRadius
        shown: island.displayState === "charging"
        opacity: shown ? 1 : 0
        visible: opacity > 0
        FadeBehavior on opacity {}
    }

    // Charging badge: a sibling of notch, not content inside it — an
    // IndicatorBadge draws its own black circle, and nesting it inside
    // notch's single black rounded rect made it read as an icon floating
    // inside one continuous shape rather than a separate floating badge next
    // to the pill (the look the reference screenshot actually shows).
    // Positioned immediately left of notch with a visible gap, vertically
    // pinned to a fixed inset (island.idleBadgeGap) inside the idle pill's
    // height band (not anchored to notch's live, currently-animating height
    // — same drift bug already documented for idleRow above). Active on Charging OR FullyCharged (not just
    // Charging alone) — a laptop plugged in and topped off at 100% reports
    // FullyCharged, not Charging, but should still show "plugged in", same
    // convention as macOS's own charging-bolt overlay.
    RowLayout {
        id: idleBadgeLeft
        anchors.right: notch.left
        anchors.rightMargin: 8
        anchors.top: parent.top
        anchors.topMargin: island.idleBadgeGap
        spacing: 4
        opacity: (island.displayState === "idle" && !(island.pillModeEffective === "strip" && !island.stripHovered)) ? 1 : 0
        scale: island.displayState === "idle" ? 1 : 0.8
        visible: opacity > 0

        FadeBehavior on opacity {}
        ScaleBehavior on scale {}

        // Hand-drawn bolt instead of IndicatorBadge's usual icon-theme
        // IconImage — no installed icon theme (Adwaita/breeze/breeze-dark,
        // the only ones present on this system) ships a standalone
        // lightning-bolt glyph; every "flash"/"bolt"/"thunderbolt" icon
        // found is either a memory-card or device-port composite, not a
        // plain bolt shape. Same black-circle/fade/scale behavior as
        // IndicatorBadge (kept in sync by hand since this is the one badge
        // that needs a shape IndicatorBadge's icon-name API can't provide),
        // just with a vector BoltShape instead of a recolored SVG.
        Item {
            id: chargingGlyph
            property bool active: batteryMonitor.state === UPowerDeviceState.Charging || batteryMonitor.state === UPowerDeviceState.FullyCharged
            width: island.idleBadgeSize
            height: island.idleBadgeSize
            opacity: active ? 1 : 0
            scale: active ? 1 : 0.7
            visible: opacity > 0

            FadeBehavior on opacity {}
            ScaleBehavior on scale {}

            // Level ring + breathing bolt — see ChargeBadge.qml.
            ChargeBadge {
                anchors.centerIn: parent
                percent: batteryMonitor.percentage
                charging: batteryMonitor.state === UPowerDeviceState.Charging
                shown: chargingGlyph.active && idleBadgeLeft.visible
            }
        }

        // Battery level while on battery (Settings → Battery), and always at
        // ≤ 10 % with the minutes left; ChargeBadge above covers the
        // plugged-in case. LiveActivityChip no longer shows low battery.
        BatteryBadge {
            size: island.idleBadgeSize
            battery: batteryMonitor
            enabledSetting: settingsStore.batteryBadge
            showPercent: settingsStore.batteryBadgePercent
            percentInside: settingsStore.batteryPercentInside
            lowPower: PowerProfiles.profile === PowerProfile.PowerSaver
            onClicked: {
                island.closeAllPanels()
                quickOverviewPanel.activeView = "battery"
                island.overviewPanelOpen = true
            }
        }

        // Screen recording lives out here rather than in the pill's
        // LiveActivityChip (user request: outside the pill, on the left).
        // Last in the row so it sits right next to the pill.
        RecordingBadge {
            store: activityStore
            size: island.idleBadgeSize
            surfaceColor: island.surfaceColor
            glassRim: island.glassRim
            onOpenRequested: { island.closeAllPanels(); island.activityOpen = true }
        }
    }

    // Mic/camera badges: right of notch (per explicit user placement —
    // charging stays left, privacy badges go right), same sibling-of-notch
    // reasoning and fixed-point vertical pinning as idleBadgeLeft above.
    RowLayout {
        id: idleBadgeRight
        anchors.left: notch.right
        anchors.leftMargin: 8
        anchors.top: parent.top
        anchors.topMargin: island.idleBadgeGap
        spacing: 4
        opacity: (island.displayState === "idle" && !(island.pillModeEffective === "strip" && !island.stripHovered)) ? 1 : 0
        scale: island.displayState === "idle" ? 1 : 0.8
        visible: opacity > 0

        FadeBehavior on opacity {}
        ScaleBehavior on scale {}

        // Cava bars moved into the idle pill itself (clockRow's right-side
        // mirror slot) — see that block for the real bar-drawing content.
        // Only mic/camera badges remain in this separate floating cluster.

        // System tray: shown while any StatusNotifierItem is registered;
        // click opens the overview's tray sub-view.
        IndicatorBadge {
            id: trayBadge
            size: island.idleBadgeSize
            // Liquid Glass: same frosted rim fading into a black core as
            // the notch (translucent fill + stacked 0.3-alpha rings).
            bgColor: island.surfaceColor
            active: SystemTray.items.values.length > 0
            Behavior on color { ColorAnimation { duration: 300 } }
            Repeater {
                model: 4
                Rectangle {
                    required property int index
                    readonly property real inset: island.glassRim * 0.6 * index / 4
                    anchors.fill: parent
                    anchors.margins: inset
                    radius: width / 2
                    color: Qt.rgba(0, 0, 0, island.glassRim > 0 ? 0.3 : 1)
                    visible: island.glassRim > 0 || index === 0
                }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: island.glassRim * 0.6
                radius: width / 2
                color: "#000000"
            }
            Grid {
                anchors.centerIn: parent
                columns: 2
                spacing: 3
                Repeater {
                    model: 4
                    Rectangle { width: 6; height: 6; radius: 2; color: "#ffffff" }
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    quickOverviewPanel.activeView = "tray"
                    island.overviewPanelOpen = true
                }
            }
        }
        // Portal screen sharing (ScreenShareMonitor), with the other
        // privacy indicators (user moved it here from the left).
        IndicatorBadge {
            size: island.idleBadgeSize
            bgColor: island.surfaceColor
            glassRim: island.glassRim
            icon: "screen-shared-symbolic"
            iconRatio: 0.42
            iconColor: "#0a84ff"
            active: screenShareMonitor.active
        }
        IndicatorBadge {
            size: island.idleBadgeSize
            bgColor: "#000000"
            shape: "mic"
            iconColor: "#ff9f0a"
            active: micMonitor.active && settingsStore.micIndicatorEnabled
        }

        IndicatorBadge {
            size: island.idleBadgeSize
            bgColor: "#000000"
            shape: "video"
            iconColor: "#32d74b"
            active: cameraMonitor.active && settingsStore.cameraIndicatorEnabled
        }
    }
}
