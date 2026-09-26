import QtQuick
import QtQuick.Shapes

// Animated backdrop behind the Weather panel, driven by the open-meteo
// weather code + day/night: a sky gradient that fades to black at the
// bottom (the island stays black under the lists), plus scene layers —
// twinkling stars and a moon glow at night, a pulsing sun glow by day,
// drifting soft clouds, falling rain streaks, snowflakes, fog bands and
// lightning flashes. Everything animates only while `active`.
// Random positions are fixed per element (fx/fy fractions) — never
// `Math.random() * width` in a binding, which re-rolls on every resize.
Item {
    id: root
    property int code: 0
    property bool isDay: true
    property bool active: false
    clip: true

    // Scene from the WMO code.
    readonly property string scene: {
        if (code === 0) return "clear"
        if (code === 1 || code === 2) return "partly"
        if (code === 3) return "cloudy"
        if (code === 45 || code === 48) return "fog"
        if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) return "rain"
        if ((code >= 71 && code <= 77) || code === 85 || code === 86) return "snow"
        if (code === 95 || code === 96 || code === 99) return "storm"
        return "cloudy"
    }
    readonly property color skyTarget: {
        const d = isDay
        switch (scene) {
            case "clear": return d ? "#2a6fc4" : "#101a44"
            case "partly": return d ? "#3a6ea8" : "#141c3c"
            case "cloudy": return d ? "#4a5666" : "#1a1e28"
            case "fog": return d ? "#5a5d63" : "#23252a"
            case "rain": return d ? "#34455a" : "#141c28"
            case "snow": return d ? "#5d6b80" : "#1f2636"
            case "storm": return d ? "#2c2a44" : "#16132a"
        }
        return "#1a1e28"
    }
    property color skyTop: skyTarget
    Behavior on skyTop { ColorAnimation { duration: 800 } }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.skyTop }
            GradientStop { position: 0.45; color: Qt.darker(root.skyTop, 2.2) }
            GradientStop { position: 0.8; color: "#000000" }
        }
    }

    // ── Stars (night, clear/partly) ──────────────────────────────────
    Repeater {
        model: !root.isDay && (root.scene === "clear" || root.scene === "partly") ? 46 : 0
        Rectangle {
            readonly property real size: 1 + Math.random() * 1.6
            readonly property real fx: Math.random()
            readonly property real fy: Math.random()
            x: fx * root.width
            y: fy * root.height * 0.5
            width: size
            height: size
            radius: size / 2
            color: "#ffffff"
            opacity: 0.3
            SequentialAnimation on opacity {
                running: root.active
                loops: Animation.Infinite
                PauseAnimation { duration: Math.random() * 3000 }
                NumberAnimation { to: 0.9; duration: 900 + Math.random() * 1500; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.2; duration: 900 + Math.random() * 1500; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── Sun / moon glow ──────────────────────────────────────────────
    component Glow: Shape {
        id: glow
        property color color: "#ffffff"
        property real strength: 0.5
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: glow.width / 2; centerY: glow.height / 2
                centerRadius: glow.width / 2
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: Qt.rgba(glow.color.r, glow.color.g, glow.color.b, glow.strength) }
                GradientStop { position: 0.35; color: Qt.rgba(glow.color.r, glow.color.g, glow.color.b, glow.strength * 0.35) }
                GradientStop { position: 1.0; color: Qt.rgba(glow.color.r, glow.color.g, glow.color.b, 0) }
            }
            PathAngleArc {
                centerX: glow.width / 2; centerY: glow.height / 2
                radiusX: glow.width / 2; radiusY: glow.height / 2
                startAngle: 0; sweepAngle: 360
            }
        }
    }

    Glow {
        id: sunGlow
        visible: root.isDay && (root.scene === "clear" || root.scene === "partly")
        x: root.width - width * 0.7
        y: 70 - height / 2
        width: 300
        height: 300
        color: "#ffd479"
        strength: 0.7
        SequentialAnimation on scale {
            running: root.active && sunGlow.visible
            loops: Animation.Infinite
            NumberAnimation { to: 1.08; duration: 3500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.96; duration: 3500; easing.type: Easing.InOutSine }
        }
    }
    Glow {
        visible: !root.isDay && (root.scene === "clear" || root.scene === "partly")
        x: root.width - 60 - width / 2
        y: 118 - height / 2
        width: 150
        height: 150
        color: "#dfe8ff"
        strength: 0.28
        // Moon disc.
        Rectangle {
            anchors.centerIn: parent
            width: 26; height: 26; radius: 13
            color: "#eef2ff"
            opacity: 0.92
            // A couple of soft "maria" for texture.
            Rectangle { x: 6; y: 7; width: 7; height: 6; radius: 3; color: "#d3dbef" }
            Rectangle { x: 14; y: 14; width: 6; height: 5; radius: 2.5; color: "#d8dff1" }
        }
    }

    // ── Clouds ───────────────────────────────────────────────────────
    readonly property int cloudCount: {
        switch (scene) {
            case "partly": return 3
            case "cloudy": case "rain": case "storm": return 5
            case "snow": return 4
            case "fog": return 0
        }
        return 0
    }
    Repeater {
        model: root.cloudCount
        Glow {
            id: cloud
            required property int index
            readonly property real w: 200 + Math.random() * 180
            width: w
            height: w * 0.45
            readonly property real fy: Math.random()
            y: -height * 0.3 + fy * root.height * 0.22
            color: root.scene === "storm" ? "#9a95b8" : root.isDay ? "#ffffff" : "#a9b3c9"
            strength: root.scene === "partly" ? 0.16 : 0.22
            readonly property real phase: Math.random()
            property real drift: 0
            x: -width + (root.width + width) * ((drift + phase) % 1)
            NumberAnimation on drift {
                running: root.active
                loops: Animation.Infinite
                from: 0; to: 1
                duration: 60000 + Math.random() * 40000
            }
        }
    }

    // ── Fog bands ────────────────────────────────────────────────────
    Repeater {
        model: root.scene === "fog" ? 4 : 0
        Rectangle {
            required property int index
            width: root.width * 1.6
            height: 46
            y: 30 + index * 70
            radius: 23
            opacity: 0.1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.5; color: "#ffffff" }
                GradientStop { position: 1.0; color: "transparent" }
            }
            SequentialAnimation on x {
                running: root.active
                loops: Animation.Infinite
                NumberAnimation { from: -root.width * 0.6; to: 0; duration: 14000 + index * 3000; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0; to: -root.width * 0.6; duration: 14000 + index * 3000; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── Rain ─────────────────────────────────────────────────────────
    Repeater {
        model: root.scene === "rain" || root.scene === "storm" ? (root.code >= 51 && root.code <= 57 ? 30 : 70) : 0
        Rectangle {
            id: drop
            readonly property real len: 10 + Math.random() * 12
            width: 1.3
            height: len
            radius: 0.6
            rotation: 12
            color: "#cfe3ff"
            opacity: 0.18 + Math.random() * 0.25
            readonly property real fx: Math.random()
            readonly property real fy: Math.random()
            x: fx * (root.width + 40)
            y: -len
            NumberAnimation on y {
                running: root.active
                loops: Animation.Infinite
                from: -drop.len - drop.fy * root.height
                to: root.height
                duration: 700 + Math.random() * 500
            }
        }
    }

    // ── Snow ─────────────────────────────────────────────────────────
    Repeater {
        model: root.scene === "snow" ? 45 : 0
        Rectangle {
            id: flake
            readonly property real size: 2 + Math.random() * 3
            readonly property real fx: Math.random()
            readonly property real fy: Math.random()
            readonly property real baseX: fx * root.width
            property real sway: 0
            width: size
            height: size
            radius: size / 2
            color: "#ffffff"
            opacity: 0.35 + Math.random() * 0.45
            x: baseX + Math.sin(sway) * 12
            NumberAnimation on y {
                running: root.active
                loops: Animation.Infinite
                from: -10 - flake.fy * root.height
                to: root.height
                duration: 6000 + Math.random() * 5000
            }
            NumberAnimation on sway {
                running: root.active
                loops: Animation.Infinite
                from: 0; to: Math.PI * 2
                duration: 3000 + Math.random() * 3000
            }
        }
    }

    // ── Lightning ────────────────────────────────────────────────────
    Rectangle {
        id: flash
        anchors.fill: parent
        color: "#dcd8ff"
        opacity: 0
        visible: root.scene === "storm"
    }
    Timer {
        running: root.active && root.scene === "storm"
        repeat: true
        interval: 5000
        onTriggered: { interval = 3500 + Math.random() * 6000; strike.restart() }
    }
    SequentialAnimation {
        id: strike
        NumberAnimation { target: flash; property: "opacity"; to: 0.35; duration: 60 }
        NumberAnimation { target: flash; property: "opacity"; to: 0.05; duration: 90 }
        NumberAnimation { target: flash; property: "opacity"; to: 0.25; duration: 50 }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 500; easing.type: Easing.OutCubic }
    }
}
