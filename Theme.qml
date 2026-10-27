pragma Singleton

import Quickshell
import QtQuick

// Shared design tokens (Apple-style). New and reworked UI should read from
// here instead of hardcoding values; older panels migrate as they're touched.
Singleton {
    // Typography
    readonly property string font: "SF Pro Display"
    readonly property string fontText: "SF Pro Text"
    readonly property string fontRounded: "SF Pro Rounded"

    // Colors (iOS dark palette)
    readonly property color bg: "#000000"
    readonly property color card: "#1c1c1e"
    readonly property color cardElevated: "#2c2c2e"
    readonly property color separator: "#38383a"
    readonly property color text: "#ffffff"
    readonly property color green: "#32d74b"
    readonly property color red: "#ff453a"
    readonly property color orange: "#ff9f0a"
    readonly property color yellow: "#ffd60a"
    readonly property color blue: "#0a84ff"

    // Radii
    readonly property int radiusSmall: 8
    readonly property int radiusMedium: 12

    // Motion. The island morph's timings live in DynamicIsland
    // (notch.morphDuration / morphEasing, keyed on notch.morphKind).
    readonly property int contentScaleDuration: 380

    // Settings → Reduce motion (bound from DynamicIsland to settingsStore):
    // no springs/overshoot, no slides, short plain fades, no ambient loops.
    property bool reduceMotion: false
}
