import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Keyboard-navigable wallpaper grid — GridView (not GridLayout+Repeater)
// so arrow-key highlight + Enter-to-apply work the same way this project's
// other keyboard-driven grids do, and so a long list scrolls its own
// content instead of relying on an outer Flickable. Inspired by a
// reference implementation the user shared (DynamicGlacier's own
// WallpaperPanel.qml), adapted to this project's own icon-masking/
// monochrome conventions rather than copied wholesale — no folder
// browsing, since this user's own wallpaper folder is flat.
ColumnLayout {
    id: panel
    property var monitor: null
    // Set from outside (true only while this is the actually-visible
    // overview sub-view) — this panel, like every other overview sub-view,
    // is a permanent sibling cross-faded via opacity rather than a fresh
    // Loader instance, so its OWN `visible` property never actually
    // changes and Component.onCompleted only ever fires once, long before
    // the panel is first opened. Re-grabbing focus on this instead is what
    // actually gets arrow keys/Enter routed here each time it opens.
    property bool panelActive: false
    onPanelActiveChanged: if (panel.panelActive) wallpaperFocusScope.forceActiveFocus()
    signal closeRequested()
    spacing: 10

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

    PanelHeader {
        Layout.fillWidth: true
        icon: "preferences-desktop-wallpaper-symbolic"
        title: "Wallpaper"
        subtitle: panel.monitor ? panel.monitor.folder : ""
        showRefresh: true
        onRefreshRequested: if (panel.monitor) panel.monitor.refresh()
        onCloseRequested: panel.closeRequested()
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: "#2a2a2a"
    }

    FocusScope {
        id: wallpaperFocusScope
        Layout.fillWidth: true
        Layout.fillHeight: true
        focus: true

        Keys.onLeftPressed: wallpaperGrid.moveCurrentIndexLeft()
        Keys.onRightPressed: wallpaperGrid.moveCurrentIndexRight()
        Keys.onUpPressed: wallpaperGrid.moveCurrentIndexUp()
        Keys.onDownPressed: wallpaperGrid.moveCurrentIndexDown()
        Keys.onReturnPressed: applyCurrent()
        Keys.onEnterPressed: applyCurrent()

        function applyCurrent() {
            const item = wallpaperGrid.model[wallpaperGrid.currentIndex]
            if (item && panel.monitor) panel.monitor.applyWallpaper(item)
        }

        GridView {
            id: wallpaperGrid
            anchors.fill: parent
            clip: true
            visible: panel.monitor && panel.monitor.images.length > 0
            model: panel.monitor ? panel.monitor.images : []
            cellWidth: width / 3
            cellHeight: 110
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400
            currentIndex: 0

            // Keeps the keyboard-highlighted tile in view rather than
            // letting arrow keys move the selection off-screen.
            onCurrentIndexChanged: wallpaperGrid.positionViewAtIndex(wallpaperGrid.currentIndex, GridView.Contain)

            delegate: Item {
                id: wallpaperTile
                required property string modelData
                required property int index

                readonly property bool isCurrent: panel.monitor && panel.monitor.currentPath === wallpaperTile.modelData
                readonly property bool keyHighlighted: wallpaperTile.GridView.isCurrentItem

                width: wallpaperGrid.cellWidth
                height: wallpaperGrid.cellHeight

                Rectangle {
                    id: tileFrame
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: 12
                    color: "#1a1a1a"
                    border.width: wallpaperTile.keyHighlighted ? 2 : 0
                    border.color: "#ffffff"
                    // clip lives on the inner clipping rectangle, not here
                    // — clipping a Rectangle that also draws a rounded
                    // border chops the border's own corners (Qt Quick
                    // clips to the bounding rect, not the antialiased
                    // rounded path). A plain `Item` with `clip: true` only
                    // clips to its rectangular bounding box, never an
                    // actually-rounded shape (confirmed live: the image
                    // corners stayed square even with one), so this needs
                    // Quickshell.Widgets' ClippingRectangle instead — same
                    // real limitation documented for `notch` in
                    // DynamicIsland.qml.
                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: wallpaperTile.keyHighlighted ? 2 : 1
                        radius: tileFrame.radius - 1
                        color: "transparent"

                        Image {
                            anchors.fill: parent
                            source: wallpaperTile.modelData
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            smooth: true
                            sourceSize.width: 360
                            sourceSize.height: 270
                        }
                    }

                    // Currently-applied wallpaper's badge — plain white
                    // fill, matching this project's existing monochrome
                    // "on/selected" convention (the toggle switches use
                    // the same white-fill/black-glyph pairing), not a
                    // colored accent. No border ring — a thin black/white
                    // outline at this size just anti-aliases into a fuzzy
                    // grey edge instead of reading as crisp.
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        width: 22
                        height: 22
                        radius: 11
                        color: "#ffffff"
                        visible: wallpaperTile.isCurrent

                        RowIcon {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            icon: "object-select-symbolic"
                            iconColor: "#000000"
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            wallpaperGrid.currentIndex = wallpaperTile.index
                            if (panel.monitor) panel.monitor.applyWallpaper(wallpaperTile.modelData)
                        }
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !panel.monitor || panel.monitor.images.length === 0
            text: "No images in this folder"
            color: "#ffffff"
            opacity: 0.4
            font.pixelSize: 12
            font.family: "SF Pro Display"
        }
    }
}
