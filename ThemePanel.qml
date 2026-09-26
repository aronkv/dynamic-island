import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// macOS "Appearance"-style theme picker: a live mini-desktop preview of the
// browsed theme on top (wallpaper, island, a terminal window using the
// theme's kitty colors and accent border), a row of round accent chips,
// and an Apply button. ←/→ browse, Enter applies, clicking a chip browses,
// double-click applies.
ColumnLayout {
    id: panel
    property var profiles: null
    property var settingsStore: null
    property var wallpaperMonitor: null
    property bool panelActive: false
    onPanelActiveChanged: if (panel.panelActive) { themeFocusScope.forceActiveFocus(); panel.syncToCurrent() }
    signal closeRequested()
    spacing: 12

    // Static presets from theme-profiles.json with the synthetic "Dynamic"
    // entry inserted second (after T480).
    readonly property var carouselItems: {
        const staticList = panel.profiles ? panel.profiles.profiles : []
        const list = []
        if (staticList.length > 0) list.push(staticList[0])
        list.push({ name: "Dynamic", isDynamic: true })
        for (let i = 1; i < staticList.length; i++) list.push(staticList[i])
        return list
    }

    property int currentIndex: 0
    readonly property var currentItem: panel.carouselItems[panel.currentIndex] || null
    readonly property string activeThemeName: panel.settingsStore ? panel.settingsStore.currentThemeProfile : "T480"
    readonly property bool browsingActive: panel.currentItem !== null && panel.currentItem.name === panel.activeThemeName

    function paletteFor(item) {
        if (!item) return []
        if (item.isDynamic) return panel.profiles ? panel.profiles.dynamicPreviewColors : []
        return item.kitty ? item.kitty.colors : []
    }
    function accentFor(item) {
        if (!item) return "#ffffff"
        if (item.isDynamic) {
            if (panel.activeThemeName === "Dynamic" && panel.settingsStore) return panel.settingsStore.themeAccent
            const p = paletteFor(item)
            return p.length > 4 ? p[4] : "#ffffff"
        }
        return item.accent
    }

    function syncToCurrent() {
        const idx = panel.carouselItems.findIndex(it => it.name === panel.activeThemeName)
        if (idx >= 0) panel.currentIndex = idx
    }

    function applyCurrent() {
        if (!panel.currentItem || !panel.profiles) return
        if (panel.currentItem.isDynamic) panel.profiles.applyDynamic()
        else panel.profiles.applyProfile(panel.currentItem.name)
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: "preferences-color-symbolic"
        title: "Theme"
        subtitle: "Active: " + panel.activeThemeName
        showSettingsGear: false
        onCloseRequested: panel.closeRequested()
    }

    FocusScope {
        id: themeFocusScope
        Layout.fillWidth: true
        Layout.fillHeight: true
        focus: true

        Keys.onLeftPressed: panel.currentIndex = Math.max(0, panel.currentIndex - 1)
        Keys.onRightPressed: panel.currentIndex = Math.min(panel.carouselItems.length - 1, panel.currentIndex + 1)
        Keys.onReturnPressed: panel.applyCurrent()
        Keys.onEnterPressed: panel.applyCurrent()

        ColumnLayout {
            anchors.fill: parent
            spacing: 14

            // ── Live preview ──────────────────────────────────────────
            ClippingRectangle {
                id: preview
                Layout.fillWidth: true
                Layout.preferredHeight: 150
                radius: Theme.radiusMedium
                color: "#0a0a0a"

                readonly property var palette: panel.paletteFor(panel.currentItem)
                readonly property color accent: panel.accentFor(panel.currentItem)
                readonly property color termBg: panel.currentItem && panel.currentItem.kitty ? panel.currentItem.kitty.background : "#0a0a0a"
                readonly property color termFg: panel.currentItem && panel.currentItem.kitty ? panel.currentItem.kitty.foreground : "#e6e6e6"


                // Wallpaper backdrop (dimmed).
                Image {
                    anchors.fill: parent
                    source: panel.wallpaperMonitor && panel.wallpaperMonitor.currentPath ? "file://" + panel.wallpaperMonitor.currentPath : ""
                    sourceSize.width: 480
                    fillMode: Image.PreserveAspectCrop
                    opacity: 0.55
                    asynchronous: true
                }

                // Mini island.
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    width: 74
                    height: 12
                    radius: 6
                    topLeftRadius: 0
                    topRightRadius: 0
                    color: "#000000"
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        width: 5
                        height: 5
                        radius: 2.5
                        color: preview.accent
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        width: 22
                        height: 3
                        radius: 1.5
                        color: "#ffffff"
                        opacity: 0.8
                    }
                }

                // Mini terminal window with the theme's colors.
                Rectangle {
                    id: term
                    x: 22
                    y: 26
                    width: parent.width * 0.62
                    height: parent.height - 40
                    radius: 7
                    color: preview.termBg
                    border.width: 1.5
                    border.color: preview.accent
                    Behavior on color { ColorAnimation { duration: 300 } }

                    // Title-bar dots.
                    Row {
                        x: 8
                        y: 7
                        spacing: 4
                        Repeater {
                            model: ["#ff5f57", "#febc2e", "#28c840"]
                            Rectangle { required property string modelData; width: 6; height: 6; radius: 3; color: modelData }
                        }
                    }

                    // Fake prompt + colored "output" lines from the palette.
                    Column {
                        x: 10
                        y: 22
                        spacing: 5
                        Row {
                            spacing: 4
                            Rectangle { width: 10; height: 4; radius: 2; color: preview.palette.length > 2 ? preview.palette[2] : "#28c840" }
                            Rectangle { width: 44; height: 4; radius: 2; color: preview.termFg; opacity: 0.85 }
                        }
                        Repeater {
                            model: 5
                            Row {
                                required property int index
                                spacing: 4
                                Rectangle {
                                    width: 18 + (index * 13) % 30
                                    height: 4
                                    radius: 2
                                    color: preview.palette.length > index + 1 ? preview.palette[index + 1] : "#888888"
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                                Rectangle {
                                    width: 30 + (index * 29) % 60
                                    height: 4
                                    radius: 2
                                    color: preview.termFg
                                    opacity: 0.45
                                }
                            }
                        }
                    }
                }

                // Palette strip on the right: all 16 (or 8) colors.
                Grid {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: term.verticalCenter
                    columns: 4
                    spacing: 5
                    Repeater {
                        model: preview.palette
                        Rectangle {
                            required property string modelData
                            width: 16
                            height: 16
                            radius: 5
                            color: modelData
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1
                        }
                    }
                }
            }

            // ── Accent chips ──────────────────────────────────────────
            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 12

                Repeater {
                    model: panel.carouselItems

                    Item {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === panel.currentIndex
                        readonly property bool isActive: modelData.name === panel.activeThemeName
                        width: 34
                        height: 34

                        // Selection ring.
                        Rectangle {
                            anchors.centerIn: parent
                            width: chip.selected ? 34 : 26
                            height: width
                            radius: width / 2
                            color: "transparent"
                            border.width: 2
                            border.color: "#ffffff"
                            opacity: chip.selected ? 1 : 0
                            Behavior on width { SpringAnimation { spring: 5; damping: 0.4 } }
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        // Dynamic = multicolor conic chip, else flat accent.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            radius: 12
                            visible: !chip.modelData.isDynamic
                            color: chip.modelData.accent || "#ffffff"
                        }
                        ClippingRectangle {
                            anchors.centerIn: parent
                            width: 24
                            height: 24
                            radius: 12
                            visible: chip.modelData.isDynamic === true
                            color: "transparent"
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: "#ff453a" }
                                    GradientStop { position: 0.33; color: "#ffd60a" }
                                    GradientStop { position: 0.66; color: "#32d74b" }
                                    GradientStop { position: 1.0; color: "#0a84ff" }
                                }
                            }
                        }

                        // Active dot.
                        Rectangle {
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: 3
                            color: "#ffffff"
                            visible: chip.isActive
                            border.color: "#000000"
                            border.width: 1
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { panel.currentIndex = chip.index; themeFocusScope.forceActiveFocus() }
                            onDoubleClicked: { panel.currentIndex = chip.index; panel.applyCurrent() }
                        }
                    }
                }
            }

            // ── Name + apply ──────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Column {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: panel.currentItem ? panel.currentItem.name : ""
                        color: "#ffffff"
                        font.pixelSize: 15
                        font.weight: 700
                        font.family: Theme.font
                    }
                    Text {
                        text: panel.currentItem && panel.currentItem.isDynamic
                            ? "Colors follow the current wallpaper"
                            : "← → to browse · Enter to apply"
                        color: "#ffffff"
                        opacity: 0.4
                        font.pixelSize: 10
                        font.family: Theme.fontText
                    }
                }

                Rectangle {
                    implicitWidth: applyText.implicitWidth + 28
                    implicitHeight: 30
                    radius: 15
                    color: panel.browsingActive ? Theme.card : "#ffffff"
                    scale: applyMouse.pressed ? 0.94 : 1
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 } }

                    Text {
                        id: applyText
                        anchors.centerIn: parent
                        text: panel.browsingActive ? "✓ Active" : "Apply"
                        color: panel.browsingActive ? "#ffffff" : "#000000"
                        opacity: panel.browsingActive ? 0.6 : 1
                        font.pixelSize: 12
                        font.weight: 600
                        font.family: Theme.fontText
                    }

                    MouseArea {
                        id: applyMouse
                        anchors.fill: parent
                        enabled: !panel.browsingActive
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.applyCurrent()
                    }
                }
            }
        }
    }
}
