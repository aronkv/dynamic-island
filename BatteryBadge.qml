import QtQuick

// Battery level beside the pill (idleBadgeLeft), shown while on battery
// when Settings → Battery → "Battery outside the pill" is on — and always
// at ≤ 10 %, then with the minutes left until empty; ChargeBadge takes
// over while plugged in. No background: like ChargeBadge's bolt, the
// glyph and text sit on the wallpaper with a soft dark halo. The level
// fill tracks the charge; iOS colors: red at ≤ 10 %, yellow while Power
// Saver is on, white otherwise. The percentage can sit next to the glyph
// or, iOS 16 style, inside a larger glyph (`percentInside`), dark over the
// fill and light over the empty part.
// Click → `clicked` (the island opens the battery view).
Item {
    id: badge
    property var battery: null          // BatteryMonitor
    property bool enabledSetting: true
    property bool showPercent: true
    property bool percentInside: false
    property bool lowPower: false
    property int size: 44
    signal clicked()

    readonly property real pct: battery ? Math.max(0, Math.min(100, battery.percentage)) : 0
    readonly property bool low: pct <= 10
    readonly property bool active: !!battery && battery.onBattery && (enabledSetting || low)
    // Smoothed estimate from BatteryMonitor (seconds); shown only when low.
    readonly property int minutesLeft: low && battery && battery.timeRemaining > 0 ? Math.round(battery.timeRemaining / 60) : -1
    readonly property color tint: pct <= 10 ? "#ff453a" : lowPower ? "#ffd60a" : "#ffffff"

    readonly property bool inside: percentInside && (showPercent || low)
    readonly property string minutesText: minutesLeft >= 0
        ? (minutesLeft >= 60 ? Math.floor(minutesLeft / 60) + " h " + minutesLeft % 60 : minutesLeft) + " min"
        : ""
    // Text beside the glyph: "64%" (+ " · 25 min" when low), or only the
    // minutes when the percentage is drawn inside.
    readonly property string label: inside ? minutesText
        : (showPercent || low) ? Math.round(pct) + "%" + (minutesText !== "" ? " · " + minutesText : "")
        : ""

    // Glyph geometry (px): 28×15 body, or 36×18 with the number inside;
    // nub 2.5×6; 7 px gap after the text.
    readonly property real bodyW: inside ? 36 : 28
    readonly property real bodyH: inside ? 18 : 15
    readonly property real cornerR: inside ? 5.5 : 4.5
    readonly property real gap: label !== "" ? 7 : 0
    readonly property real textW: label !== "" ? metrics.advanceWidth : 0
    readonly property real glyphX: textW + gap
    readonly property real contentW: glyphX + bodyW + 4
    readonly property real glyphTop: (height - bodyH) / 2

    // The glyph's right edge sits as far from the island as the charging
    // bolt's tip: the bolt (ChargeBadge, 28 px, shifted 6 px toward the
    // island inside a 44 px box centred in the same idleBadgeSize slot)
    // ends ~3.4 px inside its slot, so the content is right-aligned with
    // that inset instead of being centred.
    readonly property real rightInset: 3
    width: Math.max(size, contentW + rightInset + 8)
    height: size

    opacity: active ? 1 : 0
    scale: active ? 1 : 0.7
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    TextMetrics {
        id: metrics
        text: badge.label
        font.pixelSize: 15
        font.weight: 600
        font.family: Theme.fontText
    }

    // Everything is drawn relative to this right-aligned box.
    Item {
        id: box
        width: badge.contentW
        height: badge.height
        anchors.right: parent.right
        anchors.rightMargin: badge.rightInset

        // ── Halo ──
        // Glyph: concentric rounded-rect rings growing outward, each fainter
        // — a smooth falloff with no lobes (offset copies of the outline
        // left visible steps on the straight edges).
        Repeater {
            model: 6
            Rectangle {
                required property int index
                readonly property real grow: index + 1
                x: badge.glyphX - grow
                y: badge.glyphTop - grow
                width: badge.bodyW + 4 + grow * 2      // + the nub
                height: badge.bodyH + grow * 2
                radius: badge.cornerR + grow
                color: "transparent"
                border.width: 1.2
                border.color: Qt.rgba(0, 0, 0, 0.11 - index * 0.017)
            }
        }
        // Text: faint dark copies on two tight rings × 16 directions
        // (stroking glyph outlines that wide renders spiky artefacts).
        readonly property var textHalo: {
            const out = []
            const rings = [{ r: 2.2, a: 0.03 }, { r: 1.1, a: 0.05 }]
            for (const ring of rings)
                for (let k = 0; k < 16; k++)
                    out.push({ dx: ring.r * Math.cos(k * Math.PI / 8), dy: ring.r * Math.sin(k * Math.PI / 8), a: ring.a })
            return out
        }
        Repeater {
            model: badge.label !== "" ? box.textHalo : []
            Text {
                required property var modelData
                x: modelData.dx
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: modelData.dy
                text: badge.label
                color: Qt.rgba(0, 0, 0, modelData.a)
                font: metrics.font
            }
        }

        // Text beside the glyph.
        Text {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            visible: badge.label !== ""
            text: badge.label
            color: badge.tint
            font: metrics.font
        }

        // ── Glyph ──
        Rectangle {
            id: body
            x: badge.glyphX
            y: badge.glyphTop
            width: badge.bodyW
            height: badge.bodyH
            radius: badge.cornerR
            color: badge.inside ? Qt.rgba(0, 0, 0, 0.25) : "transparent"
            border.width: 1.6
            border.color: Qt.rgba(badge.tint.r, badge.tint.g, badge.tint.b, 0.6)
        }
        Rectangle {
            x: badge.glyphX + badge.bodyW + 1.2
            y: badge.glyphTop + badge.bodyH / 2 - 3
            width: 2.5
            height: 6
            radius: 1
            color: Qt.rgba(badge.tint.r, badge.tint.g, badge.tint.b, 0.6)
        }
        Rectangle {
            id: fill
            x: badge.glyphX + 2.5
            y: badge.glyphTop + 2.5
            height: badge.bodyH - 5
            width: Math.max(2.5, (badge.bodyW - 5) * badge.pct / 100)
            radius: badge.cornerR - 2
            color: badge.tint
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }

        // Number inside the glyph: light over the empty part, and a dark
        // copy clipped to the fill on top of it.
        Item {
            visible: badge.inside
            x: body.x
            y: body.y
            width: body.width
            height: body.height
            Text {
                id: insideText
                anchors.centerIn: parent
                text: Math.round(badge.pct)
                color: "#ffffff"
                font.pixelSize: 12
                font.weight: 700
                font.family: Theme.fontText
            }
            Item {
                x: fill.x - body.x
                y: 0
                width: fill.width
                height: parent.height
                clip: true
                Text {
                    x: insideText.x - parent.x
                    y: insideText.y
                    text: insideText.text
                    color: "#000000"
                    font: insideText.font
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: badge.clicked()
    }
}
