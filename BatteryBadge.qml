import QtQuick

// Battery level beside the pill (idleBadgeLeft), shown while on battery
// when Settings → Battery → "Battery outside the pill" is on — and always
// at ≤ 10 %, then with the minutes left until empty; ChargeBadge takes
// over while plugged in. No background: like ChargeBadge's bolt, the
// glyph and the percentage sit on the wallpaper with a soft dark halo. The level fill tracks the charge; iOS
// colors: red at ≤ 10 %, yellow while Power Saver is on, white otherwise.
// Click → `clicked` (the island opens the battery view).
Item {
    id: badge
    property var battery: null          // BatteryMonitor
    property bool enabledSetting: true
    property bool showPercent: true
    property bool lowPower: false
    property int size: 44
    signal clicked()

    readonly property real pct: battery ? Math.max(0, Math.min(100, battery.percentage)) : 0
    readonly property bool low: pct <= 10
    readonly property bool active: !!battery && battery.onBattery && (enabledSetting || low)
    // Smoothed estimate from BatteryMonitor (seconds); shown only when low.
    readonly property int minutesLeft: low && battery && battery.timeRemaining > 0 ? Math.round(battery.timeRemaining / 60) : -1
    readonly property color tint: pct <= 10 ? "#ff453a" : lowPower ? "#ffd60a" : "#ffffff"

    readonly property string label: (showPercent || low)
        ? Math.round(pct) + "%" + (minutesLeft >= 0
            ? " · " + (minutesLeft >= 60 ? Math.floor(minutesLeft / 60) + " h " + minutesLeft % 60 : minutesLeft) + " min"
            : "")
        : ""

    // Glyph geometry (px): body 28×15, nub 2.5×6, 7 px gap after the text.
    readonly property real bodyW: 28
    readonly property real bodyH: 15
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

    // Everything is drawn relative to this centred box.
    Item {
        id: box
        width: badge.contentW
        height: badge.height
        anchors.right: parent.right
        anchors.rightMargin: badge.rightInset

        // Halo rings shared by glyph and text: faint dark copies offset on
        // rings around the shape add up to a soft falloff. (Stroking the
        // outline several times, as ChargeBadge does for the bolt, drew
        // spiky artefacts on these small curves and on PathText.)
        readonly property var haloOffsets: {
            const out = []
            const rings = [{ r: 5, a: 0.025 }, { r: 3.5, a: 0.035 }, { r: 2, a: 0.05 }, { r: 1, a: 0.07 }]
            for (const ring of rings)
                for (let k = 0; k < 12; k++)
                    out.push({ dx: ring.r * Math.cos(k * Math.PI / 6), dy: ring.r * Math.sin(k * Math.PI / 6), a: ring.a })
            return out
        }
        Repeater {
            model: box.haloOffsets
            Item {
                required property var modelData
                anchors.fill: parent
                Rectangle {
                    x: badge.glyphX + modelData.dx
                    y: badge.glyphTop + modelData.dy
                    width: badge.bodyW
                    height: badge.bodyH
                    radius: 4.5
                    color: "transparent"
                    border.width: 1.6
                    border.color: Qt.rgba(0, 0, 0, modelData.a)
                }
                Rectangle {
                    x: badge.glyphX + badge.bodyW + 1.2 + modelData.dx
                    y: badge.glyphTop + badge.bodyH / 2 - 3 + modelData.dy
                    width: 2.5
                    height: 6
                    radius: 1
                    color: Qt.rgba(0, 0, 0, modelData.a)
                }
            }
        }
        // Same halo for the percentage text.
        Repeater {
            model: box.haloOffsets
            Text {
                required property var modelData
                x: modelData.dx
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: modelData.dy
                visible: badge.label !== ""
                text: badge.label
                color: Qt.rgba(0, 0, 0, modelData.a)
                font.pixelSize: metrics.font.pixelSize
                font.weight: metrics.font.weight
                font.family: metrics.font.family
            }
        }

        // Percentage.
        Text {
            x: 0
            anchors.verticalCenter: parent.verticalCenter
            visible: badge.label !== ""
            text: badge.label
            color: badge.tint
            font.pixelSize: metrics.font.pixelSize
            font.weight: metrics.font.weight
            font.family: metrics.font.family
        }

        // Glyph: outline + nub, then the level fill inside.
        Rectangle {
            x: badge.glyphX
            y: badge.glyphTop
            width: badge.bodyW
            height: badge.bodyH
            radius: 4.5
            color: "transparent"
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
            x: badge.glyphX + 2.5
            y: badge.glyphTop + 2.5
            height: badge.bodyH - 5
            width: Math.max(2.5, (badge.bodyW - 5) * badge.pct / 100)
            radius: 2.5
            color: badge.tint
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: badge.clicked()
    }
}
