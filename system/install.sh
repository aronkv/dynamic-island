#!/bin/sh
# Installs the system tweaks for a smooth island (run with sudo):
#  - ananicy-cpp rule: qs as an interactive app (nice -4) instead of "Service" (nice 10)
#  - TLP drop-in: Balanced keeps EPP balance_performance + a higher iGPU floor on battery
# Undo: sudo rm /etc/ananicy.d/99-local/99-quickshell.rules /etc/tlp.d/10-island-smooth.conf
#       && sudo systemctl restart ananicy-cpp && sudo tlp start
set -e
dir=$(dirname "$(readlink -f "$0")")
install -Dm644 "$dir/99-quickshell.rules" /etc/ananicy.d/99-local/99-quickshell.rules
install -Dm644 "$dir/10-island-smooth.conf" /etc/tlp.d/10-island-smooth.conf
# The stock rule for "qs" lives in 00-default; comment it out so ours is the only one.
f=/etc/ananicy.d/00-default/DEs-and-WMs/dank-material-shell.rules
[ -f "$f" ] && sed -i 's|^{ "name": "qs", "type": "Service" }|# & (overridden by 99-local/99-quickshell.rules)|' "$f"
systemctl restart ananicy-cpp
tlp start >/dev/null
echo "qs nice now: $(ps -o ni= -p "$(pgrep -x qs | head -1)" 2>/dev/null || echo '?') (applies within ~15 s)"
