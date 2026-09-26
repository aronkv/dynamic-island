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
            onClicked: btn.clicked()
        }
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: "emblem-system-symbolic"
        title: "Settings"
        subtitle: "Saved automatically"
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
                    Behavior on x { SpringAnimation { spring: 4; damping: 0.35 } }
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
