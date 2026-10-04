import Quickshell
import Quickshell.Bluetooth
import Quickshell.Widgets
import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: panel
    property var batteryMonitor: null
    property var networkMonitor: null
    property var bluetoothMonitor: null
    property var settingsStore: null
    property var weatherMonitor: null
    property var nightLight: null
    property var themeProfiles: null
    property var wallpaperMonitor: null
    property var calendarStore: null
    property string activeView: "overview"
    // Push/pop slides only for navigation inside an already-open panel.
    // Opening straight into a sub-view (SUPER+I, IPC…) sets activeView in
    // the same tick as the open, so it must appear in place, not slide in.
    property bool panelOpen: false
    property bool slideEnabled: false
    onPanelOpenChanged: {
        if (panelOpen) slideArm.restart()
        else { slideArm.stop(); slideEnabled = false }
    }
    Timer { id: slideArm; interval: 60; onTriggered: panel.slideEnabled = true }
    property bool mediaPlaying: false
    readonly property bool calcHistoryVisible: calculatorPanel.historyVisible
    readonly property bool calcGraphVisible: calculatorPanel.graphVisible
    readonly property bool calcSubVisible: calculatorPanel.subVisible
    readonly property real calcNaturalHeight: calculatorPanel.naturalHeight
    readonly property real trayNaturalHeight: trayPanel.naturalHeight
    function wifiShare() { wifiPanel.toggleShare() }
    function calcSetExpression(t) { calculatorPanel.setExpression(t) }
    function calcShowHelp() { calculatorPanel.helpOpen = true }
    signal backToNowPlaying()
    signal closeRequested()
    readonly property bool wifiPasswordEntryOpen: wifiPanel.passwordEntryOpen || wifiPanel.modifyEntryOpen

    onActiveViewChanged: {
        if (activeView === "wifi" && panel.networkMonitor) panel.networkMonitor.rescan()
        if (activeView === "bluetooth" && panel.bluetoothMonitor) panel.bluetoothMonitor.rescan()
    }

    // Turning the adapter on goes through a brief "Enabling" transition
    // (confirmed live via `bluetoothctl`: PowerState briefly reports
    // "off-enabling" before "on") — a rescan requested before that finishes
    // silently does nothing, which was the real cause of the device list
    // sometimes just staying empty. Retry once discovery is actually possible.
    Connections {
        target: panel.bluetoothMonitor
        function onStateChanged() {
            if (panel.activeView === "bluetooth" && panel.bluetoothMonitor.state === BluetoothAdapterState.Enabled) {
                panel.bluetoothMonitor.rescan()
            }
        }
    }

    // Minimal connectivity row (monochrome, no background): title +
    // status right-aligned, then a round icon — white disc with a black
    // icon when the radio is on, a faint outline when off. The icon toggles
    // the radio; the rest of the row opens the sub-view.
    component ConnTile: Item {
        id: tile
        property bool active: false
        property string icon: ""
        property string title: ""
        property string status: ""
        // Optional small secondary badge on the icon (Ethernet row: Wi-Fi
        // state), white when active, outlined when off.
        property string subIcon: ""
        property bool subActive: false
        signal toggleRequested()
        signal openRequested()
        implicitWidth: 150
        implicitHeight: 34
        opacity: tileMouse.containsMouse || badgeMouse.containsMouse ? 1 : 0.92

        MouseArea {
            id: tileMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.openRequested()
        }

        Column {
            anchors.right: tileBadge.left
            anchors.rightMargin: 10
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: tile.title
                color: "#ffffff"
                opacity: tileMouse.containsMouse ? 1 : 0.85
                font.pixelSize: 12
                font.weight: 600
                font.family: Theme.fontText
                elide: Text.ElideLeft
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: tile.status
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 10
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        Rectangle {
            id: tileBadge
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            radius: 15
            color: tile.active ? "#ffffff" : "transparent"
            border.width: tile.active ? 0 : 1
            border.color: Qt.rgba(1, 1, 1, badgeMouse.containsMouse ? 0.5 : 0.25)
            scale: badgeMouse.pressed ? 0.88 : 1
            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
            RowIcon {
                anchors.centerIn: parent
                width: 15
                height: 15
                icon: tile.icon
                iconColor: tile.active ? "#000000" : "#ffffff"
                opacity: tile.active ? 1 : 0.55
            }
            MouseArea {
                id: badgeMouse
                anchors.fill: parent
                anchors.margins: -3
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: tile.toggleRequested()
            }

            // Tiny vector Wi-Fi glyph (dot + 2 arcs) on a black disc — a
            // theme icon at 9 px turned to mush.
            Rectangle {
                visible: tile.subIcon !== ""
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -5
                anchors.bottomMargin: -5
                width: 17
                height: 17
                radius: 8.5
                color: "#000000"
                Item {
                    id: miniWifi
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: 1
                    width: 11
                    height: 11
                    readonly property color c: tile.subActive ? "#ffffff" : Qt.rgba(1, 1, 1, 0.35)
                    Rectangle {
                        x: 5.5 - width / 2
                        y: 8.2 - height / 2
                        width: 2.2
                        height: 2.2
                        radius: 1.1
                        color: miniWifi.c
                    }
                    Repeater {
                        model: 2
                        Shape {
                            required property int index
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                fillColor: "transparent"
                                strokeColor: miniWifi.c
                                strokeWidth: 1.4
                                capStyle: ShapePath.RoundCap
                                PathAngleArc {
                                    moveToStart: true
                                    centerX: 5.5; centerY: 8.2
                                    radiusX: 3.2 + index * 2.8; radiusY: radiusX
                                    startAngle: -135; sweepAngle: 90
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    component RowIcon: Item {
        id: rowIcon
        property string icon: ""
        property color iconColor: "#ffffff"
        implicitWidth: 16
        implicitHeight: 16

        IconImage {
            id: iconImg
            anchors.fill: parent
            source: rowIcon.icon !== "" ? "image://icon/" + rowIcon.icon : ""
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }

        Rectangle {
            id: flatFill
            anchors.fill: parent
            color: rowIcon.iconColor
            visible: false
        }

        MultiEffect {
            anchors.fill: iconImg
            source: flatFill
            maskEnabled: true
            maskSource: iconImg
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.0
            maskThresholdMax: 1.0
            maskSpreadAtMax: 0.0
        }
    }

    // Replaces every sub-view's old "‹ Back" text link — minimalist,
    // monochrome redesign (explicit user request to drop the accent red
    // from the whole panel chrome): a plain white circle with a "‹" glyph,
    // no icon file involved (reuses the same "‹" character the old text
    // link already rendered, just restyled, rather than risking another
    // Adwaita icon with the raster/filter hazard documented in CLAUDE.md).
    component BackButton: Item {
        id: backBtn
        signal clicked()
        implicitWidth: 28
        implicitHeight: 28

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#ffffff"

            Text {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: -1
                text: "‹"
                color: "#000000"
                font.pixelSize: 16
                font.weight: 700
                font.family: "SF Pro Display"
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: backBtn.clicked()
        }
    }

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        id: overviewContent
        anchors.fill: parent
        anchors.topMargin: 18
        anchors.bottomMargin: 18
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        spacing: 8
        opacity: panel.activeView === "overview" ? 1 : 0
        scale: panel.activeView === "overview" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "overview" ? 0 : -Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        IslandHeaderRow {
            Layout.fillWidth: true
            batteryMonitor: panel.batteryMonitor
            settingsStore: panel.settingsStore
            onNavigate: (target) => panel.activeView = target
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 12

            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignBottom
                // Clock/date opens the calendar.
                TapHandler { onTapped: panel.activeView = "calendar" }
                HoverHandler { cursorShape: Qt.PointingHandCursor }

                Text {
                    text: Qt.formatDateTime(sysClock.date, "HH:mm")
                    color: "#ffffff"
                    font.pixelSize: 28
                    font.weight: 700
                    font.family: "SF Mono"
                }

                Text {
                    text: Qt.formatDateTime(sysClock.date, "dd.MM.yyyy, ddd").toUpperCase()
                    color: "#ffffff"
                    opacity: 0.5
                    font.pixelSize: 13
                    font.family: "SF Pro Display"
                }
            }

            Item { Layout.fillWidth: true }

            // Control Center-style connectivity tiles: the round badge
            // toggles the radio (blue when on), the rest of the tile opens
            // the Wi-Fi / Bluetooth sub-view.
            ColumnLayout {
                spacing: 6
                Layout.alignment: Qt.AlignBottom

                ConnTile {
                    readonly property var nm: panel.networkMonitor
                    // Ethernet takes priority: when the cable is active the
                    // row becomes "Ethernet" (wired icon, white) and Wi-Fi
                    // shows as the small badge + the status line.
                    readonly property bool eth: nm ? nm.ethernetActive : false
                    active: nm ? (eth || nm.wifiEnabled) : false
                    icon: eth ? "network-wired-symbolic" : "network-wireless-symbolic"
                    title: eth ? "Ethernet" : "Wi-Fi"
                    subIcon: eth ? "network-wireless-symbolic" : ""
                    subActive: nm ? nm.activeWifiNetwork !== null : false
                    status: !nm ? "Not available"
                        : eth ? (!nm.wifiEnabled ? "Wi-Fi off" : nm.activeWifiNetwork ? "Wi-Fi · " + nm.activeWifiNetwork.name : "Wi-Fi on")
                        : !nm.wifiEnabled ? "Off"
                        : nm.activeWifiNetwork ? nm.activeWifiNetwork.name : "Not connected"
                    onToggleRequested: if (nm) nm.setWifiEnabled(!nm.wifiEnabled)
                    onOpenRequested: panel.activeView = "wifi"
                }

                ConnTile {
                    readonly property var bm: panel.bluetoothMonitor
                    readonly property var connected: bm ? bm.devices.find(d => d.connected) : null
                    active: bm ? bm.enabled : false
                    icon: "bluetooth-symbolic"
                    title: "Bluetooth"
                    status: !bm || !bm.adapter ? "Not available" : !bm.enabled ? "Off"
                        : connected ? connected.deviceName : "On"
                    onToggleRequested: if (bm && bm.adapter) bm.setEnabled(!bm.enabled)
                    onOpenRequested: panel.activeView = "bluetooth"
                }

                // Calculator/Weather/Theme/Wallpaper root rows removed —
                // each now opens directly via its own IPC-triggered
                // keybind (SUPER+C / SUPER+W / SUPER+SHIFT+T /
                // SUPER+SHIFT+W, see DynamicIsland.qml's IpcHandlers and
                // keybindings.lua) and is listed in the new Shortcuts help
                // panel (SUPER+H) instead of cluttering the root list. The
                // sub-view content blocks below (calculatorContent etc.)
                // are unchanged and still fully reachable.
            }
        }
    }

    ColumnLayout {
        id: batteryContent
        anchors.fill: parent
        anchors.margins: 24
        spacing: 10
        opacity: panel.activeView === "battery" ? 1 : 0
        scale: panel.activeView === "battery" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "battery" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        BatteryPanel {
            Layout.fillWidth: true
            monitor: panel.batteryMonitor
            onSettingsRequested: panel.activeView = "settings"
            onCloseRequested: panel.closeRequested()
        }

        Item { Layout.fillHeight: true }
    }

    ColumnLayout {
        id: wifiContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "wifi" ? 1 : 0
        scale: panel.activeView === "wifi" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "wifi" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        WifiPanel {
            id: wifiPanel
            Layout.fillWidth: true
            Layout.fillHeight: true
            monitor: panel.networkMonitor
            onSettingsRequested: panel.activeView = "settings"
            onCloseRequested: panel.closeRequested()
        }
    }

    ColumnLayout {
        id: bluetoothContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "bluetooth" ? 1 : 0
        scale: panel.activeView === "bluetooth" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "bluetooth" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        BluetoothPanel {
            id: bluetoothPanel
            Layout.fillWidth: true
            Layout.fillHeight: true
            monitor: panel.bluetoothMonitor
            onSettingsRequested: panel.activeView = "settings"
            onCloseRequested: panel.closeRequested()
        }
    }

    // Laid out at the settings view's final size (620×520 in
    // DynamicIsland's notch sizes, minus the 14 px margins) instead of
    // filling the springing notch: two columns reflowing on every frame of
    // the open made everything inside slide around.
    ColumnLayout {
        id: settingsContent
        anchors.top: parent.top
        anchors.topMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        width: 620 - 28
        height: 520 - 28
        spacing: 10
        opacity: panel.activeView === "settings" ? 1 : 0
        scale: panel.activeView === "settings" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "settings" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        SettingsPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            store: panel.settingsStore
            weatherMonitor: panel.weatherMonitor
            nightLight: panel.nightLight
            onCloseRequested: panel.closeRequested()
        }
    }

    ColumnLayout {
        id: calculatorContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "calculator" ? 1 : 0
        scale: panel.activeView === "calculator" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "calculator" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        CalculatorPanel {
            id: calculatorPanel
            active: panel.panelOpen && panel.activeView === "calculator"
            Layout.fillWidth: true
            Layout.fillHeight: true
            settingsStore: panel.settingsStore
            onCloseRequested: panel.closeRequested()
        }
    }

    ColumnLayout {
        id: calendarContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "calendar" ? 1 : 0
        scale: panel.activeView === "calendar" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "calendar" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        CalendarPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            store: panel.calendarStore
            active: panel.activeView === "calendar"
            onCloseRequested: panel.closeRequested()
        }
    }

    ColumnLayout {
        id: weatherContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "weather" ? 1 : 0
        scale: panel.activeView === "weather" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "weather" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        WeatherPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            monitor: panel.weatherMonitor
            onSettingsRequested: panel.activeView = "settings"
            onCloseRequested: panel.closeRequested()
        }
    }

    ColumnLayout {
        id: themeContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "theme" ? 1 : 0
        scale: panel.activeView === "theme" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "theme" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        ThemePanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            profiles: panel.themeProfiles
            settingsStore: panel.settingsStore
            wallpaperMonitor: panel.wallpaperMonitor
            panelActive: panel.activeView === "theme"
            onCloseRequested: panel.closeRequested()
        }
    }

    ColumnLayout {
        id: wallpaperContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "wallpaper" ? 1 : 0
        scale: panel.activeView === "wallpaper" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "wallpaper" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        WallpaperPanel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            monitor: panel.wallpaperMonitor
            panelActive: panel.activeView === "wallpaper"
            onCloseRequested: panel.closeRequested()
        }
    }

    ColumnLayout {
        id: shortcutsContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "shortcuts" ? 1 : 0
        scale: panel.activeView === "shortcuts" ? 1 : 0.97
        // Push/pop: sub-views slide in from the right, the root overview
        // slides out to the left.
        transform: Translate {
            x: panel.activeView === "shortcuts" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }


        ShortcutsPanel {
            active: panel.activeView === "shortcuts"
            id: shortcutsPanel
            Layout.fillWidth: true
            Layout.fillHeight: true
            onCloseRequested: panel.closeRequested()
        }

        onVisibleChanged: if (visible) shortcutsPanel.refresh()
    }

    ColumnLayout {
        id: trayContent
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10
        opacity: panel.activeView === "tray" ? 1 : 0
        scale: panel.activeView === "tray" ? 1 : 0.97
        transform: Translate {
            x: panel.activeView === "tray" ? 0 : Theme.panelSlide
            Behavior on x { enabled: panel.slideEnabled; NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
        }
        visible: opacity > 0

        FadeBehavior on opacity {}
        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        TrayPanel {
            id: trayPanel
            Layout.fillWidth: true
            active: panel.panelOpen && panel.activeView === "tray"
            onCloseRequested: panel.closeRequested()
        }

        Item { Layout.fillHeight: true }
    }
}
