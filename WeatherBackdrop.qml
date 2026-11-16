import QtQuick
import QtQuick.Shapes

// Animated backdrop behind the Weather panel, driven by the open-meteo
// weather code + day/night: a sky gradient that fades to black at the
// bottom (the island stays black under the lists), plus scene layers —
// twinkling stars and a moon at night, a layered sun glow by day,
// drifting puff-cluster clouds (two parallax layers), near/far rain
// streaks, snowflakes, fog bands and lightning flashes. Everything
// animates only while `active`.
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
    // [zenith, horizon] per scene.
    readonly property var skyTarget: {
        const d = isDay
        switch (scene) {
            case "clear": return d ? ["#1c5fc0", "#4a93dc"] : ["#060b24", "#1a2556"]
            case "partly": return d ? ["#2b62a6", "#5c8fc4"] : ["#0a1028", "#1f2a52"]
            case "cloudy": return d ? ["#3d4a5c", "#6b7787"] : ["#101319", "#262c38"]
            case "fog": return d ? ["#545961", "#7e8389"] : ["#18191d", "#2e3036"]
            case "rain": return d ? ["#28374a", "#4a5d74"] : ["#0b1019", "#1d2736"]
            case "snow": return d ? ["#506078", "#8796ab"] : ["#141a28", "#2b3448"]
            case "storm": return d ? ["#1f1d36", "#3d3a5c"] : ["#0c0a1c", "#221d3a"]
        }
        return ["#101319", "#262c38"]
    }
    property color skyTop: skyTarget[0]
    property color skyHorizon: skyTarget[1]
    Behavior on skyTop { ColorAnimation { duration: 800 } }
    Behavior on skyHorizon { ColorAnimation { duration: 800 } }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.skyTop }
            GradientStop { position: 0.32; color: root.skyHorizon }
            GradientStop { position: 0.55; color: Qt.darker(root.skyHorizon, 2.4) }
            GradientStop { position: 0.78; color: "#000000" }
        }
    }
    // Scene layers live in the sky part and fade out above the cards.
    readonly property real skyDepth: height * 0.45

    // ── Stars (night, clear/partly) ──────────────────────────────────
    Repeater {
        model: !root.isDay && (root.scene === "clear" || root.scene === "partly") ? 46 : 0
        Rectangle {
            readonly property real size: 1 + Math.random() * 1.6
            readonly property real fx: Math.random()
            readonly property real fy: Math.random()
            x: fx * root.width
            y: fy * root.skyDepth
            width: size
            height: size
            radius: size / 2
            color: "#ffffff"
            property real twinkle: 0.3
            opacity: twinkle * (1 - fy * 0.8)
            SequentialAnimation on twinkle {
                running: root.active && !Theme.reduceMotion
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

    Item {
        id: sunGlow
        visible: root.isDay && (root.scene === "clear" || root.scene === "partly")
        x: root.width * 0.72 - width / 2
        y: 10 - height / 2
        width: 420
        height: 420
        Glow { anchors.fill: parent; color: "#ffe2a8"; strength: root.scene === "partly" ? 0.22 : 0.32 }
        Glow { anchors.centerIn: parent; width: 150; height: 150; color: "#fff1c9"; strength: 0.55 }
        Glow { anchors.centerIn: parent; width: 46; height: 46; color: "#ffffff"; strength: 1 }
        SequentialAnimation on scale {
            running: root.active && !Theme.reduceMotion && sunGlow.visible
            loops: Animation.Infinite
            NumberAnimation { to: 1.04; duration: 4500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.98; duration: 4500; easing.type: Easing.InOutSine }
        }
    }
    Glow {
        visible: !root.isDay && (root.scene === "clear" || root.scene === "partly")
        x: root.width * 0.74 - width / 2
        y: 46 - height / 2
        width: 220
        height: 220
        color: "#c9d6ff"
        strength: 0.22
        Rectangle {
            anchors.centerIn: parent
            width: 28; height: 28; radius: 14
            opacity: 0.85
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#ffffff" }
                GradientStop { position: 0.6; color: "#e6ebf8" }
                GradientStop { position: 1.0; color: "#aeb8d2" }
            }
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
    readonly property color cloudColor: scene === "storm" ? "#8f8aad" : isDay ? "#ffffff" : "#9aa5bd"
    Repeater {
        model: root.cloudCount * 2
        Item {
            id: cloud
            required property int index
            readonly property bool front: index % 2 === 1      // nearer: bigger, brighter, faster
            readonly property real w: (front ? 240 : 180) + Math.random() * 140
            width: w
            height: w * 0.5
            readonly property real fy: Math.random()
            y: -height * 0.35 + fy * root.skyDepth * (front ? 0.45 : 0.3)
            opacity: (root.scene === "partly" ? 0.7 : 1) * (front ? 1 : 0.6)
            readonly property real phase: Math.random()
            property real drift: 0
            x: -width + (root.width + width) * ((drift + phase) % 1)
            Glow { x: 0; y: parent.height * 0.3; width: parent.width * 0.55; height: parent.height * 0.7; color: root.cloudColor; strength: 0.2 }
            Glow { x: parent.width * 0.25; y: 0; width: parent.width * 0.5; height: parent.height * 0.9; color: root.cloudColor; strength: 0.24 }
            Glow { x: parent.width * 0.45; y: parent.height * 0.25; width: parent.width * 0.55; height: parent.height * 0.75; color: root.cloudColor; strength: 0.2 }
            NumberAnimation on drift {
                running: root.active && !Theme.reduceMotion
                loops: Animation.Infinite
                from: 0; to: 1
                duration: (cloud.front ? 55000 : 95000) + Math.random() * 30000
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
                running: root.active && !Theme.reduceMotion
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
            required property int index
            readonly property bool near: index % 3 === 0
            readonly property real len: near ? 18 + Math.random() * 10 : 8 + Math.random() * 6
            width: near ? 1.6 : 1
            height: len
            radius: width / 2
            rotation: 12
            color: "#d6e6ff"
            readonly property real base: near ? 0.35 + Math.random() * 0.15 : 0.15 + Math.random() * 0.15
            opacity: base * Math.max(0, 1 - y / (root.skyDepth * 1.2))
            readonly property real fx: Math.random()
            readonly property real fy: Math.random()
            x: fx * (root.width + 80) - y * 0.21       // tan(12°): falls along its slant
            y: -len
            NumberAnimation on y {
                running: root.active && !Theme.reduceMotion
                loops: Animation.Infinite
                from: -drop.len - drop.fy * root.skyDepth
                to: root.skyDepth * 1.2
                duration: (drop.near ? 450 : 800) + Math.random() * 300
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
            readonly property real base: 0.35 + Math.random() * 0.45
            opacity: base * Math.max(0, 1 - y / (root.skyDepth * 1.4))
            x: baseX + Math.sin(sway) * 12
            NumberAnimation on y {
                running: root.active && !Theme.reduceMotion
                loops: Animation.Infinite
                from: -10 - flake.fy * root.skyDepth
                to: root.skyDepth * 1.4
                duration: 6000 + Math.random() * 5000
            }
            NumberAnimation on sway {
                running: root.active && !Theme.reduceMotion
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
        running: root.active && !Theme.reduceMotion && root.scene === "storm"
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
