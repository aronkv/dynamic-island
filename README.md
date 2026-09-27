# Dynamic Island for Hyprland

An iPhone-style **Dynamic Island** desktop shell for [Hyprland](https://hyprland.org), built with
[Quickshell](https://quickshell.outfoxxed.me) (QML). There is no bar, no dock and no separate
popups: one black pill at the top of the screen morphs into everything else. It covers the media
player, notifications, OSDs, quick settings, a Spotlight-style launcher, a calculator that solves
equations, weather, clipboard, calendar, screen recording, a system monitor and a power menu. A
matching lock screen and SDDM login theme are included.

The visual language is Apple's: SF Pro, the iOS dark palette and spring physics. Liquid Glass is
optional, via the hyprglass plugin.

It was built on a ThinkPad T480 (dual battery, USB-C PD) running CachyOS with a **Lua-based
Hyprland config**. Almost all of it is hardware-independent.

---

## What makes it different

- **One surface, zero popups.** Every panel, OSD and alert is content inside a single morphing
  shape.
  - The Wayland surface itself never resizes. Only the inner notch animates, with a real spring, so
    the compositor never re-centers or stutters.
  - Content cross-fades with a fast exit and a delayed entry, so nothing spills out mid-morph.
- **One theme, the whole desktop.** Picking a theme (or *Dynamic*, derived from your wallpaper)
  recolors all of these at once:
  - kitty, with 16 guaranteed-distinct ANSI colors;
  - GTK and Qt;
  - VS Code, KDE globals and Hyprland borders;
  - the island's accent;
  - a custom **Obsidian theme**, which follows the accent or stays Obsidian purple.
- **Live activities, like iOS.** Screen recording, timers, pomodoro, "rain in 15 min" and low battery
  live in the idle pill next to the clock. Tap one for its controls.
- **A calculator that thinks.**
  - It solves linear, quadratic, quartic and trig equations and inequalities in `x`, and graphs them
    with the roots and the shaded solution set.
  - It converts currencies (live ECB rates), units and dates (`days until christmas`).
  - It uses a hand-written recursive-descent parser. There is no `eval`, so there is no injection
    surface.
- **Honest privacy badges.** The mic/camera indicators ignore the island's own cava visualizer and
  the screen recorder's system-audio tap, so they only light up for a real microphone.
- **Escalating low-battery care.**
  - **20 %** — remaining time, and automatic Low Power.
  - **10 %** — a Low Power nudge.
  - **5 %** — a pulsing critical view with *Dim Display*.
  - **1 %** — *Sleep Now*.
- **Hold-to-confirm power menu.** Lock, Sleep, Log Out, Restart and Shut Down are numbered 1–5. You
  **hold** a number (or a button) for ~1 s; a stray tap never shuts anything down.
- **Everything is hand-made.** There is no QtQuick.Controls. Switches, sliders, segmented controls,
  chips and sheets are all custom, and the privacy badges and the charging bolt are vector shapes in
  SF Symbols proportions.
- **Designed to be light.**
  - Monitors poll only while their panel is open, and the system monitor stops completely when it
    is closed.
  - `Reduce motion` turns every spring and ambient animation into a quick fade.

### Fun facts from building it

- **The Wi-Fi share QR code is drawn module by module** with integer pixels and a 4-module quiet
  zone. The first version (a smoothly scaled SVG) decoded fine in software, but real phone cameras
  refused it.
- **Icons are recolored with an alpha mask, never `colorization`.** Qt's colorize blends in
  proportion to the icon's own luminance, so a dark Adwaita glyph can never become pure white.
- **Brightness steps along a gamma-2.2 curve** (20 perceptual levels), so the bottom steps aren't
  stuck and the top ones don't jump.
- **Synced lyrics always win.** Plain lyrics are only used when no timestamped version exists
  anywhere. Scrolling is Apple-Music-style, with blurred edges.
- **CachyOS made the island stutter.** Its default `ananicy-cpp` rules classify `qs` as a background
  "Service" (nice 10). `system/install.sh` reclassifies it as interactive.
- **Launcher file results show real previews:**
  - images themselves, embedded album covers, video frames and PDF first pages;
  - generated once with ffmpeg / ffmpegthumbnailer / pdftoppm and cached;
  - the freedesktop thumbnail cache is used first when it already has one.

---

## Features

### The island
- **Idle pill** — clock, now-playing (album art, title or a live lyrics line), cava bars in the
  album cover's color, mic/camera privacy badges, charging bolt, unread-notification dot.
  Optional thin **strip mode**.
- **Two looks:**
  - solid black;
  - with *Liquid Glass* on, a black body with a frosted, gradient glass rim (hyprglass),
    macOS-Tahoe style. The same toggle applies glass to all windows; terminals stay black thanks to
    a neutral tint.
- **Transient OSDs** — volume, brightness, Caps Lock, mic mute, screenshot preview, LocalSend
  transfers, notifications.
- **Live activities** — at the left of the pill:
  - screen recording (pulsing red dot + elapsed time);
  - timer / stopwatch / pomodoro (progress ring + time);
  - low battery (≤ 10 %);
  - "rain soon" (Open-Meteo 15-minute data).
  
  Tap one for its controls.
- **Charging** — an iPhone-style "charging" view with a liquid battery fill when you plug in.
- **Low battery** — escalating alerts at 20 / 10 / 5 / 1 % (see above).
- **Workspaces** — on every switch, dots appear inside the pill and the active one moves with an iOS
  page-control "stretch".

### Panels
| Panel | Highlights |
|---|---|
| **Music** | Blurred album-art ambient background, 20-band cava visualizer in the cover's color, big cover, scrub-able progress, Apple-Music-style synced lyrics with soft blurred edges. |
| **Overview** | Clock, Wi-Fi/Ethernet, Bluetooth, battery, Liquid Glass toggle, shortcuts to every panel. |
| **Battery** | Monochrome, with a two-tone charging bolt (black over the fill, white over the empty part). Per-pack level, health and cycle count straight from sysfs, capacity vs. design. *Charging at* = watts going into the battery right now (vs. the USB-C charger's rating); *Using* = the drain on battery. Power profiles via tlp-pd; automatic Low Power at ≤ 20 % (a manual change is respected until you plug in again). |
| **Wi-Fi / Bluetooth** | Device cards, password entry, details, forget/disconnect, pairing; **share the Wi-Fi password as a QR code** (click to enlarge). |
| **Weather** | Open-Meteo: animated sky backdrop, 24-hour temperature curve, 7-day range bars, feels-like / humidity / wind / UV / sunrise-sunset / pressure tiles, rain alert. |
| **Calculator** | Opens ready to type ("Challenge me…"). Input and result cards, animated result, chips (Copy, Use as ans, one per root). **Equations & inequalities** with a graph (hover crosshair with x/y readout). Currency, units, dates. History side sheet (Ctrl+H). **Help sheet** (`?`) with clickable examples. |
| **Launcher** | Fuzzy app search (most-launched first), starred favorites as tiles. **Files** with real thumbnails (Ctrl+Enter opens the folder). **Emoji** (`:fire`, Enter copies). **Google search** (`?query`). Web addresses (`youtube.com`) open directly. Commands (`timer 5m`, `stopwatch`, `pomodoro`, `record`). Inline math. |
| **Notifications** | Last 100 notifications (survive restarts), grouped by app, relative times, click to activate, ✕ / swipe to dismiss, clear per app / all. |
| **System** | CPU (total + per-core), memory, temperature + fan, network ↓/↑ with 60-second sparklines, disk, top processes. |
| **Clipboard** | cliphist history with image thumbnails. |
| **Calendar** | Month grid + reminders with natural-language quick-add ("tomorrow 9:00 dentist"). |
| **Theme** | macOS-Appearance-style picker with a live preview (wallpaper, mini island, mini terminal), presets + *Dynamic* (matugen from the wallpaper). |
| **Wallpaper** | Keyboard-navigable grid, applies via hyprpaper. |
| **Settings** | iOS-style grouped list. Appearance: Liquid Glass, strip mode. Display: Night Shift via hyprsunset (sunset→sunrise or always, warmth slider), Reduce motion, Obsidian follows theme. **Screen recording**: resolution, fps, quality, system audio, microphone, cursor. Also now-playing mode, Do Not Disturb, privacy indicators, calculator history, weather. |
| **Shortcuts** | Live cheat sheet generated from `keybindings.lua`. |
| **Power menu** | Lock · Sleep · Log Out · Restart · Shut Down; hold 1–5 (or press-and-hold a button). |

### Lock screen & login
- **Lock screen** (`WlSessionLock` + PAM):
  - blurred wallpaper, big rounded clock, now-playing card, iOS-style battery;
  - a password pill that shakes on a wrong password;
  - Sleep always locks first.
- **SDDM theme "Island"** (`sddm/island/`):
  - the same look, in two stages (lock view, then the login view on any key or click);
  - session picker and power buttons.

### "Type-first" panels
The calculator, launcher, clipboard, settings and power menu get keyboard focus the moment they
open. Clicking another window closes them and hands the focus to it, like Spotlight.

---

## Installation

These steps target **Arch / CachyOS** with a **Lua-based Hyprland config** (`hl.config`,
`hl.bind` …). On plain Arch, `quickshell` and `matugen` come from the AUR; CachyOS ships both in its
own repos.

### 1. Packages
```bash
sudo pacman -S --needed quickshell hyprland hyprpaper hyprpicker hyprshot hyprsunset kitty \
  pipewire-audio wireplumber libpulse playerctl cava upower networkmanager bluez bluez-utils \
  bluez-tools brightnessctl tlp tlp-pd matugen curl jq python wl-clipboard cliphist grim slurp \
  libnotify gpu-screen-recorder plocate qrencode ffmpeg ffmpegthumbnailer poppler noto-fonts
```

### 2. Fonts
Put **SF Pro** (Display, Text and Rounded `.otf` files from Apple's developer site) in
`~/.local/share/fonts/SF-Pro/`, then run `fc-cache -f`.

### 3. The shell itself
```bash
git clone <this repo> ~/.config/quickshell     # or copy the folder there
qs                                             # first run in a terminal, to see the log
```

### 4. Hyprland: autostart
Add this to `~/.config/hypr/config/autostart.lua`:
```lua
hl.exec_cmd("hyprpm reload -n")   -- only if you use hyprglass
hl.exec_cmd("hyprpaper")
hl.exec_cmd("qs")
hl.exec_cmd("bt-agent --capability=NoInputNoOutput")
hl.exec_cmd("wl-paste --type text --watch cliphist store")
hl.exec_cmd("wl-paste --type image --watch cliphist store")
```
Don't run another notification daemon (mako, dunst, swaync): the island is the notification
server.

### 5. Hyprland: keybindings
Add these to `~/.config/hypr/config/keybindings.lua`. The Shortcuts panel reads its
`qs ipc call …` lines.
```lua
hl.bind(mainMod .. " + Super_L", hl.dsp.exec_cmd("qs ipc call overview toggle"), { release = true })
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("qs ipc call calculator toggle"))
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call notifications toggle"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("qs ipc call activity record"))
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("qs ipc call system toggle"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("qs ipc call power toggle"))
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs ipc call brightness up"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs ipc call brightness down"), { locked = true, repeating = true })
-- …the rest follow the table under "Keybindings"
```

### 6. Services
```bash
sudo systemctl enable --now tlp-pd bluetooth NetworkManager
sudo updatedb                                   # first plocate index (a timer keeps it fresh)
```

### 7. Smooth animations (CachyOS)
```bash
sudo sh ~/.config/quickshell/system/install.sh
```
This does two things:
- It reclassifies `qs` from ananicy-cpp's "Service" (nice 10) to interactive (nice -4).
- It adds a TLP drop-in that makes the power profiles clearly distinct:
  - **Performance** — EPP `performance`, iGPU ≥ 600 MHz;
  - **Balanced** — EPP `balance_performance`, iGPU ≥ 450 MHz;
  - **Power Saver** — unchanged.

To undo it, follow the instructions at the top of the script.

### 8. Optional extras
- **Liquid Glass:** run
  `hyprpm add https://github.com/hyprnux/hyprglass && hyprpm enable hyprglass`.
  Then add the `hl.plugin.hyprglass` block (island preset + neutral window tint) to
  `look-and-feel.lua`.
- **Login screen:** run `sudo sh ~/.config/quickshell/sddm/install.sh`.
  - Re-run it after changing the theme or the wallpaper.
  - To undo it: `sudo rm /etc/sddm.conf.d/10-island-theme.conf`.
- **Obsidian theme:**
  1. Copy `obsidian/Island/` into `<vault>/.obsidian/themes/`.
  2. Pick *Island* in Obsidian → Appearance.
  3. From then on, `obsidian_write_theme.py` rewrites its color block on every theme change. It
     finds vaults through `~/.config/obsidian/obsidian.json`.
- **Spotify:** plain spicetify + Marketplace; the island doesn't theme it.

### 9. Check that it works
```bash
qs list                                  # exactly one instance
qs ipc call battery chargeTest           # plays the charging animation
qs ipc call battery lowTest 5            # previews the critical battery alert
qs ipc call calculator help              # calculator with its help sheet
```

### Troubleshooting
| Symptom | Fix |
|---|---|
| Animations stutter | Check `ps -o ni= -p $(pgrep -x qs)`. It should be `-4`, not `10`. Run step 7. |
| A change has no effect | A failed hot reload keeps the old config. Check `qs log -i <id>` and restart `qs`. |
| Two islands / doubled actions | Two instances are running. `qs list`, then `qs kill -i <id>` for the extra one. |
| Notifications don't appear | Another daemon (mako/dunst/swaync) owns `org.freedesktop.Notifications`. Stop it. |
| `hyprctl keyword` errors | Expected with a Lua config. Everything here uses `hyprctl eval`. |
| Screen recording does nothing | Check that `gpu-screen-recorder` is installed. The island notifies you if it's missing. |

---

## Keybindings

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
| `SUPER + N` | Notification history |
| `SUPER + R` | Start / stop screen recording (`~/Videos/Recordings`) |
| `SUPER + M` | System monitor |
| `SUPER + Escape` | Power menu (then hold `1`–`5`) |
| `SUPER + L` | Lock screen |
| `SUPER + SHIFT + M` | Log out |

Inside panels, `Esc` closes, the arrows navigate and `Enter` activates.

| Where | Keys |
|---|---|
| Launcher | `Ctrl+S` stars the selected app. `Ctrl+Enter` opens a file's folder. |
| Calculator | `?` opens help. `Ctrl+H` history. `Ctrl+L` clears history. `↑` recalls the last expression. |

## IPC

Everything is scriptable through `qs ipc call <target> <function>`:

| Target | Functions |
|---|---|
| `overview`, `settings`, `calculator`, `weather`, `theme`, `wallpaper`, `shortcuts`, `battery`, `calendar`, `clipboard`, `launcher`, `power`, `wifi`, `system` | `toggle` |
| `overview` | `open <view>` |
| `calculator` | `open <expr>`, `help` |
| `wifi` | `share` (toggles the password QR) |
| `notifications` | `toggle`, `clear` |
| `activity` | `toggle`, `record`, `timer <5m|90s|1h30m>`, `stopwatch`, `pomodoro`, `stop` |
| `lock` | `lock`, `isLocked` |
| `theme` | `apply <name>` (e.g. `Blue`, `Dynamic`) |
| `battery` | `chargeTest`, `lowTest <20|10|5|1>`, `lowDismiss` |
| `brightness` | `up`, `down` |
| `weather` | `preview <code> <day>` (`-1` resets) |

Run `qs ipc show` for the live list.

## Files it keeps

| File | Contents |
|---|---|
| `settings.json` | All settings. |
| `launcher-history.json` | Launcher stars and launch counts. |
| `calendar.json` | Reminders. |
| `notifications.json` | Notification history. |
| `activity.json` | Running timers (they survive a reload). |
| `theme-profiles.json` | Theme presets. |
| `~/.cache/quickshell/thumbs/` | Launcher thumbnails. |
| `~/Videos/Recordings/` | Screen recordings. |

**Online services** (none of them needs a key):

| Service | Used for |
|---|---|
| lrclib.net | Lyrics |
| open-meteo.com | Weather and geocoding |
| ip-api.com | Approximate location |
| frankfurter.dev | Exchange rates |
| Google s2 | Favicons in the launcher |

---

## Architecture (short version)

- **Entry point:** `shell.qml` → `DynamicIsland.qml`. It is one `PanelWindow` with a fixed surface.
  The inner `notch` resizes via `targetWidth`/`targetHeight` + spring animations.
- **One derived state machine:** `displayState` (volume, brightness, charging, lowbattery, power,
  launcher, notifications, …, overview, mediaExpanded, idle) is computed from a few root-cause
  booleans. Every view is an always-present sibling, cross-faded with `FadeBehavior` /
  `ScaleBehavior`.
- **Monitors** (`*Monitor.qml`, `*Store.qml`) wrap one data source each and are declared early in
  `DynamicIsland.qml`. The sources are MPRIS, PipeWire, UPower/sysfs, NetworkManager, BlueZ, cava,
  weather, clipboard, notifications, activities and LocalSend.
- **Panels** (`*Panel.qml`) live in `QuickOverviewPanel.qml` (push/pop sub-views) or directly in the
  island (launcher, power, clipboard, notifications, system, activity).
- **Shared pieces:** `Theme.qml` (design tokens, reduce motion), `PanelHeader.qml`,
  `ToggleSwitch.qml`, `CalcEngine.qml` + `CalcSmart.js` (parser, no `eval`), `ThemePalette.js`,
  `BoltShape` / `MicShape` / `VideoShape`.
- **Theming pipeline:** `ThemeProfiles.qml` feeds three things:
  - `MatugenMonitor.qml` (GTK/Qt templates in `matugen-templates/`);
  - `ThemeColorMonitor.qml` (Hyprland borders, island accent);
  - small Python writers for kitty / VS Code / KDE / Obsidian.

See **`CLAUDE.md`** for the full architecture notes and the list of bug classes already hit (and
how to avoid them), and **`PROGRESS.md`** for the detailed change log.

## Development

There is no build step. Quickshell hot-reloads on save.

```bash
timeout 5 qs > /tmp/qs.log 2>&1; grep -E 'ReferenceError|TypeError|WARN scene' /tmp/qs.log   # headless check
qs list                      # running instance(s): make sure there's exactly one
qs log -i <id> -t 200        # live log of that instance
qs kill -i <id>; hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("qs"))'   # clean restart
```

The pure-JS logic (`CalcSmart.js`, `CalendarParse.js`, `ThemePalette.js`) runs under node once you
strip the `.pragma library` line.

## Credits

Inspired by:
- Apple's Dynamic Island / iOS / macOS design;
- [SilentSDDM](https://github.com/uiriansan/SilentSDDM) (the login flow);
- [QS-DFMID26](https://github.com/Legfena/QS-DFMID26) (the theme carousel idea).

SF Pro fonts © Apple (used locally). Icons: Adwaita, plus custom vector shapes.
