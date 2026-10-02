import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// System tray (StatusNotifierItem) host for Hyprland: Discord, Steam etc.
// park their icons here when their window is closed. Left click opens the
// app (or its menu for menu-only items), right click shows the app's own
// menu, middle click is the secondary action, the wheel scrolls.
//
// The menu is drawn inside the island (QsMenuOpener) rather than via
// item.display(): native platform menus need `//@ pragma UseQApplication`,
// which would switch the whole shell to QApplication mode.
ColumnLayout {
    id: panel
    // True while the tray view is on screen; leaving it drops any open menu.
    property bool active: false
    signal closeRequested()
    readonly property int count: SystemTray.items.values.length
    readonly property real naturalHeight: implicitHeight
    spacing: 14

    // Open menu levels, innermost last: [{ handle, title }]. Empty = grid.
    property var menuStack: []
    readonly property var currentMenu: menuStack.length > 0 ? menuStack[menuStack.length - 1] : null
    function openMenu(handle, title) { menuStack = menuStack.concat([{ handle: handle, title: title }]) }
    function popMenu() { menuStack = menuStack.slice(0, -1) }
    onActiveChanged: if (!active) menuStack = []
    // The app quit (its tray item and menu are gone) while the menu was open.
    onCountChanged: menuStack = []

    QsMenuOpener {
        id: opener
        menu: panel.currentMenu ? panel.currentMenu.handle : null
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: "view-app-grid-symbolic"
        title: "Tray"
        subtitle: panel.count === 0 ? "No apps in the tray"
            : panel.count === 1 ? "1 app running" : panel.count + " apps running"
        showSettingsGear: false
        onCloseRequested: panel.closeRequested()
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8
        visible: panel.count > 0 && !panel.currentMenu

        Repeater {
            model: SystemTray.items

            Rectangle {
                id: tile
                required property SystemTrayItem modelData
                readonly property string label: modelData.tooltipTitle || modelData.title || modelData.id
                width: 84
                height: 78
                radius: Theme.radiusMedium
                color: Qt.rgba(1, 1, 1, tileMouse.containsMouse ? 0.12 : 0.06)
                scale: tileMouse.pressed ? 0.94 : 1
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 0 : 140; easing.type: Easing.OutBack } }

                IconImage {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 12
                    implicitSize: 30
                    source: tile.modelData.icon
                    smooth: true
                    mipmap: true
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.label
                    color: "#ffffff"
                    opacity: 0.8
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    font.family: Theme.fontText
                }

                MouseArea {
                    id: tileMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    function showMenu() {
                        if (tile.modelData.hasMenu && tile.modelData.menu)
                            panel.openMenu(tile.modelData.menu, tile.label)
                    }

                    onClicked: (mouse) => {
                        const item = tile.modelData
                        if (!item) return
                        if (mouse.button === Qt.RightButton) showMenu()
                        else if (mouse.button === Qt.MiddleButton) item.secondaryActivate()
                        else if (item.onlyMenu) showMenu()
                        else { item.activate(); panel.closeRequested() }
                    }
                    onWheel: (wheel) => {
                        if (!tile.modelData) return
                        const horizontal = Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)
                        tile.modelData.scroll(horizontal ? wheel.angleDelta.x : wheel.angleDelta.y, horizontal)
                    }
                }
            }
        }
    }

    // The open menu: a back row with the app / submenu name, then entries.
    ColumnLayout {
        Layout.fillWidth: true
        visible: panel.currentMenu !== null
        spacing: 2

        Item {
            Layout.fillWidth: true
            implicitHeight: 28

            Rectangle {
                id: backDisc
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                radius: 12
                color: "#ffffff"
                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -1
                    text: "‹"
                    color: "#000000"
                    font.pixelSize: 15
                    font.weight: 700
                    font.family: "SF Pro Display"
                }
            }
            Text {
                anchors.left: backDisc.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: panel.currentMenu ? panel.currentMenu.title : ""
                color: "#ffffff"
                elide: Text.ElideRight
                font.pixelSize: 13
                font.weight: 600
                font.family: Theme.fontText
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.popMenu()
            }
        }

        Repeater {
            model: opener.children

            Item {
                id: row
                required property QsMenuEntry modelData
                Layout.fillWidth: true
                implicitHeight: modelData.isSeparator ? 9 : 32

                Rectangle {
                    visible: row.modelData.isSeparator
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: Qt.rgba(1, 1, 1, 0.12)
                }

                Rectangle {
                    visible: !row.modelData.isSeparator
                    anchors.fill: parent
                    radius: Theme.radiusSmall
                    color: Qt.rgba(1, 1, 1, rowMouse.containsMouse && row.modelData.enabled ? 0.1 : 0)
                    Behavior on color { ColorAnimation { duration: 120 } }

                    // Check / radio mark column (always reserved so labels align).
                    Text {
                        id: mark
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        text: row.modelData.buttonType === QsMenuButtonType.None ? ""
                            : row.modelData.checkState === Qt.Checked
                                ? (row.modelData.buttonType === QsMenuButtonType.RadioButton ? "●" : "✓") : ""
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.family: Theme.fontText
                    }
                    IconImage {
                        id: entryIcon
                        anchors.left: mark.right
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 16
                        visible: row.modelData.icon !== ""
                        source: row.modelData.icon
                    }
                    Text {
                        anchors.left: entryIcon.visible ? entryIcon.right : mark.right
                        anchors.leftMargin: 8
                        anchors.right: chevron.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.text.replace(/_(?!_)/g, "")
                        color: "#ffffff"
                        opacity: row.modelData.enabled ? 0.92 : 0.35
                        elide: Text.ElideRight
                        font.pixelSize: 13
                        font.family: Theme.fontText
                    }
                    Text {
                        id: chevron
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.hasChildren ? "›" : ""
                        color: "#ffffff"
                        opacity: 0.5
                        font.pixelSize: 15
                        font.family: "SF Pro Display"
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    enabled: !row.modelData.isSeparator && row.modelData.enabled
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const e = row.modelData
                        if (e.hasChildren) {
                            panel.openMenu(e, e.text.replace(/_(?!_)/g, ""))
                        } else {
                            e.triggered()
                            panel.closeRequested()
                        }
                    }
                }
            }
        }
    }

    Text {
        Layout.fillWidth: true
        visible: panel.count === 0
        horizontalAlignment: Text.AlignHCenter
        text: "Apps that minimize to the tray show up here."
        color: "#ffffff"
        opacity: 0.45
        wrapMode: Text.WordWrap
        font.pixelSize: 12
        font.family: Theme.fontText
    }
}
