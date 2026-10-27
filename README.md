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

This repo is the `~/.config/quickshell` folder. The Hyprland, terminal and theming configs it
works with are in my dotfiles: [aronkv/dotfiles-hyprland](https://github.com/aronkv/dotfiles-hyprland).

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
- **Live activities, like iOS.** Timers, pomodoro and "rain in 15 min" live in the idle pill next
  to the clock; screen recording and the battery get their own floating capsules beside the pill.
  Tap one for its controls.
- **A calculator that thinks.**
  - It solves linear, quadratic, quartic and trig equations and inequalities in `x`, and graphs them
    with the roots and the shaded solution set.
  - It converts currencies (live ECB rates), units and dates (`days until christmas`).
  - It uses a hand-written recursive-descent parser. There is no `eval`, so there is no injection
    surface.
- **Honest privacy badges.** The mic/camera indicators ignore the island's own cava visualizer and
  the screen recorder's system-audio tap, so they only light up for a real microphone. A blue badge
  shows while an app (Discord, a browser, OBS) is screen sharing through the portal.
- **Escalating low-battery care**, each as a compact pill (what happened + the level, like the
  charging pill):
  - **20 %** — automatic Low Power (which also dims the display a little): "Low Power On", yellow.
  - **10 %** — "Battery Low", orange, with a Low Power nudge.
  - **5 %** — "Connect Charger", red, the level pulses.
  - **1 %** — "Almost Empty", faster pulse.
  - **≤ 10 %** — the battery badge left of the pill always shows, with the minutes left.
- **Confirm-to-run power menu.** Lock, Sleep, Log Out, Restart, Shut Down and BIOS are numbered 1–6.
  The risky ones open into a red confirm pill first, so a stray tap never shuts anything down.
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
  stuck and the top ones don't jump. The T480's brightness keys never report a held key (each event
  is press + release at once, repeated ~520 ms then every ~260 ms while held), so the island
  recognises a hold by that cadence and ramps fast itself; taps stay one level each.
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
- **Idle pill** — clock; while something plays, one of three now-playing layouts: *album art*
  ([cover] [clock] [cava]), *track title* ([cover] [title] [cava]) or *lyrics* (just the current
  synced line, over cava bars in the cover's color — fixed-size bars, more of them on longer lines; the pill springs to each line's
  width, long lines scroll, ♪ in instrumental gaps). The small cava bars use the album cover's
  color. Unread-notification dot. Floating badges beside it (inset from the screen edge):
  charging bolt or battery level on the left (no background, with a soft shadow like the bolt;
  the level fill and color follow the charge; the percentage can be off, beside the glyph or
  inside a larger glyph, iOS 16 style), screen recording; tray, screen
  sharing, mic/camera on the right.
  Optional thin **strip mode**.
- **Two looks:**
  - solid black;
  - with *Liquid Glass* on, a black body with a frosted, gradient glass rim (hyprglass),
    macOS-Tahoe style. The same toggle applies glass to all windows; terminals stay black thanks to
    a neutral tint.
- **Transient OSDs** — volume, brightness, Caps Lock, mic mute, screenshot preview, LocalSend
  transfers, notifications.
- **Live activities** — screen recording (pulsing red dot + elapsed time) as a capsule left of
  the pill; inside the pill, at its left:
  - timer / stopwatch / pomodoro (progress ring + time);
  - "rain soon" (Open-Meteo 15-minute data).
  
  Tap one for its controls.
- **Charging** — when you plug in, the pill reads "Charging" with the percentage while a green
  light runs around its outline, ears included.
- **Ethernet** — plugging in a network cable shows a compact pill: the wired glyph, "Ethernet" and
  the negotiated link speed ("1 Gbps"); pulling it shows "Disconnected".
- **Bluetooth** — when a device connects (e.g. headphones reconnecting on their own), a compact pill
  shows its icon, name and battery. Skipped while the Bluetooth panel is open.
- **Low battery** — compact pills at 20 / 10 / 5 / 1 % (see above).
- **Workspaces** — on every switch, dots appear inside the pill and the active one moves with an iOS
  page-control "stretch".

### Panels
| Panel | Highlights |
|---|---|
| **Music** | Blurred album-art ambient background, 20-band cava visualizer in the cover's color, big cover, scrub-able progress, Apple-Music-style synced lyrics with soft blurred edges. |
| **Overview** | Clock, Wi-Fi/Ethernet, Bluetooth, battery, Liquid Glass toggle, shortcuts to every panel. |
| **Battery** | Monochrome, with a two-tone charging bolt (black over the fill, white over the empty part). Per-pack level, health and cycle count straight from sysfs, capacity vs. design. *Charging at* = watts going into the battery right now (vs. the USB-C charger's rating); *Using* = the drain on battery. Power profiles via tlp-pd; automatic Low Power at ≤ 20 % (a manual change is respected until you plug in again). |
| **Wi-Fi / Bluetooth** | Device cards, password entry, details, forget/disconnect, pairing; **share the Wi-Fi password as a QR code** (click to enlarge). The connected network's icon carries its Wi-Fi generation (4 / 5 / 6 / 6E / 7, from `iw`'s negotiated link). |
| **Weather** | Open-Meteo: animated sky backdrop, 24-hour temperature curve, 7-day range bars, feels-like / humidity / wind / UV / sunrise-sunset / pressure tiles, rain alert. **Location by Wi-Fi** (`wifi_locate.py`): nearby access points are looked up via Apple's Wi-Fi positioning service (BeaconDB fallback) and named via OpenStreetMap, accurate to ~20 m, anywhere. Falls back to IP geolocation (city-level at best) when Wi-Fi is off; a manual city can be set in Settings. Re-resolved every 30 min. Note: the nearby access points' MAC addresses are sent to Apple. |
| **Calculator** | Opens ready to type ("Challenge me…"). Input and result cards, animated result, chips (Copy, Use as ans, one per root). **Equations & inequalities** with a graph (hover crosshair with x/y readout). Currency, units, dates. History side sheet (Ctrl+H). **Help sheet** (`?`) with clickable examples. |
| **Launcher** | Fuzzy app search (most-launched first), starred favorites as tiles. **Files** with real thumbnails (Ctrl+Enter opens the folder). **Emoji** (`:fire`, Enter copies). **Google search** (`?query`). Web addresses (`youtube.com`) open directly. Commands (`timer 5m`, `stopwatch`, `pomodoro`, `record`). Inline math. |
| **Notifications** | iOS-style banners: the app's own icon top-left (CachyOS updates get the CachyOS logo), title + time, two lines of body, and the picture (album art, screenshot…) as a thumbnail. History (SUPER+N): last 100 (survive restarts), grouped by app with its icon, relative times, click to activate, ✕ on hover / swipe to dismiss, clear per app / all. |
| **System** | Uptime + load average; tiles with 60-second sparklines for CPU (total, per-core, clock), GPU (Intel i915 busy % + MHz), memory, temperature + fan, network ↓/↑ and battery power draw; disk usage + read/write throughput; top processes with CPU bars. |
| **Clipboard** | cliphist history with image thumbnails. |
| **Calendar** | Month grid + reminders with natural-language quick-add ("tomorrow 9:00 dentist"). |
| **Theme** | macOS-Appearance-style picker with a live preview (wallpaper, mini island, mini terminal), presets + *Dynamic* (matugen from the wallpaper). |
| **Wallpaper** | Keyboard-navigable grid, applies via hyprpaper. |
| **Settings** | iOS-style grouped sections in two columns, monochrome. Each section header folds its group (the open/closed state is kept while the session runs, so it reopens as you left it). **Appearance**: Liquid Glass, strip mode. **Display**: Night Shift via hyprsunset (sunset→sunrise or always, warmth slider), Reduce motion, Obsidian follows theme. **Now playing**: album art / track title / lyrics. **Screen recording**: resolution, fps, constant bitrate (20 / 40 / 80 Mbps; MP4 with H.264 on the GPU + AAC, constant frame rate, so every player and editor opens it), system audio, microphone, cursor. **Battery**: automatic Low Power Mode at 20 % (on/off), badge outside the pill, percentage off / beside / inside the icon. **Notifications & privacy**: Do Not Disturb, mic/camera indicators. **Calculator**: history. **Weather**: rain alert, manual location. |
| **Tray** | System-tray host (StatusNotifierItem) for Discord, Steam etc.: a 2×2-dot badge next to the pill while any app sits in the tray; icon grid, click opens the app, right click shows its own menu. **SUPER+A** (`qs ipc call tray toggle`). |
| **Shortcuts** | Live cheat sheet generated from `keybindings.lua`. |
| **Power menu** | Lock · Sleep · Log Out · Restart · Shut Down · BIOS (restart into firmware setup). Click or press 1–6; Lock and Sleep run at once, the others open into a red "Restart?" pill and run on a second click / Enter (they fold back after 3 s). |

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
Put **SF Pro** (Display, Text and Rounded `.otf` files from
[Apple's developer site](https://developer.apple.com/fonts/)) in `~/.local/share/fonts/SF-Pro/`,
then run `fc-cache -f`. Apple doesn't allow redistributing them, so they are **not in this repo**;
the SDDM theme also needs a copy in `sddm/island/fonts/`.

### 3. The shell itself
```bash
git clone https://github.com/aronkv/dynamic-island.git ~/.config/quickshell   # move an existing one aside first
qs                                                                         # first run in a terminal, to see the log
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
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs ipc call brightness press up"),   { locked = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs ipc call brightness press down"), { locked = true })
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
  1. `obsidian_write_theme.py` installs `obsidian/Island/` into every vault listed in
     `~/.config/obsidian/obsidian.json` (new vaults too) and rewrites its color block on every
     theme change.
  2. Pick *Island* in Obsidian → Appearance; the script never switches the theme for you.
  4. `obsidian/ThinkRed/` is a second, static theme (black-grey with ThinkPad TrackPoint red).
- **Spotify:** plain spicetify + Marketplace; the island doesn't theme it.
- **Media apps:** `sudo pacman -S mpv mpd rmpc swayimg && systemctl --user enable --now mpd`.
  The uosc UI for mpv isn't in the repo; install it with
  `curl -fsSL https://github.com/tomasklaen/uosc/releases/latest/download/uosc.zip -o /tmp/uosc.zip && unzip -o /tmp/uosc.zip -d ~/.config/mpv`.

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
| `SUPER + A` | Tray apps (Discord, Steam…) |
| `SUPER + SHIFT + V` | Clipboard |
| `SUPER + I` | Settings |
| `SUPER + SHIFT + T` | Theme |
| `SUPER + SHIFT + W` | Wallpaper |
| `SUPER + H` | Keyboard shortcuts |
| `SUPER + N` | Notification history |
| `SUPER + R` | Start / stop screen recording (`~/Videos/Recordings`) |
| `SUPER + M` | System monitor |
| `SUPER + Escape` | Power menu (then `1`–`6`) |
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
| `brightness` | `press <up\|down>` (key event; hold detection), `up`, `down` |
| `weather` | `preview <code> <day>` (`-1` resets) |

Run `qs ipc show` for the live list.

## Files it keeps

Relative to `~/.config/quickshell/` unless the path says otherwise.

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
  weather (Wi-Fi location via `wifi_locate.py`, IP fallback), clipboard, notifications, activities
  and LocalSend.
- **Panels** (`*Panel.qml`) live in `QuickOverviewPanel.qml` (crossfading sub-views) or directly in the
  island (launcher, power, clipboard, notifications, system, activity).
- **Shared pieces:** `Theme.qml` (design tokens, reduce motion), `PanelHeader.qml`,
  `ToggleSwitch.qml`, `CalcEngine.qml` + `CalcSmart.js` (parser, no `eval`), `ThemePalette.js`,
  `BoltShape` / `MicShape` / `VideoShape`.
- **Theming pipeline:** `ThemeProfiles.qml` feeds three things:
  - `MatugenMonitor.qml` (GTK/Qt templates in `matugen-templates/`);
  - `ThemeColorMonitor.qml` (Hyprland borders, island accent);
  - small Python writers for kitty / VS Code / KDE / Obsidian.

## Development

There is no build step. Quickshell hot-reloads on save.

```bash
timeout 5 qs > /tmp/qs.log 2>&1; grep -E 'ReferenceError|TypeError|WARN scene' /tmp/qs.log   # headless check
qs list                      # running instance(s): make sure there's exactly one
qs log -i <id> -t 200        # live log of that instance
qs kill -i <id>; hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("qs"))'   # clean restart
```

The pure-JS logic (`CalcSmart.js`, `CalendarParse.js`, `ThemePalette.js`) runs under node once you
strip the `.pragma library` line; `node tests/logic.js` checks the date parsing.

## Credits

Inspired by:
- Apple's Dynamic Island / iOS / macOS design;
- [SilentSDDM](https://github.com/uiriansan/SilentSDDM) (the login flow);
- [QS-DFMID26](https://github.com/Legfena/QS-DFMID26) (the theme carousel idea);
- [DynamicGlacier](https://github.com/mavxa/DynamicGlacier), the main design reference for the
  island: the idle pill layout, the media card, the Bluetooth panel's sizing and the wallpaper
  picker;
- [impasto](https://github.com/andreumassanet/impasto) (the "whole desktop follows the wallpaper"
  idea): how the accent color is picked from the wallpaper, and saving themes as named profiles.

SF Pro fonts © Apple (used locally). Icons: Adwaita, plus custom vector shapes.
