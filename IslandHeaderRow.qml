import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Shared toggle+battery+gear header row, reused by QuickOverviewPanel.qml's
// plain overview screen and DynamicIsland.qml's media-expanded card, so the
// two don't drift out of sync with duplicated markup. Navigation is exposed
// as a signal rather than writing anywhere directly, since the two callers
// need different effects on click (QuickOverviewPanel just flips its own
// local activeView; DynamicIsland additionally has to leave mediaExpanded
// and open the overview panel first).
RowLayout {
    id: headerRow
    property var batteryMonitor: null
    property var settingsStore: null
    // Optional — only the media card passes these, folding wifi/bluetooth
    // directly into this header row for that one caller. Left null (as
    // QuickOverviewPanel.qml's plain overview screen does), no icons render
    // and the row looks exactly as it always has.
    property var networkMonitor: null
    property var bluetoothMonitor: null
    // Only the media card turns this on — the plain overview screen already
    // has its own big clock in a lower row, so this stays off there by
    // default (matching the null-monitor pattern used for wifi/bluetooth
    // above: opt-in per caller, no change to the existing look otherwise).
    property bool showClock: false
    signal navigate(string target)
    spacing: 12

    component RowIcon: Item {
        id: rowIcon
        property string icon: ""
        property color iconColor: "#ffffff"
        implicitWidth: 16
        implicitHeight: 16

        IconImage {
            id: iconImg
            anchors.fill: parent
            source: "image://icon/" + rowIcon.icon
            visible: false
            // Used as MultiEffect's maskSource below — needs a rendered
            // texture to sample (visible:false alone isn't enough), or the
            // mask has nothing to read and the icon renders blank.
            layer.enabled: true
            smooth: true
            mipmap: true
        }

        // Flat-fill via alpha mask instead of `colorization` — the icon
        // theme's actual SVGs (e.g. Adwaita's network-wireless-symbolic)
        // fill with a fairly dark grey (#2e3436), and MultiEffect's
        // colorization blends toward colorizationColor proportionally to
        // the source's own luminance rather than fully overwriting every
        // opaque pixel, so a dark source never quite reaches a true flat
        // white/bright color even at colorization: 1.0 — confirmed as the
        // cause of the wifi icon visibly looking dimmer/greyer than
        // adjacent plain-white/cream Text next to it in the same row.
        // Using the icon purely as an alpha mask over a solid,
        // flat-colored Rectangle guarantees every visible pixel is the
        // exact target color, independent of the source glyph's shading.
        Rectangle {
            id: flatFill
            anchors.fill: parent
            color: rowIcon.iconColor
            visible: false

            Behavior on color { ColorAnimation { duration: 150 } }
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

    // "Liquid Glass" (hyprglass) toggle, wired to SettingsStore.blurEnabled.
    ToggleSwitch {
        implicitWidth: 26
        implicitHeight: 14
        Layout.leftMargin: 4
        Layout.topMargin: 4
        checked: headerRow.settingsStore ? headerRow.settingsStore.blurEnabled : false
        onToggled: if (headerRow.settingsStore) headerRow.settingsStore.blurEnabled = !headerRow.settingsStore.blurEnabled
    }

    Item { Layout.fillWidth: true }

    Clock {
        visible: headerRow.showClock
        Layout.alignment: Qt.AlignVCenter
    }

    Item {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 2
        implicitWidth: battRow.implicitWidth
        implicitHeight: battRow.implicitHeight

        RowLayout {
            id: battRow
            spacing: 6

            RowIcon { icon: headerRow.batteryMonitor ? headerRow.batteryMonitor.iconName : "battery-symbolic" }

            Text {
                text: headerRow.batteryMonitor ? Math.round(headerRow.batteryMonitor.percentage) + "%" : "—"
                color: "#ffffff"
                font.pixelSize: 13
                font.family: "SF Pro Display"
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: headerRow.navigate("battery")
        }
    }

    // Wifi/bluetooth icons — only rendered when both monitors are supplied
    // (the media card's usage). Siblings of the battery/gear Items below,
    // not nested in them, for the same z-ordering reason noted above.
    Item {
        visible: headerRow.networkMonitor !== null && headerRow.bluetoothMonitor !== null
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 2
        implicitWidth: visible ? wifiIcon.implicitWidth : 0
        implicitHeight: wifiIcon.implicitHeight

        RowIcon {
            id: wifiIcon
            // Shows the primary connection (ethernet wins over Wi-Fi when
            // both are up); dim when nothing is connected.
            icon: headerRow.networkMonitor ? headerRow.networkMonitor.primaryIcon : "network-wireless-symbolic"
            opacity: headerRow.networkMonitor && headerRow.networkMonitor.primaryType !== "none" ? 1 : 0.5
        }

        MouseArea {
            anchors.fill: parent
            onClicked: headerRow.navigate("wifi")
        }
    }

    Item {
        visible: headerRow.networkMonitor !== null && headerRow.bluetoothMonitor !== null
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 2
        implicitWidth: visible ? btIcon.implicitWidth : 0
        implicitHeight: btIcon.implicitHeight

        RowIcon {
            id: btIcon
            icon: "bluetooth-symbolic"
            // .find() returns undefined, not false — !! coerces it for the bool.
            readonly property bool btConnected: !!(headerRow.bluetoothMonitor && headerRow.bluetoothMonitor.enabled
                && headerRow.bluetoothMonitor.devices.find(d => d.connected))
            iconColor: btConnected ? "#ffffff" : "#ffffff"
            opacity: btConnected ? 1 : 0.5
        }

        MouseArea {
            anchors.fill: parent
            onClicked: headerRow.navigate("bluetooth")
        }
    }

    // Sibling of (not nested inside) the battery Item above — z only
    // resolves stacking among siblings sharing a parent, so keeping this
    // fully separate avoids any ambiguity about which MouseArea wins a
    // click (see the same fix already applied once in QuickOverviewPanel.qml).
    Item {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 2
        implicitWidth: gearIcon.implicitWidth
        implicitHeight: gearIcon.implicitHeight

        RowIcon { id: gearIcon; icon: "emblem-system-symbolic" }

        MouseArea {
            anchors.fill: parent
            onClicked: headerRow.navigate("settings")
        }
    }
}
