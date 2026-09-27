import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// iOS Settings style: grouped, rounded sections with hairline separators;
// each row has a colored icon tile, a label (+ optional subtitle) and a
// trailing control.
ColumnLayout {
    id: panel
    property var store: null
    property var weatherMonitor: null
    property var nightLight: null
    signal closeRequested()
    spacing: 12

    component IconTile: Rectangle {
        id: tile
        property string icon: ""
        implicitWidth: 28
        implicitHeight: 28
        radius: 7

        IconImage {
            id: tileIcon
            anchors.centerIn: parent
            implicitSize: 16
            source: tile.icon ? "image://icon/" + tile.icon : ""
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }
        Rectangle {
            id: tileFill
            anchors.fill: tileIcon
            color: "#ffffff"
            visible: false
        }
        MultiEffect {
            anchors.fill: tileIcon
            source: tileFill
            maskEnabled: true
            maskSource: tileIcon
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.0
            maskThresholdMax: 1.0
            maskSpreadAtMax: 0.0
        }
    }

    component SectionTitle: Text {
        Layout.leftMargin: 12
        Layout.topMargin: 4
        color: "#ffffff"
        opacity: 0.45
        font.pixelSize: 10
        font.weight: 600
        font.letterSpacing: 0.6
        font.family: Theme.fontText
    }

    // Rounded group container; rows go inside, separated by Separator.
    component Group: Rectangle {
        default property alias rows: groupCol.data
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: Theme.radiusMedium
        color: Theme.card

        ColumnLayout {
            id: groupCol
            width: parent.width
            spacing: 0
        }
    }

    component Separator: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: 50
        implicitHeight: 1
        color: Theme.separator
        opacity: 0.6
    }

    component Row: Item {
        id: row
        property string icon: ""
        property color tint: Theme.blue
        property string label: ""
        property string subtitle: ""
        property bool checked: false
        property bool showToggle: true
        signal toggled()
        Layout.fillWidth: true
        implicitHeight: subtitle !== "" ? 54 : 44

        IconTile {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            icon: row.icon
            color: row.tint
        }

        Column {
            anchors.left: rowIcon.right
            anchors.leftMargin: 10
            anchors.right: rowToggle.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Text {
                width: parent.width
                text: row.label
                color: "#ffffff"
                font.pixelSize: 13
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                visible: row.subtitle !== ""
                text: row.subtitle
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 10
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        ToggleSwitch {
            id: rowToggle
            visible: row.showToggle
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 40
            implicitHeight: 24
            checked: row.checked
            onToggled: row.toggled()
        }
    }

    // Segment highlights only animate right after a click. Otherwise their
    // x (a fraction of the track width) would visibly slide while the island
    // grows around the panel on open.
    property bool segAnim: false
    Timer { id: segAnimOff; interval: 450; onTriggered: panel.segAnim = false }

    component SegmentButton: Item {
        id: btn
        property string label: ""
        property bool active: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: 28

        Text {
            anchors.centerIn: parent
            text: btn.label
            color: btn.active ? "#000000" : "#ffffff"
            opacity: btn.active ? 1 : 0.65
            font.pixelSize: 11
            font.weight: 600
            font.family: Theme.fontText
            Behavior on color { ColorAnimation { duration: 180 } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { panel.segAnim = true; segAnimOff.restart(); btn.clicked() }
        }
    }

    // Segmented control with a sliding white highlight (same look as the
    // Night Shift schedule / now-playing tracks).
    component SegTrack: Rectangle {
        id: seg
        property var labels: []
        property var values: []
        property var current
        signal picked(var value)
        readonly property int idx: Math.max(0, values.indexOf(current))
        readonly property real segW: (width - 6) / Math.max(1, labels.length)
        Layout.fillWidth: true
        implicitHeight: 30
        radius: 9
        color: Theme.cardElevated
        Rectangle {
            x: 3 + seg.idx * seg.segW
            y: 3
            width: seg.segW
            height: parent.height - 6
            radius: 7
            color: "#ffffff"
            Behavior on x { enabled: panel.segAnim; NumberAnimation { duration: Theme.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic } }
        }
        RowLayout {
            anchors.fill: parent
            anchors.margins: 3
            spacing: 0
            Repeater {
                model: seg.labels
                SegmentButton {
                    required property int index
                    required property string modelData
                    label: modelData
                    active: seg.idx === index
                    onClicked: seg.picked(seg.values[index])
                }
            }
        }
    }

    component SegRow: Item {
        id: segRow
        property string label: ""
        default property alias track: slot.data
        Layout.fillWidth: true
        implicitHeight: 44
        Text {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 82
            text: segRow.label
            color: "#ffffff"
            font.pixelSize: 13
            font.family: Theme.fontText
        }
        RowLayout {
            id: slot
            x: 100
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 112
        }
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: "emblem-system-symbolic"
        title: "Settings"
        showToggle: false
        showRefresh: false
        showSettingsGear: false
        onCloseRequested: panel.closeRequested()
    }

    Flickable {
        id: scroller
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: scrollFadeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ColumnLayout {
            id: body
            width: scroller.width
            spacing: 6

            SectionTitle { text: "APPEARANCE" }
            Group {
                Row {
                    icon: "view-dual-symbolic"
                    tint: Theme.blue
                    label: "Liquid Glass"
                    subtitle: "Frosted glass island and windows"
                    checked: panel.store ? panel.store.blurEnabled : false
                    onToggled: if (panel.store) panel.store.blurEnabled = !panel.store.blurEnabled
                }
                Separator {}
                Row {
                    icon: "window-maximize-symbolic"
                    tint: "#5e5ce6"
                    label: "Strip mode"
                    subtitle: "Collapse the idle island to a thin bar"
                    checked: panel.store ? panel.store.pillMode === "strip" : false
                    onToggled: if (panel.store) panel.store.pillMode = (panel.store.pillMode === "strip" ? "pill" : "strip")
                }
            }

            SectionTitle { text: "DISPLAY" }
            Group {
                Row {
                    icon: "weather-clear-night-symbolic"
                    tint: Theme.orange
                    label: "Night Shift"
                    subtitle: panel.nightLight && !panel.nightLight.available ? "Needs hyprsunset: sudo pacman -S hyprsunset"
                        : panel.store && panel.store.nightLightSchedule === "always" ? "Warmer colors, always on"
                        : "Warmer colors from sunset to sunrise"
                    checked: panel.store ? panel.store.nightLight : false
                    onToggled: if (panel.store) panel.store.nightLight = !panel.store.nightLight
                }
                Item {
                    Layout.fillWidth: true
                    implicitHeight: 86
                    visible: panel.store ? panel.store.nightLight : false

                    Rectangle {
                        id: nsTrack
                        x: 50
                        y: 4
                        width: parent.width - 62
                        height: 30
                        radius: 9
                        color: Theme.cardElevated
                        readonly property int idx: panel.store && panel.store.nightLightSchedule === "always" ? 1 : 0
                        Rectangle {
                            x: 3 + nsTrack.idx * (nsTrack.width - 6) / 2
                            y: 3
                            width: (nsTrack.width - 6) / 2
                            height: parent.height - 6
                            radius: 7
                            color: "#ffffff"
                            Behavior on x { enabled: panel.segAnim; NumberAnimation { duration: Theme.reduceMotion ? 0 : 180; easing.type: Easing.OutCubic } }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 3
                            spacing: 0
                            SegmentButton { label: "Sunset to Sunrise"; active: nsTrack.idx === 0; onClicked: if (panel.store) panel.store.nightLightSchedule = "sunset" }
                            SegmentButton { label: "Always"; active: nsTrack.idx === 1; onClicked: if (panel.store) panel.store.nightLightSchedule = "always" }
                        }
                    }

                    // Warmth slider: 6000 K (less warm) → 2500 K (more warm).
                    RowLayout {
                        x: 50
                        y: 46
                        width: parent.width - 62
                        spacing: 8
                        Text { text: "Less warm"; color: "#ffffff"; opacity: 0.45; font.pixelSize: 10; font.family: Theme.fontText }
                        Item {
                            id: warmth
                            Layout.fillWidth: true
                            implicitHeight: 24
                            readonly property real value: panel.store ? (6000 - panel.store.nightLightTemp) / 3500 : 0.57
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 6
                                radius: 3
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "#ffe6c7" }
                                    GradientStop { position: 1; color: "#ff9f0a" }
                                }
                            }
                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(0, Math.min(1, warmth.value)) * (warmth.width - width)
                                color: "#ffffff"
                                border.color: Qt.rgba(0, 0, 0, 0.2)
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                function setAt(x) {
                                    const v = Math.max(0, Math.min(1, x / width))
                                    if (panel.store) panel.store.nightLightTemp = Math.round((6000 - v * 3500) / 100) * 100
                                }
                                onPressed: (mouse) => setAt(mouse.x)
                                onPositionChanged: (mouse) => { if (pressed) setAt(mouse.x) }
                            }
                        }
                        Text { text: "More warm"; color: "#ffffff"; opacity: 0.45; font.pixelSize: 10; font.family: Theme.fontText }
                    }
                }
                Separator {}
                Row {
                    icon: "view-restore-symbolic"
                    tint: "#5e5ce6"
                    label: "Reduce motion"
                    subtitle: "No springs, slides or ambient animations"
                    checked: panel.store ? panel.store.reduceMotion : false
                    onToggled: if (panel.store) panel.store.reduceMotion = !panel.store.reduceMotion
                }
                Separator {}
                Row {
                    icon: "accessories-text-editor-symbolic"
                    tint: "#7f6df2"
                    label: "Obsidian follows theme"
                    subtitle: panel.store && panel.store.obsidianFollowTheme ? "Island theme uses the current accent" : "Island theme uses Obsidian purple"
                    checked: panel.store ? panel.store.obsidianFollowTheme : true
                    onToggled: if (panel.store) panel.store.obsidianFollowTheme = !panel.store.obsidianFollowTheme
                }
            }

            SectionTitle { text: "NOW PLAYING IN THE ISLAND" }
            Rectangle {
                id: segTrack
                Layout.fillWidth: true
                implicitHeight: 34
                radius: 10
                color: Theme.card
                readonly property var modes: ["art", "title", "lyrics"]
                readonly property int activeIndex: panel.store ? Math.max(0, modes.indexOf(panel.store.idlePlayerMode)) : 0
                readonly property real segW: (width - 6) / 3

                Rectangle {
                    x: 3 + segTrack.activeIndex * segTrack.segW
                    y: 3
                    width: segTrack.segW
                    height: parent.height - 6
                    radius: 8
                    color: "#ffffff"
                    Behavior on x { enabled: panel.segAnim; SpringAnimation { spring: 4; damping: 0.35 } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 0
                    SegmentButton { label: "Album art"; active: segTrack.activeIndex === 0; onClicked: if (panel.store) panel.store.idlePlayerMode = "art" }
                    SegmentButton { label: "Track title"; active: segTrack.activeIndex === 1; onClicked: if (panel.store) panel.store.idlePlayerMode = "title" }
                    SegmentButton { label: "Lyrics"; active: segTrack.activeIndex === 2; onClicked: if (panel.store) panel.store.idlePlayerMode = "lyrics" }
                }
            }

            SectionTitle { text: "SCREEN RECORDING" }
            Group {
                SegRow {
                    label: "Resolution"
                    SegTrack {
                        labels: ["Native", "1080p", "720p", "480p"]
                        values: ["native", "1080", "720", "480"]
                        current: panel.store ? panel.store.recordResolution : "native"
                        onPicked: (v) => { if (panel.store) panel.store.recordResolution = v }
                    }
                }
                Separator {}
                SegRow {
                    label: "Frame rate"
                    SegTrack {
                        labels: ["30 fps", "60 fps"]
                        values: [30, 60]
                        current: panel.store ? panel.store.recordFps : 60
                        onPicked: (v) => { if (panel.store) panel.store.recordFps = v }
                    }
                }
                Separator {}
                SegRow {
                    label: "Quality"
                    SegTrack {
                        labels: ["Medium", "High", "Very high", "Ultra"]
                        values: ["medium", "high", "very_high", "ultra"]
                        current: panel.store ? panel.store.recordQuality : "very_high"
                        onPicked: (v) => { if (panel.store) panel.store.recordQuality = v }
                    }
                }
                Separator {}
                Row {
                    icon: "audio-speakers-symbolic"
                    tint: Theme.blue
                    label: "System audio"
                    checked: panel.store ? panel.store.recordSystemAudio : true
                    onToggled: if (panel.store) panel.store.recordSystemAudio = !panel.store.recordSystemAudio
                }
                Separator {}
                Row {
                    icon: "audio-input-microphone-symbolic"
                    tint: Theme.orange
                    label: "Microphone"
                    checked: panel.store ? panel.store.recordMic : false
                    onToggled: if (panel.store) panel.store.recordMic = !panel.store.recordMic
                }
                Separator {}
                Row {
                    icon: "input-mouse-symbolic"
                    tint: "#8e8e93"
                    label: "Show cursor"
                    checked: panel.store ? panel.store.recordCursor : true
                    onToggled: if (panel.store) panel.store.recordCursor = !panel.store.recordCursor
                }
            }
            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                text: "SUPER+R starts / stops · saved to ~/Videos/Recordings · changes apply to the next recording"
                color: "#ffffff"
                opacity: 0.35
                font.pixelSize: 10
                font.family: Theme.fontText
                wrapMode: Text.WordWrap
            }

            SectionTitle { text: "NOTIFICATIONS & PRIVACY" }
            Group {
                Row {
                    icon: "weather-clear-night-symbolic"
                    tint: "#5e5ce6"
                    label: "Do Not Disturb"
                    subtitle: "Notifications won't expand the island"
                    checked: panel.store ? panel.store.doNotDisturb : false
                    onToggled: if (panel.store) panel.store.doNotDisturb = !panel.store.doNotDisturb
                }
                Separator {}
                Row {
                    icon: "audio-input-microphone-symbolic"
                    tint: Theme.orange
                    label: "Microphone indicator"
                    checked: panel.store ? panel.store.micIndicatorEnabled : false
                    onToggled: if (panel.store) panel.store.micIndicatorEnabled = !panel.store.micIndicatorEnabled
                }
                Separator {}
                Row {
                    icon: "camera-web-symbolic"
                    tint: Theme.green
                    label: "Camera indicator"
                    checked: panel.store ? panel.store.cameraIndicatorEnabled : false
                    onToggled: if (panel.store) panel.store.cameraIndicatorEnabled = !panel.store.cameraIndicatorEnabled
                }
            }

            SectionTitle { text: "CALCULATOR" }
            Group {
                Row {
                    icon: "document-open-recent-symbolic"
                    tint: Theme.orange
                    label: "Always show history"
                    subtitle: "Otherwise open it with the clock button or Ctrl+H"
                    checked: panel.store ? panel.store.calcHistoryAlways : false
                    onToggled: if (panel.store) panel.store.calcHistoryAlways = !panel.store.calcHistoryAlways
                }
            }

            SectionTitle { text: "WEATHER" }
            Group {
                Row {
                    icon: "weather-showers-symbolic"
                    tint: Theme.blue
                    label: "Rain alert"
                    subtitle: "Heads-up in the island ~15–30 min before rain"
                    checked: panel.store ? panel.store.rainAlert : false
                    onToggled: if (panel.store) panel.store.rainAlert = !panel.store.rainAlert
                }
                Separator {}
                Row {
                    icon: "find-location-symbolic"
                    tint: Theme.blue
                    label: "Manual location"
                    subtitle: panel.store && panel.store.weatherManualLocation ? "" : "Detected automatically from your IP"
                    checked: panel.store ? panel.store.weatherManualLocation : false
                    onToggled: if (panel.store) panel.store.weatherManualLocation = !panel.store.weatherManualLocation
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    visible: panel.store ? panel.store.weatherManualLocation : false

                    Rectangle {
                        anchors.fill: parent
                        anchors.leftMargin: 50
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 8
                        radius: 8
                        color: Theme.cardElevated

                        TextInput {
                            id: cityInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            color: "#ffffff"
                            font.pixelSize: 12
                            font.family: Theme.fontText
                            selectByMouse: true
                            clip: true
                            focus: panel.store ? panel.store.weatherManualLocation : false
                            Component.onCompleted: text = panel.store ? panel.store.weatherCity : ""
                            onTextChanged: if (panel.store) panel.store.weatherCity = text

                            Text {
                                visible: cityInput.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "City, e.g. Budapest"
                                color: "#ffffff"
                                opacity: 0.35
                                font: cityInput.font
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: 50
                    Layout.bottomMargin: 8
                    visible: panel.weatherMonitor ? panel.weatherMonitor.locationError : false
                    text: "No such place — the last reading is still showing"
                    color: Theme.red
                    font.pixelSize: 11
                    font.family: Theme.fontText
                    wrapMode: Text.WordWrap
                }
            }

            // Plain text button, iOS "destructive-less" link style.
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                Layout.bottomMargin: 8
                text: "Reset island size"
                color: Theme.blue
                font.pixelSize: 12
                font.family: Theme.fontText
                opacity: resetMouse.pressed ? 0.5 : 1

                MouseArea {
                    id: resetMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (panel.store) { panel.store.idleWidth = 0; panel.store.idleHeight = 0 }
                }
            }
        }
    }

    Item {
        id: scrollFadeMask
        width: scroller.width
        height: scroller.height
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: scroller.contentY > 2 ? "transparent" : "white" }
                GradientStop { position: 0.05; color: "white" }
                GradientStop { position: 0.92; color: "white" }
                GradientStop { position: 1.0; color: scroller.contentY < scroller.contentHeight - scroller.height - 2 ? "transparent" : "white" }
            }
        }
    }
}
