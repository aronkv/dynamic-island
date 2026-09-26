import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// iPhone-style "charger connected" moment: a battery glyph whose liquid
// fill rises to the current level (with a light sheen sweeping through it)
// and a vector bolt popping in, "Charging" + time-to-full, big percentage.
// Low batteries (<20%) fill with a red→green gradient.
Item {
    id: root
    property var battery: null          // BatteryMonitor
    property bool shown: false

    readonly property real pct: battery ? Math.max(0, Math.min(100, battery.percentage)) : 0
    readonly property bool full: battery && battery.state === UPowerDeviceState.FullyCharged
    readonly property bool low: pct < 20
    readonly property string subtitle: {
        if (!battery) return ""
        if (battery.chargeLimitSupported && pct >= battery.chargeLimit - 1)
            return "Held at " + battery.chargeLimit + "% to protect the battery"
        if (full) return "Connected to power"
        const t = battery.timeToFull
        if (battery.charging && t > 60) {
            const h = Math.floor(t / 3600), m = Math.round((t % 3600) / 60)
            return "Full in " + (h > 0 ? h + " h " : "") + m + " min"
        }
        return battery.charging ? "Plugged in" : "Plugged in · not charging"
    }

    // 0..1 fill level, animated from empty each time the view appears.
    property real fill: 0
    onShownChanged: {
        if (shown) {
            fill = 0
            boltPop.restart()
            fillIn.restart()
        }
    }
    NumberAnimation {
        id: fillIn
        target: root
        property: "fill"
        from: 0
        to: root.pct / 100
        duration: 1100
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: boltPop
        PropertyAction { target: boltItem; property: "scale"; value: 0 }
        PauseAnimation { duration: 260 }
        NumberAnimation { target: boltItem; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 22
        spacing: 14

        // ── Battery glyph ─────────────────────────────────────────────
        Item {
            implicitWidth: 58
            implicitHeight: 28

            Rectangle {
                id: shell
                width: 53
                height: 28
                radius: 8.5
                color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1.5
                border.color: Qt.rgba(1, 1, 1, 0.35)

                // Liquid fill, clipped to the inner rounded shape.
                Item {
                    id: inner
                    anchors.fill: parent
                    anchors.margins: 3
                    clip: true
                    Rectangle {
                        id: liquid
                        height: parent.height
                        width: Math.max(radius * 2, parent.width * root.fill)
                        visible: root.fill > 0.01
                        radius: 5.5
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.low ? "#ff453a" : "#28b446" }
                            GradientStop { position: 1; color: root.low && root.fill < 0.12 ? "#ff9f0a" : "#4be26b" }
                        }
                        // Sheen sweeping across the liquid.
                        Item {
                            anchors.fill: parent
                            clip: true
                            Rectangle {
                                id: sheen
                                width: 18
                                height: parent.height
                                opacity: 0.35
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 0.5; color: "#ffffff" }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                                NumberAnimation on x {
                                    running: root.shown
                                    loops: Animation.Infinite
                                    from: -30
                                    to: 60
                                    duration: 1400
                                    easing.type: Easing.InOutSine
                                }
                            }
                        }
                    }
                }

                // Bolt: white with a dark outline so it reads over the fill.
                BoltShape {
                    id: boltItem
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    color: "#ffffff"
                    outline: "#000000"
                    outlineWidth: 1.6
                }
            }
            // Terminal nub.
            Rectangle {
                anchors.left: shell.right
                anchors.leftMargin: 2
                anchors.verticalCenter: shell.verticalCenter
                width: 3
                height: 10
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.35)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            Text {
                Layout.fillWidth: true
                text: root.full ? "Fully Charged" : "Charging"
                color: "#ffffff"
                font.pixelSize: 15
                font.weight: 600
                font.family: "SF Pro Display"
            }
            Text {
                Layout.fillWidth: true
                text: root.subtitle
                color: "#ffffff"
                opacity: 0.5
                font.pixelSize: 11
                font.family: "SF Pro Text"
                elide: Text.ElideRight
            }
        }

        Row {
            Layout.alignment: Qt.AlignVCenter
            Text {
                text: Math.round(root.fill * 100 > root.pct - 0.5 ? root.pct : root.fill * 100)
                color: root.low ? "#ff9f0a" : "#32d74b"
                font.pixelSize: 26
                font.weight: 700
                font.family: "SF Pro Rounded"
                font.features: { "tnum": 1 }
            }
            Text {
                anchors.baseline: parent.children[0].baseline
                text: "%"
                color: root.low ? "#ff9f0a" : "#32d74b"
                opacity: 0.8
                font.pixelSize: 15
                font.weight: 600
                font.family: "SF Pro Rounded"
            }
        }
    }
}
