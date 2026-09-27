import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: panel
    property var monitor: null
    signal settingsRequested()
    signal closeRequested()

    // Value animations only once the panel has settled: while it opens, the
    // island is still spring-resizing, so every width/x in here changes
    // continuously and the Behaviors made the level bars and the power-mode
    // highlight visibly jump. Enabled ~0.6 s after the panel shows.
    property bool animate: false
    onVisibleChanged: {
        animate = false
        if (visible) animateTimer.restart()
    }
    Timer { id: animateTimer; interval: 600; onTriggered: panel.animate = true }
    spacing: 12

    readonly property color levelColor: {
        // Monochrome panel: the level is always white.
        return "#ffffff"
    }

    component StatTile: Rectangle {
        id: tile
        property string value: ""
        property string label: ""
        Layout.fillWidth: true
        implicitHeight: 48
        radius: 12
        color: "#161616"

        Column {
            anchors.centerIn: parent
            spacing: 2

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.value
                color: "#ffffff"
                font.pixelSize: 14
                font.weight: 700
                font.family: "SF Pro Display"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.label
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 9
                font.weight: 600
                font.letterSpacing: 0.4
                font.family: "SF Pro Display"
            }
        }
    }

    // Apple-style battery glyph: rounded capsule outline + nub, animated fill.
    component BatteryGlyph: Item {
        id: glyph
        property real level: 0
        property color fill: "#ffffff"
        property bool bolt: false
        implicitWidth: 46
        implicitHeight: 22

        Rectangle {
            id: body
            width: parent.width - 4
            height: parent.height
            radius: 6
            color: "transparent"
            border.color: "#ffffff"
            border.width: 1.5
            opacity: 0.9

            Rectangle {
                id: fillRect
                x: 3
                y: 3
                height: parent.height - 6
                width: Math.max(radius * 2, (parent.width - 6) * Math.min(1, glyph.level / 100))
                radius: 3.5
                color: glyph.fill
                Behavior on width { enabled: panel.animate; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 250 } }
            }
        }

        Rectangle {
            anchors.left: body.right
            anchors.leftMargin: 1
            anchors.verticalCenter: body.verticalCenter
            width: 2.5
            height: 7
            radius: 1.25
            color: "#ffffff"
            opacity: 0.6
        }

        // Charging bolt, two-tone: black where it sits on the white fill,
        // white over the empty part — split exactly at the fill's edge.
        Item {
            id: boltArea
            anchors.centerIn: body
            width: 14
            height: 14
            visible: glyph.bolt
            readonly property real split: Math.max(0, Math.min(width, body.x + fillRect.x + fillRect.width - x))
            Item {
                width: boltArea.split
                height: parent.height
                clip: true
                BoltShape { width: boltArea.width; height: boltArea.height; color: "#000000" }
            }
            Item {
                x: boltArea.split
                width: boltArea.width - boltArea.split
                height: parent.height
                clip: true
                BoltShape { x: -boltArea.split; width: boltArea.width; height: boltArea.height; color: "#ffffff" }
            }
        }
    }

    component SegmentButton: Item {
        id: btn
        property string label: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 30

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.active ? "#000000" : "#ffffff"
            opacity: btn.active ? 1 : 0.6
            font.pixelSize: 11
            font.weight: 600
            font.family: "SF Pro Display"
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: panel.monitor ? panel.monitor.iconName : "battery-symbolic"
        title: "Battery"
        subtitle: panel.monitor ? panel.monitor.statusText : ""
        onSettingsRequested: panel.settingsRequested()
        onCloseRequested: panel.closeRequested()
    }

    // Hero row: big percentage + battery glyph, power draw on the right.
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        BatteryGlyph {
            level: panel.monitor ? panel.monitor.percentage : 0
            fill: panel.levelColor
            bolt: panel.monitor ? panel.monitor.charging : false
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: panel.monitor ? Math.round(panel.monitor.percentage) + "%" : "—"
            color: "#ffffff"
            font.pixelSize: 30
            font.weight: 700
            font.family: "SF Pro Display"
        }

        Item { Layout.fillWidth: true }

        // Power: charging rate / draw, plus the charger's rated wattage.
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: 18

            Column {
                visible: panel.monitor && panel.monitor.powerDraw > 0.05
                spacing: 1
                Text {
                    anchors.right: parent.right
                    text: panel.monitor ? panel.monitor.powerDraw.toFixed(1) + " W" : ""
                    color: "#ffffff"
                    font.pixelSize: 18
                    font.weight: 600
                    font.family: "SF Pro Display"
                }
                Text {
                    anchors.right: parent.right
                    text: panel.monitor && panel.monitor.charging ? "CHARGING AT" : "USING"
                    color: "#ffffff"
                    opacity: 0.45
                    font.pixelSize: 9
                    font.weight: 600
                    font.family: "SF Pro Display"
                }
            }

            Column {
                visible: panel.monitor && panel.monitor.pluggedIn && panel.monitor.adapterWatts > 0
                spacing: 1
                Text {
                    anchors.right: parent.right
                    text: panel.monitor ? panel.monitor.adapterWatts + " W" : ""
                    color: "#ffffff"
                    font.pixelSize: 18
                    font.weight: 600
                    font.family: "SF Pro Display"
                }
                Text {
                    anchors.right: parent.right
                    text: "USB-C CHARGER"
                    color: "#ffffff"
                    opacity: 0.45
                    font.pixelSize: 9
                    font.weight: 600
                    font.family: "SF Pro Display"
                }
            }
        }
    }

    // Per-pack bars — the T480 has an internal (BAT0) and a removable (BAT1)
    // battery; only shown when there's more than one to break down.
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        visible: panel.monitor && panel.monitor.batteries.length > 1

        Repeater {
            model: panel.monitor ? panel.monitor.batteries : []

            RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: modelData.nativePath === "BAT0" ? "Internal" : modelData.nativePath === "BAT1" ? "Removable" : modelData.nativePath
                    color: "#ffffff"
                    opacity: 0.6
                    font.pixelSize: 11
                    font.family: "SF Pro Display"
                    Layout.preferredWidth: 70
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: 3
                    color: "#1f1f1f"

                    Rectangle {
                        width: parent.width * Math.min(1, modelData.percentage)
                        height: parent.height
                        radius: parent.radius
                        color: panel.levelColor
                        Behavior on width { enabled: panel.animate; NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    text: Math.round(modelData.percentage * 100) + "%"
                    color: "#ffffff"
                    font.pixelSize: 11
                    font.weight: 600
                    font.family: "SF Pro Display"
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 34
                }

                // Per-pack health + cycles (sysfs).
                Text {
                    readonly property var info: panel.monitor ? panel.monitor.packInfo(modelData.nativePath) : null
                    visible: info !== null
                    text: info ? Math.round(info.health) + "% health · " + info.cycles + " cycles" : ""
                    color: "#ffffff"
                    opacity: 0.45
                    font.pixelSize: 10
                    font.family: "SF Pro Display"
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: 130
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        StatTile {
            visible: panel.monitor && panel.monitor.healthKnown
            value: panel.monitor ? Math.round(panel.monitor.healthCombined) + "%" : ""
            label: "HEALTH"
        }
        StatTile {
            visible: panel.monitor && panel.monitor.chargeCyclesSupported
            value: panel.monitor ? String(panel.monitor.chargeCycles) : ""
            label: panel.monitor && panel.monitor.packs.length > 1 ? "CYCLES (MAX)" : "CYCLES"
        }
        StatTile {
            visible: panel.monitor && panel.monitor.fullCapacitySupported
            value: panel.monitor ? panel.monitor.fullCapacityWh.toFixed(1) + " / " + panel.monitor.designCapacityWh.toFixed(0) + " Wh" : ""
            label: "CAPACITY / DESIGN"
        }
        StatTile {
            visible: panel.monitor && panel.monitor.chargeLimitSupported
            value: panel.monitor ? panel.monitor.chargeLimit + "%" : ""
            label: "CHARGE LIMIT"
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "Power Mode"
                color: "#ffffff"
                opacity: 0.5
                font.pixelSize: 10
                font.weight: 600
                font.family: "SF Pro Display"
                Layout.fillWidth: true
            }

            Text {
                visible: panel.monitor && !panel.monitor.daemonAvailable
                text: "tlp-pd not running"
                color: "#ff453a"
                font.pixelSize: 10
                font.family: "SF Pro Display"
            }
        }

        Rectangle {
            id: segmentTrack
            Layout.fillWidth: true
            implicitHeight: 36
            radius: 11
            color: "#161616"
            opacity: panel.monitor && panel.monitor.daemonAvailable ? 1 : 0.4

            readonly property int activeIndex: !panel.monitor ? 1
                : panel.monitor.profile === PowerProfile.PowerSaver ? 0
                : panel.monitor.profile === PowerProfile.Performance ? 2 : 1
            readonly property real segmentWidth: (width - 6) / 3

            Rectangle {
                x: 3 + segmentTrack.activeIndex * segmentTrack.segmentWidth
                y: 3
                width: segmentTrack.segmentWidth
                height: parent.height - 6
                radius: 8
                color: "#ffffff"
                Behavior on x { enabled: panel.animate; SpringAnimation { spring: 4; damping: 0.35 } }
                Behavior on color { ColorAnimation { duration: 200 } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 0

                SegmentButton {
                    label: "Power Saver"
                    active: segmentTrack.activeIndex === 0
                    onClicked: panel.monitor.setProfile(PowerProfile.PowerSaver)
                }
                SegmentButton {
                    label: "Balanced"
                    active: segmentTrack.activeIndex === 1
                    onClicked: panel.monitor.setProfile(PowerProfile.Balanced)
                }
                SegmentButton {
                    label: "Performance"
                    active: segmentTrack.activeIndex === 2
                    onClicked: if (panel.monitor.hasPerformance) panel.monitor.setProfile(PowerProfile.Performance)
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: {
                if (!panel.monitor) return ""
                if (panel.monitor.degradationReason) return "Performance limited: " + panel.monitor.degradationReason
                switch (segmentTrack.activeIndex) {
                case 0: return "Reduces CPU speed and background activity to extend battery life."
                case 2: return "Maximum CPU performance. Uses more power and runs warmer."
                default: return "Balances performance and energy use automatically."
                }
            }
            color: "#ffffff"
            opacity: 0.45
            wrapMode: Text.WordWrap
            font.pixelSize: 10
            font.family: "SF Pro Display"
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Column {
            Layout.fillWidth: true
            spacing: 1

            Text {
                text: "Automatic Low Power"
                color: "#ffffff"
                font.pixelSize: 12
                font.family: "SF Pro Display"
            }

            Text {
                text: "Power Saver on battery at 20% or less"
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 10
                font.family: "SF Pro Display"
            }
        }

        ToggleSwitch {
            checked: panel.monitor && panel.monitor.settingsStore ? panel.monitor.settingsStore.autoLowPower : false
            onToggled: if (panel.monitor && panel.monitor.settingsStore)
                panel.monitor.settingsStore.autoLowPower = !panel.monitor.settingsStore.autoLowPower
        }
    }
}
