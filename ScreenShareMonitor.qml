import Quickshell.Services.Pipewire
import QtQuick

// Screen sharing through the portal (browser / Discord / OBS / Zoom …):
// xdg-desktop-portal-hyprland publishes each active screencast as a PipeWire
// video source and removes it when the share ends. Its node.name is
// "xdg-desktop-portal-hyprland" in xdph 1.4 (verified live with a Discord
// share); older builds used "xdph-streaming-<n>". Matched by name, since the
// webcam is a VideoSource node too.
// gpu-screen-recorder (Super+R) grabs the screen directly, not via the
// portal, so it never shows up here — RecordingBadge covers that.
Item {
    readonly property bool active: Pipewire.nodes.values.some(n =>
        n.type === PwNodeType.VideoSource
        && (n.name === "xdg-desktop-portal-hyprland" || n.name.startsWith("xdph-streaming")))
}
