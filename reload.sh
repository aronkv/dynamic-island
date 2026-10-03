#!/usr/bin/env bash
# Restart the Dynamic Island (Quickshell).
#
# Run manually when needed; IconCacheMonitor.qml also calls it after pacman
# installs new app icons, since Quickshell caches icon lookups per process.
set -u

pkill -x qs
for _ in {1..20}; do
    pgrep -x qs >/dev/null || break
    sleep 0.1
done

# Launch through Hyprland, like autostart.lua, so the island isn't a child of
# this script and inherits the session environment.
if [[ -z ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -n1)
    export HYPRLAND_INSTANCE_SIGNATURE
fi
hyprctl eval 'hl.dispatch(hl.dsp.exec_cmd("qs"))' >/dev/null
