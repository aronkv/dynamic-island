import QtQuick

// Battery level as a floating glass badge left of the pill (idleBadgeLeft),
// shown while on battery when Settings → Battery → "Battery outside the
// pill" is on; ChargeBadge takes over while plugged in. iOS colors: red at
// ≤ 10 %, yellow while Power Saver is on, white otherwise. With
// showPercent off it shrinks to a circle around the glyph.
// Click → `clicked` (the island opens the battery view).
Rectangle {
    id: badge
    property var battery: null          // BatteryMonitor
    property bool enabledSetting: true
    property bool showPercent: true
    property bool lowPower: false
    property int size: 44
    property color surfaceColor: "#000000"
    property real glassRim: 0
    signal clicked()

    readonly property bool active: enabledSetting && !!battery && battery.onBattery
    readonly property real pct: battery ? Math.max(0, Math.min(100, battery.percentage)) : 0
    readonly property color tint: pct <= 10 ? "#ff453a" : lowPower ? "#ffd60a" : "#ffffff"

    width: Math.max(size, row.implicitWidth + 24)
    height: size
    radius: height / 2
    color: surfaceColor

    opacity: active ? 1 : 0
    scale: active ? 1 : 0.7
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 300 } }

    // Liquid Glass rim, same as RecordingBadge / the tray badge.
    Repeater {
        model: 4
        Rectangle {
            required property int index
            anchors.fill: parent
            anchors.margins: badge.glassRim * 0.6 * index / 4
            radius: height / 2
            color: Qt.rgba(0, 0, 0, badge.glassRim > 0 ? 0.3 : 1)
            visible: badge.glassRim > 0 || index === 0
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: badge.glassRim * 0.6
        radius: height / 2
        color: "#000000"
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        Text {
            visible: badge.showPercent
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(badge.pct) + "%"
            color: badge.tint
            font.pixelSize: 13
            font.weight: 600
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }

        // Battery glyph: outline + level fill + terminal nub.
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 12
            Rectangle {
                width: 21
                height: 12
                radius: 3.5
                color: "transparent"
                border.width: 1.2
                border.color: Qt.rgba(badge.tint.r, badge.tint.g, badge.tint.b, 0.55)
                Rectangle {
                    x: 2; y: 2
                    height: parent.height - 4
                    width: Math.max(2, (parent.width - 4) * badge.pct / 100)
                    radius: 1.5
                    color: badge.tint
                }
            }
            Rectangle {
                x: 22; y: 4
                width: 1.8; height: 4; radius: 1
                color: Qt.rgba(badge.tint.r, badge.tint.g, badge.tint.b, 0.55)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: badge.clicked()
    }
}
