#!/usr/bin/env python3
"""Patches the accent color inside VS Code's own
workbench.colorCustomizations block in settings.json — the user already
had a hand-set `"[Vira*]"` override block (their "Vira Carbon" theme)
using one accent hex (#80CBC4) repeated across ~40 keys, with a plain
"#000000" used for the handful of "foreground on top of the accent"
keys. This patches every non-#000000 value's base 6 hex digits to the
new accent, preserving whatever alpha suffix (if any) that key already
had — VS Code live-reloads colorCustomizations from settings.json with
no restart needed.

Only touches settings.json's `workbench.colorCustomizations` block;
every other setting (colorTheme, iconTheme, editor settings, etc.) is
read back byte-for-byte via json.load/json.dump, not regenerated.

Usage: vscode_write_theme.py <accent hex>
"""
import json
import os
import re
import sys

HEX_RE = re.compile(r"^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{0,2})$")


def main():
    if len(sys.argv) != 2:
        print("usage: vscode_write_theme.py <accent hex>", file=sys.stderr)
        sys.exit(1)

    accent = sys.argv[1].lstrip("#").lower()
    path = os.path.expanduser("~/.config/Code/User/settings.json")
    if not os.path.exists(path):
        return

    with open(path) as f:
        settings = json.load(f)

    customizations = settings.get("workbench.colorCustomizations", {})
    changed = False
    for scope_block in customizations.values():
        if not isinstance(scope_block, dict):
            continue
        for key, value in scope_block.items():
            if not isinstance(value, str):
                continue
            m = HEX_RE.match(value)
            if not m:
                continue
            base, alpha = m.group(1), m.group(2)
            if base.lower() == "000000":
                continue
            scope_block[key] = "#" + accent + alpha
            changed = True

    if changed:
        with open(path, "w") as f:
            json.dump(settings, f, indent=4)
            f.write("\n")


if __name__ == "__main__":
    main()
