import Quickshell.Widgets
import QtQuick
import QtQuick.Effects

// Shared header for the Battery/Bluetooth/Wifi/Settings detail panels —
// icon-in-a-circle + title + dynamic subtitle, with an optional toggle and
// refresh action, plus a gear (settings) and close (X) action that are
// always present. A genuine shared file (unlike most of this project's
// per-file inline `component` convention) since this exact markup is
// otherwise identically duplicated across four panels.
// Root is a plain Item and every child here is positioned with plain
// anchors — no RowLayout/ColumnLayout anywhere in this file. A RowLayout's
// own `width` turned out to be unreliable in this environment no matter
// how it was told to stretch (Layout.fillWidth from an ancestor Layout,
// wrapping it in a fillWidth Item, even a direct `width: parent.width`
// binding) — it kept collapsing back to its own implicit content width,
// so the trailing toggle/action icons always sat bunched up short of the
// panel's real right edge instead of reaching it (confirmed live and
// re-confirmed after each attempted fix, via a width debug log and via
// screenshots). Plain `Item`/anchors don't hit whatever that is, so the
// icon/title/action-cluster row below is built with anchors throughout.
Item {
    id: header
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property bool showToggle: false
    property bool toggleChecked: false
    property bool showRefresh: false
    // The Settings panel's own header hides this — a gear button that just
    // navigates to the panel you're already looking at would be circular.
    property bool showSettingsGear: true
    // iOS-style colored squircle behind the icon (Wi-Fi/Bluetooth blue,
    // Calculator orange); transparent = the neutral glass squircle.
    property color accent: "transparent"
    // false = no icon and no subtitle, just the title + toggle + actions
    // (Wi-Fi / Bluetooth, whose status card already says the rest).
    property bool showIdentity: true
    readonly property bool hasAccent: accent.a > 0
    signal toggled()
    signal refreshRequested()
    signal settingsRequested()
    signal closeRequested()
    implicitHeight: showIdentity ? Math.max(mainIconBadge.height, titleColumn.implicitHeight, iconCluster.implicitHeight, toggleSwitch.implicitHeight)
        : Math.max(titleColumn.implicitHeight, iconCluster.implicitHeight, toggleSwitch.implicitHeight)

    // Flat-fill-via-alpha-mask icon rendering — colorization blends toward the target color
    // proportional to the source glyph's own luminance rather than fully
    // replacing it, so a dark icon-theme SVG never reaches a true flat
    // color at colorization: 1.0. Masking a solid Rectangle with the icon's
    // alpha shape guarantees the exact target color everywhere.
    component MaskIcon: Item {
        id: maskIcon
        property string icon: ""
        property color iconColor: "#ffffff"

        IconImage {
            id: iconImg
            anchors.fill: parent
            source: maskIcon.icon !== "" ? "image://icon/" + maskIcon.icon : ""
            visible: false
            layer.enabled: true
            // Without these, the icon provider's raster gets point-scaled
            // to whatever size this instance requests (18/15px here vs. the
            // theme's native 16px grid), which looks distorted/pixelated —
            // same root cause and fix as IndicatorBadge.qml's mic/camera fix.
            smooth: true
            mipmap: true
        }

        Rectangle {
            id: flatFill
            anchors.fill: parent
            color: maskIcon.iconColor
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

    // Compact glass circle behind each action icon (iOS large-title bar).
    component ActionIcon: Item {
        id: actionIcon
        property string icon: ""
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: actionMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            scale: actionMouse.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        }

        MaskIcon {
            anchors.centerIn: parent
            width: 14
            height: 14
            icon: actionIcon.icon
            iconColor: "#ffffff"
            opacity: actionMouse.containsMouse ? 1 : 0.8
        }

        MouseArea {
            id: actionMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: actionIcon.clicked()
        }
    }

    // App-icon squircle: accent gradient with a top highlight and a soft
    // glow in the accent color, or neutral glass without an accent.
    RectangularShadow {
        id: iconGlow
        visible: header.hasAccent && header.showIdentity
        anchors.fill: mainIconBadge
        radius: mainIconBadge.radius
        blur: 16
        spread: 0
        offset.y: 3
        color: Qt.rgba(header.accent.r, header.accent.g, header.accent.b, 0.45)
    }
    Rectangle {
        id: mainIconBadge
        visible: header.showIdentity
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 42
        height: 42
        radius: 11
        color: header.hasAccent ? header.accent : Qt.rgba(1, 1, 1, 0.1)
        border.width: header.hasAccent ? 0 : 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
        gradient: header.hasAccent ? accentGradient : null
        Gradient {
            id: accentGradient
            GradientStop { position: 0; color: Qt.lighter(header.accent, 1.3) }
            GradientStop { position: 1; color: Qt.darker(header.accent, 1.15) }
        }
        // Glossy top highlight.
        Rectangle {
            visible: header.hasAccent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: parent.height / 2
            radius: parent.radius - 1
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.28) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }

    MaskIcon {
        id: mainIcon
        visible: header.showIdentity
        anchors.centerIn: mainIconBadge
        width: 22
        height: 22
        icon: header.icon
        iconColor: "#ffffff"
    }

    // The gear/refresh/close icons stay tight against each other at the
    // right edge (spacing handled per-icon rather than via a Layout — see
    // the file-level comment on why RowLayout itself isn't used here).
    Row {
        id: iconCluster
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            icon: "view-refresh-symbolic"
            visible: header.showRefresh
            onClicked: header.refreshRequested()
        }

        ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            icon: "emblem-system-symbolic"
            visible: header.showSettingsGear
            onClicked: header.settingsRequested()
        }

        ActionIcon {
            anchors.verticalCenter: parent.verticalCenter
            icon: "window-close-symbolic"
            onClicked: header.closeRequested()
        }
    }

    // The power toggle sits well clear of the icon cluster, not tucked
    // right against it — explicit follow-up request.
    ToggleSwitch {
        id: toggleSwitch
        implicitWidth: 50
        implicitHeight: 30
        anchors.right: iconCluster.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: header.showToggle
        checked: header.toggleChecked
        onToggled: header.toggled()
    }

    Column {
        id: titleColumn
        anchors.left: header.showIdentity ? mainIconBadge.right : parent.left
        anchors.leftMargin: header.showIdentity ? 12 : 2
        anchors.right: header.showToggle ? toggleSwitch.left : iconCluster.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        Text {
            width: parent.width
            text: header.title
            color: "#ffffff"
            font.pixelSize: 22
            font.weight: 700
            font.letterSpacing: -0.3
            font.family: "SF Pro Display"
            elide: Text.ElideRight
        }

        Text {
            width: parent.width
            text: header.subtitle
            color: "#ffffff"
            opacity: 0.55
            font.pixelSize: 12
            font.family: "SF Pro Text"
            elide: Text.ElideRight
            visible: header.showIdentity && header.subtitle.length > 0
        }
    }
}
