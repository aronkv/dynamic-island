#!/usr/bin/env python3
"""Writes the color block of the Obsidian "Island" theme.

For every vault listed in ~/.config/obsidian/obsidian.json that has
.obsidian/themes/Island/theme.css, replaces the text between the
`/* ISLAND-COLORS:BEGIN */` and `/* ISLAND-COLORS:END */` markers (the rest
of the file is left alone; no markers → the file is skipped). Obsidian
live-reloads theme CSS, so no restart is needed.

Modes:
  follow <accent>  accent + slightly accent-tinted iOS surfaces
  static           iOS neutral surfaces + Obsidian's default purple accent

Usage: obsidian_write_theme.py follow "#rrggbb" | obsidian_write_theme.py static
"""
import json
import os
import re
import sys

BEGIN = "/* ISLAND-COLORS:BEGIN */"
END = "/* ISLAND-COLORS:END */"
HEX_RE = re.compile(r"^#?([0-9A-Fa-f]{6})$")

# Obsidian's default accent: hsl(254, 80%, 68%).
OBSIDIAN_PURPLE = "#8b6cef"


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexc(c):
    return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)


def mix(a, b, t):
    ca, cb = rgb(a), rgb(b)
    return hexc(tuple(x + (y - x) * t for x, y in zip(ca, cb)))


def luminance(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(v) for v in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def hsl(h):
    r, g, b = (v / 255 for v in rgb(h))
    mx, mn = max(r, g, b), min(r, g, b)
    l = (mx + mn) / 2
    if mx == mn:
        return 0, 0, round(l * 100)
    d = mx - mn
    s = d / (2 - mx - mn) if l > 0.5 else d / (mx + mn)
    if mx == r:
        hue = (g - b) / d + (6 if g < b else 0)
    elif mx == g:
        hue = (b - r) / d + 2
    else:
        hue = (r - g) / d + 4
    return round(hue * 60), round(s * 100), round(l * 100)


def csv(h):
    return ", ".join(str(v) for v in rgb(h))


def block(scheme, accent, tint):
    """CSS variables for one scheme ("dark"/"light")."""
    dark = scheme == "dark"
    if dark:
        base = {"primary": "#1c1c1e", "alt": "#232325", "secondary": "#121213",
                "secondary_alt": "#18181a", "border": "#2c2c2e", "border_hover": "#3a3a3c",
                "field": "#2c2c2e", "text": "#f5f5f7", "muted": "#98989d", "faint": "#636366",
                "code": "#141415"}
        green, red, orange, yellow, purple = "#30d158", "#ff453a", "#ff9f0a", "#ffd60a", "#bf5af2"
    else:
        base = {"primary": "#ffffff", "alt": "#f7f7f9", "secondary": "#f2f2f7",
                "secondary_alt": "#ebebf0", "border": "#e5e5ea", "border_hover": "#d1d1d6",
                "field": "#f2f2f7", "text": "#1d1d1f", "muted": "#6e6e73", "faint": "#aeaeb2",
                "code": "#f5f5f7"}
        green, red, orange, yellow, purple = "#34c759", "#ff3b30", "#ff9500", "#ffcc00", "#af52de"

    # A white/near-white accent (the monochrome themes) would vanish on the
    # light scheme — fall back to black there.
    if not dark and luminance(accent) > 0.7:
        accent = "#1d1d1f"
    if tint:
        surf = {k: mix(v, accent, 0.035 if k in ("primary", "alt", "secondary", "secondary_alt", "code") else 0.06)
                for k, v in base.items() if k not in ("text", "muted", "faint")}
        base.update(surf)

    on_accent = "#000000" if luminance(accent) > 0.45 else "#ffffff"
    hover = mix(accent, "#ffffff" if dark else "#000000", 0.15)
    h, s, l = hsl(accent)
    sel = "rgba(%s, %s)" % (csv(accent), "0.32" if dark else "0.22")

    v = {
        "--accent-h": h, "--accent-s": "%d%%" % s, "--accent-l": "%d%%" % l,
        "--color-accent": accent, "--color-accent-1": hover, "--color-accent-2": hover,
        "--island-surface-rgb": csv(base["secondary_alt"] if dark else base["primary"]),
        "--island-green": green,
        "--background-primary": base["primary"],
        "--background-primary-alt": base["alt"],
        "--background-secondary": base["secondary"],
        "--background-secondary-alt": base["secondary_alt"],
        "--background-modifier-border": base["border"],
        "--background-modifier-border-hover": base["border_hover"],
        "--background-modifier-border-focus": accent,
        "--background-modifier-hover": "rgba(%s, 0.06)" % ("255, 255, 255" if dark else "0, 0, 0"),
        "--background-modifier-active-hover": "rgba(%s, 0.16)" % csv(accent),
        "--background-modifier-form-field": base["field"],
        "--background-modifier-error": red,
        "--background-modifier-success": green,
        "--text-normal": base["text"],
        "--text-muted": base["muted"],
        "--text-faint": base["faint"],
        "--text-on-accent": on_accent,
        "--text-error": red,
        "--text-success": green,
        "--text-warning": orange,
        "--text-accent": accent,
        "--text-accent-hover": hover,
        "--text-selection": sel,
        "--text-highlight-bg": "rgba(%s, 0.35)" % csv(yellow),
        "--interactive-accent": accent,
        "--interactive-accent-rgb": csv(accent),
        "--interactive-accent-hover": hover,
        "--interactive-normal": base["field"],
        "--interactive-hover": base["border_hover"],
        "--link-color": accent,
        "--link-color-hover": hover,
        "--link-external-color": accent,
        "--link-unresolved-color": base["muted"],
        "--code-background": base["code"],
        "--code-normal": base["text"],
        "--code-comment": base["faint"],
        "--code-function": accent,
        "--code-keyword": purple,
        "--code-string": green if dark else "#248a3d",
        "--code-value": orange,
        "--code-property": base["muted"],
        "--blockquote-border-color": accent,
        "--checkbox-color": accent,
        "--checkbox-color-hover": hover,
        "--checkbox-marker-color": on_accent,
        "--checklist-done-color": base["faint"],
        "--tab-outline-color": "transparent",
        "--tab-background-active": base["primary"],
        "--titlebar-background": base["secondary"],
        "--titlebar-background-focused": base["secondary"],
        "--ribbon-background": base["secondary"],
        "--status-bar-background": base["secondary"],
        "--scrollbar-thumb-bg": base["border_hover"],
        "--scrollbar-active-thumb-bg": accent,
        "--graph-line": base["border_hover"],
        "--graph-node": base["muted"],
        "--graph-node-unresolved": base["faint"],
        "--graph-node-focused": accent,
        "--graph-node-tag": purple,
        "--graph-node-attachment": orange,
        "--callout-default": csv(accent),
        "--callout-note": csv(accent),
        "--callout-info": csv(accent),
        "--callout-todo": csv(accent),
        "--callout-tip": "100, 210, 255" if dark else "50, 173, 230",
        "--callout-success": csv(green),
        "--callout-question": csv(orange),
        "--callout-warning": csv(orange),
        "--callout-fail": csv(red),
        "--callout-error": csv(red),
        "--callout-bug": csv(red),
        "--callout-example": csv(purple),
        "--callout-quote": csv(base["muted"]),
    }
    lines = ["  %s: %s;" % (k, val) for k, val in v.items()]
    return ".theme-%s {\n%s\n}" % (scheme, "\n".join(lines))


def generate(mode, accent):
    if mode == "static":
        return "\n".join([
            "/* mode: static (Obsidian purple) */",
            block("dark", OBSIDIAN_PURPLE, False),
            block("light", OBSIDIAN_PURPLE, False),
        ])
    return "\n".join([
        "/* mode: follow (accent %s) */" % accent,
        block("dark", accent, True),
        block("light", accent, True),
    ])


def vault_themes():
    cfg = os.path.expanduser("~/.config/obsidian/obsidian.json")
    try:
        with open(cfg) as f:
            vaults = json.load(f).get("vaults", {})
    except (OSError, ValueError):
        return []
    out = []
    for v in vaults.values():
        p = os.path.join(v.get("path", ""), ".obsidian", "themes", "Island", "theme.css")
        if os.path.isfile(p):
            out.append(p)
    return out


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("follow", "static"):
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        sys.exit(1)
    mode = sys.argv[1]
    accent = OBSIDIAN_PURPLE
    if mode == "follow":
        m = HEX_RE.match(sys.argv[2] if len(sys.argv) > 2 else "")
        if not m:
            print("follow needs an accent like #rrggbb", file=sys.stderr)
            sys.exit(1)
        accent = "#" + m.group(1).lower()

    css = generate(mode, accent)
    for path in vault_themes():
        with open(path) as f:
            text = f.read()
        a, b = text.find(BEGIN), text.find(END)
        if a < 0 or b < a:
            continue
        new = text[:a + len(BEGIN)] + "\n" + css + "\n" + text[b:]
        if new != text:
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                f.write(new)
            os.replace(tmp, path)


if __name__ == "__main__":
    main()
