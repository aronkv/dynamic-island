import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

Rectangle {
    id: badge

    property bool active: false
    property string icon: ""
    property color iconColor: "#ffffff"
    // Default matches this component's original fixed size — the only two
    // usages in the project (mic/camera in DynamicIsland.qml's
    // idleBadgeRight) now override this to sit flush with the pill's
    // height, but nothing else depends on the old hardcoded 28.
    property int size: 28
    property color bgColor: "#000000"
    // "mic" | "video": draw the filled SF-style vector glyph (MicShape /
    // VideoShape) instead of the icon-theme icon.
    property string shape: ""

    width: size
    height: size
    radius: width / 2
    color: bgColor

    opacity: active ? 1 : 0
    scale: active ? 1 : 0.7
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    MicShape {
        anchors.centerIn: parent
        visible: badge.shape === "mic"
        width: Math.round(badge.size * 0.5)
        height: width
        color: badge.iconColor
    }
    VideoShape {
        anchors.centerIn: parent
        visible: badge.shape === "video"
        width: Math.round(badge.size * 0.5)
        height: width
        color: badge.iconColor
    }

    IconImage {
        id: iconImg
        anchors.centerIn: parent
        // Rounded to a whole pixel and paired with an explicit matching
        // sourceSize + smooth/mipmap — a fractional implicitSize (e.g. the
        // old size*16/28 with size=44 landed on 25.142857...) combined with
        // no explicit sourceSize left the icon provider rasterizing at its
        // own default resolution and then point-scaling the result to a
        // mismatched fractional box, which is what made mic/camera look
        // distorted once the badge grew from 28 to 44 (the smaller default
        // size never made this visible).
        implicitSize: Math.round(size * 16 / 28)
        smooth: true
        mipmap: true
        source: badge.icon !== "" ? "image://icon/" + badge.icon : ""
        visible: false
        // Used as MultiEffect's maskSource below — that needs a rendered
        // texture to sample, which only exists if this item is layered
        // (visible:false alone isn't enough; without this the mask has
        // nothing to read and every icon using this pattern renders blank).
        layer.enabled: true
    }

    // Flat-fill via alpha mask instead of colorization — colorization
    // blends the target color proportional to the source icon's own
    // luminance rather than replacing it outright, so a dark icon-theme
    // glyph recolored this way never reaches the literal target color
    // (confirmed and fixed the same way in IslandHeaderRow.qml's RowIcon
    // this same session). A flat Rectangle masked by the icon's own alpha
    // shape guarantees every visible pixel is the exact iconColor.
    Rectangle {
        id: iconFill
        anchors.fill: iconImg
        color: badge.iconColor
        visible: false
    }

    MultiEffect {
        visible: badge.shape === ""
        anchors.fill: iconImg
        source: iconFill
        maskEnabled: true
        maskSource: iconImg
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.0
        maskThresholdMax: 1.0
        maskSpreadAtMax: 0.0
    }
}
