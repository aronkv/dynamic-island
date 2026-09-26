# Dynamic Island for Hyprland

An iPhone-style **Dynamic Island** desktop shell for [Hyprland](https://hyprland.org), built with
[Quickshell](https://quickshell.outfoxxed.me) (QML). One black pill at the top of the screen that
morphs into everything else: media player, notifications, OSDs, quick settings, a Spotlight-style
launcher, calculator, weather, clipboard, calendar, power menu — plus a matching lock screen and an
SDDM login theme. Visual language: Apple (SF Pro, iOS dark palette, spring animations), with
optional "Liquid Glass" via the hyprglass plugin.

Built for a ThinkPad T480 (dual battery, USB-C PD) on CachyOS / Arch with a **Lua-based Hyprland
config**, but most of it is hardware-independent.

---

## Features

### The island
- **Single morphing surface** — one fixed-size layer-shell window; only the inner shape resizes, with
  an elastic spring (iPhone-island style). Content cross-fades with a fast exit / delayed entry so
  nothing "spills" during a morph.
- **Idle pill** — clock, now-playing (album art, title or a live lyrics line), cava bars in the album
  cover's color, mic/camera privacy badges, charging bolt. Optional thin **strip mode**.
- **Two looks** — solid black; or with *Liquid Glass* on, a black body with a frosted, gradient glass
  rim (hyprglass), macOS-Tahoe style. The same toggle applies glass to all windows (terminals stay
  black — neutral tint).
- **Transient OSDs** — volume, brightness, Caps Lock, mic mute (round badge + mirrored switch),
  screenshot preview, LocalSend transfers, notifications.
- **Charging** — a green stroke sweeps around the island on plug-in, plus an iPhone-style
  "charging" view.
- **Workspaces** — on every switch, dots appear inside the pill (occupied / empty / active) and the
  active pill moves with an iOS page-control "stretch".

### Panels
| Panel | Highlights |
|---|---|
| **Music** | Blurred album-art ambient background, 20-band cava visualizer across the top in the cover's dominant color, big cover, scrub-able progress with elapsed/remaining, round play button, Apple-Music-style synced lyrics (timestamped lyrics are always preferred — see below) with soft blurred edges. |
| **Overview** | Clock, Wi-Fi/Ethernet (the primary connection is shown), Bluetooth, battery, Liquid Glass toggle, shortcuts to every panel. |
| **Battery** | Per-pack (internal/removable) level, health and cycle count straight from sysfs, combined health and capacity vs. design, live power draw / charging rate, charger wattage (USB-C PD), power profiles via tlp-pd (Power Saver / Balanced / Performance), automatic Low Power at ≤ 20 %. |
| **Wi-Fi / Bluetooth** | Device cards, password entry, details, forget/disconnect, pairing. |
| **Weather** | Open-Meteo: big place name, animated sky backdrop, 24-hour strip with temperature curve, 7-day range bars, feels-like / humidity / wind / UV / sunrise-sunset / pressure tiles. |
| **Calculator** | One input line with live result. Functions (`sqrt sin cos tan log ln abs round …`, degrees), `^`, `%`, `pi`, `ans`, implicit multiplication (`2x`). **Equations & inequalities in x** (linear, quadratic, quartic, trig on 0–360°) with a **graph** (curve, roots, shaded solution set). Smart queries: dates, currency (live ECB rates), units. Optional history (button / Ctrl+H, or always on). |
| **Launcher** | Spotlight-style, grows out of the island: fuzzy search, most-launched first, **starred favorites as square tiles**, math/currency row, terminal apps in kitty. |
| **Clipboard** | cliphist-backed history with image thumbnails. |
| **Calendar** | Month grid + local reminders with natural-language quick-add ("tomorrow 9:00 dentist"), fired as notifications. |
| **Theme** | macOS-Appearance-style picker: live preview (wallpaper, mini island, mini terminal in the theme's colors), accent chips, presets + a *Dynamic* theme derived from the wallpaper (matugen). Applies to kitty, GTK, Qt (qt6ct), Spotify (spicetify), VS Code, KDE globals, Hyprland borders. |
| **Wallpaper** | Keyboard-navigable grid, applies via hyprpaper. |
| **Settings** | iOS-style grouped list (Liquid Glass, strip mode, now-playing mode, Do Not Disturb, privacy indicators, calculator history, manual weather location). |
| **Shortcuts** | Live cheat sheet generated from `keybindings.lua`. |
| **Power menu** | Lock · Sleep · Log Out · Restart · Shut Down, numbered 1–5 — **hold** a number (or press-and-hold a button) ~1 s to run it; a tap does nothing. |

### Lock screen & login
- **Lock screen** (`WlSessionLock` + PAM): blurred wallpaper, big rounded clock, now-playing card,
  iOS-style battery, password pill that shakes on a wrong password. Sleep always locks first.
- **SDDM theme "Island"** (`sddm/island/`): same look, two stages (lock view → login view on any
  key/click, SilentSDDM-inspired), session picker, power buttons. Fonts and wallpaper are bundled
  because SDDM can't read your home directory.

### "Type-first" panels
The calculator, launcher and power menu get keyboard focus immediately on open (Hyprland focus grab)
and close when you click another window, which then receives the focus — like Spotlight.

---

## Keybindings

Defined in `~/.config/hypr/config/keybindings.lua` (the Shortcuts panel reads this file).

| Keys | Action |
|---|---|
| `SUPER` (tap) | Toggle overview / now-playing card |
| `SUPER + Space` | Launcher |
| `SUPER + C` | Calculator |
| `SUPER + W` | Weather |
| `SUPER + B` | Battery |
| `SUPER + K` | Calendar |
| `SUPER + SHIFT + V` | Clipboard |
| `SUPER + I` | Settings |
| `SUPER + SHIFT + T` | Theme |
| `SUPER + SHIFT + W` | Wallpaper |
| `SUPER + H` | Keyboard shortcuts |
| `SUPER + Escape` | Power menu (then hold `1`–`5`) |
| `SUPER + L` | Lock screen |
| `SUPER + SHIFT + M` | Log out |

Inside panels: `Esc` closes, arrows navigate, `Enter` activates. Launcher: `Ctrl+S` stars the
selected app. Calculator: `Ctrl+H` history, `Ctrl+L` clear history, `↑` recall last.

## IPC

Everything is scriptable through `qs ipc call <target> <function>`:

| Target | Functions |
|---|---|
| `overview`, `settings`, `calculator`, `weather`, `theme`, `wallpaper`, `shortcuts`, `battery`, `calendar`, `clipboard`, `launcher`, `power` | `toggle` |
| `lock` | `lock`, `isLocked` |
| `theme` | `apply <name>` (e.g. `Blue`, `Dynamic`) |
| `battery` | `chargeTest` (plays the plug-in animation) |
| `brightness` | `up`, `down` |

Run `qs ipc show` for the live list.

---

## Requirements

- **Quickshell** ≥ 0.3 and **Hyprland** (Lua config — `hyprctl keyword` is not used anywhere;
  runtime changes go through `hyprctl eval`)
- PipeWire + WirePlumber, UPower, NetworkManager, BlueZ (`bt-agent` for pairing)
- **tlp** + **tlp-pd** (power profiles through Quickshell's `PowerProfiles`)
- **cava**, **matugen**, **hyprpaper**, **kitty**
- `curl`, `python3`, `wl-clipboard`, `cliphist`, `grim`, `slurp`, `hyprshot`, `hyprpicker`, `libnotify`
- Optional: **hyprglass** (Liquid Glass, via `hyprpm`), **spicetify** (Spotify theming), `sddm`
- Fonts: **SF Pro** (Display / Text / Rounded) in `~/.local/share/fonts/SF-Pro/`; Noto Sans Symbols 2
- Online services (no keys needed): lrclib.net (lyrics), open-meteo.com (weather + geocoding),
  ip-api.com (approximate location), frankfurter.dev (exchange rates)

## Setup

1. Put this directory at `~/.config/quickshell/`.
2. Autostart (in `~/.config/hypr/config/autostart.lua`):
   ```lua
   hl.exec_cmd("hyprpm reload -n")   -- loads hyprglass (hyprpm enable alone doesn't)
   hl.exec_cmd("hyprpaper")
   hl.exec_cmd("qs")
   hl.exec_cmd("bt-agent --capability=NoInputNoOutput")
   ```
   plus the two `wl-paste --watch cliphist store` watchers for the clipboard panel.
3. Enable power profiles: `sudo pacman -S tlp-pd && sudo systemctl enable --now tlp-pd`.
4. Optional glass: `hyprpm add https://github.com/hyprnux/hyprglass && hyprpm enable hyprglass`,
   and the `hl.plugin.hyprglass` block in `look-and-feel.lua` (island preset + neutral window tint).
5. Optional login screen: `sudo sh ~/.config/quickshell/sddm/install.sh`
   (re-run after changing the theme or wallpaper; undo with
   `sudo rm /etc/sddm.conf.d/10-island-theme.conf`).

Settings persist in `settings.json`; launcher stars/counts in `launcher-history.json`; calendar
reminders in `calendar.json`; theme presets in `theme-profiles.json`.

---

## Architecture (short version)

- `shell.qml` → `DynamicIsland.qml`: one `PanelWindow` with a fixed surface (640×620); the inner
  `notch` (`ClippingRectangle`) resizes via `targetWidth`/`targetHeight` + spring animations.
- **One derived state machine**: `displayState` (volume, brightness, micmute, capslock, charging,
  power, launcher, clipboard, notification, …, overview, mediaExpanded, idle) computed from a few
  root-cause booleans. Every view is an always-present sibling cross-faded with
  `FadeBehavior` / `ScaleBehavior`.
- **Monitors** (`*Monitor.qml`) wrap one data source each (MPRIS, PipeWire, UPower/sysfs,
  NetworkManager, BlueZ, cava, weather, clipboard, LocalSend …) and are declared early in
  `DynamicIsland.qml`.
- **Panels** (`*Panel.qml`) live in `QuickOverviewPanel.qml` (push/pop sub-views) or directly in the
  island (launcher, power, clipboard).
- Shared pieces: `Theme.qml` (design tokens singleton), `PanelHeader.qml`, `ToggleSwitch.qml`,
  `CalcEngine.qml` (safe expression parser, no `eval`), `ArtColor.qml` (cover color extraction).
- Theming pipeline: `ThemeProfiles.qml` → `MatugenMonitor.qml` (matugen templates in
  `matugen-templates/`) + `ThemeColorMonitor.qml` (Hyprland borders, island accent) + small Python
  writers for kitty / VS Code / KDE.

See **`CLAUDE.md`** for the full architecture notes and the list of bug classes already hit (and how
to avoid them), and **`PROGRESS.md`** for the detailed change log.

## Development

There is no build step — Quickshell hot-reloads on save.

```bash
timeout 5 qs > /tmp/qs.log 2>&1; grep -E 'ReferenceError|TypeError|ERROR' /tmp/qs.log   # headless check
qs list                      # running instance(s) — make sure there's exactly one
qs log -i <id> -t 200        # live log of that instance
qs kill -i <id>; hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("qs"))'   # clean restart
```

A failed hot reload keeps the old config running — if a change seems to have no effect, check the
live log and restart.

## Credits

Inspired by Apple's Dynamic Island / iOS / macOS design, [SilentSDDM](https://github.com/uiriansan/SilentSDDM)
(login flow) and [QS-DFMID26](https://github.com/Legfena/QS-DFMID26) (theme carousel idea).
SF Pro fonts © Apple (used locally). Icons: Adwaita.
