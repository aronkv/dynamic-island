#!/usr/bin/env python3
"""Patches the color sections of ~/.config/kdeglobals AND the actual
named KDE color-scheme file it points to, so KDE Frameworks apps
(Dolphin, etc.) actually follow the Theme panel — confirmed live that
`[General] ColorScheme=<Name>` in kdeglobals makes KColorScheme resolve
and read `~/.local/share/color-schemes/<Name>.colors` (or the matching
file under /usr/share/color-schemes/) for the REAL color values;
kdeglobals' own inline [Colors:*] sections are only a fallback used when
no such named scheme file exists, so patching kdeglobals alone silently
had no visible effect the first time this was tried.

Patches both files in place via configparser (preserves every unrelated
section — Icons, KDE, WM label fields, ColorEffects, comments a plain
INI writer would drop, etc.) rather than generating either from scratch.

Usage: kdeglobals_write_theme.py <background hex> <foreground hex> <accent hex>
"""
import configparser
import os
import sys


def hex_to_rgb_string(hexval):
    hexval = hexval.lstrip("#")
    r, g, b = (int(hexval[i:i + 2], 16) for i in (0, 2, 4))
    return f"{r},{g},{b}"


SURFACE_SECTIONS = [
    "Colors:View", "Colors:Window", "Colors:Button",
    "Colors:Tooltip", "Colors:Header", "Colors:Complementary",
    "Colors:Header][Inactive",
]


def patch_colors_file(path, bg, fg, accent):
    config = configparser.ConfigParser(strict=False)
    config.optionxform = str  # preserve KDE's mixed-case key names as-is
    if os.path.exists(path):
        config.read(path)

    for section in SURFACE_SECTIONS:
        if not config.has_section(section):
            config.add_section(section)
        config.set(section, "BackgroundNormal", bg)
        config.set(section, "ForegroundNormal", fg)
        config.set(section, "DecorationFocus", accent)
        config.set(section, "DecorationHover", accent)
        config.set(section, "ForegroundActive", accent)

    if not config.has_section("Colors:Selection"):
        config.add_section("Colors:Selection")
    config.set("Colors:Selection", "BackgroundNormal", accent)
    config.set("Colors:Selection", "ForegroundNormal", fg)
    config.set("Colors:Selection", "DecorationFocus", accent)
    config.set("Colors:Selection", "DecorationHover", accent)
    config.set("Colors:Selection", "ForegroundActive", fg)

    if not config.has_section("WM"):
        config.add_section("WM")
    config.set("WM", "activeBackground", bg)
    config.set("WM", "activeForeground", fg)
    config.set("WM", "inactiveBackground", bg)
    config.set("WM", "inactiveForeground", fg)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        config.write(f, space_around_delimiters=False)
    return config


def main():
    if len(sys.argv) != 4:
        print("usage: kdeglobals_write_theme.py <bg hex> <fg hex> <accent hex>", file=sys.stderr)
        sys.exit(1)

    bg = hex_to_rgb_string(sys.argv[1])
    fg = hex_to_rgb_string(sys.argv[2])
    accent = hex_to_rgb_string(sys.argv[3])

    kdeglobals_path = os.path.expanduser("~/.config/kdeglobals")
    kdeglobals = patch_colors_file(kdeglobals_path, bg, fg, accent)

    scheme_name = None
    if kdeglobals.has_option("General", "ColorScheme"):
        scheme_name = kdeglobals.get("General", "ColorScheme")
    if scheme_name:
        scheme_path = os.path.expanduser(f"~/.local/share/color-schemes/{scheme_name}.colors")
        if not os.path.exists(scheme_path):
            # Fall back to copying the system-provided scheme once, so
            # there's something to patch — matches what KColorScheme
            # itself would have resolved to before this ever ran.
            system_path = f"/usr/share/color-schemes/{scheme_name}.colors"
            if os.path.exists(system_path):
                os.makedirs(os.path.dirname(scheme_path), exist_ok=True)
                with open(system_path) as src, open(scheme_path, "w") as dst:
                    dst.write(src.read())
        if os.path.exists(scheme_path):
            patch_colors_file(scheme_path, bg, fg, accent)


if __name__ == "__main__":
    main()
