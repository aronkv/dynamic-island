import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Notification history (displayState "notifications", SUPER+N): grouped by
// app, newest first, relative times. Click an entry → its default action
// (if the app is still listening) and it disappears; ✕ or a swipe sideways
// dismisses it; per-app "Clear" and a global "Clear all". Esc closes.
FocusScope {
    id: panel
    property var store: null
    property bool active: false
    signal closeRequested()

    onActiveChanged: if (active) { forceActiveFocus(); now = Date.now(); if (store) store.markRead() }
    Keys.onEscapePressed: panel.closeRequested()

    property real now: Date.now()
    Timer { interval: 30000; running: panel.active; repeat: true; onTriggered: panel.now = Date.now() }
    function ago(t) {
        const s = Math.max(0, Math.round((now - t) / 1000))
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m ago"
        if (s < 86400) return Math.floor(s / 3600) + "h ago"
        const d = new Date(t)
        return Qt.formatDate(d, "MMM d")
    }

    // [{ app, items: [...] }] — groups ordered by their newest entry.
    readonly property var groups: {
        const out = []
        const idx = {}
        for (const it of (store ? store.items : [])) {
            if (idx[it.app] === undefined) { idx[it.app] = out.length; out.push({ app: it.app, items: [] }) }
            out[idx[it.app]].items.push(it)
        }
        return out
    }

    component TextButton: Text {
        id: tb
        signal clicked()
        color: "#ffffff"
        opacity: tbMouse.pressed ? 0.4 : 0.6
        font.pixelSize: 11
        font.weight: 600
        font.family: Theme.fontText
        MouseArea {
            id: tbMouse
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "Notifications"
                color: "#ffffff"
                font.pixelSize: 17
                font.weight: 700
                font.family: Theme.font
            }
            Text {
                visible: panel.store && panel.store.items.length > 0
                text: panel.store ? String(panel.store.items.length) : ""
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 13
                font.family: Theme.fontText
                Layout.leftMargin: 4
            }
            Item { Layout.fillWidth: true }
            TextButton {
                visible: panel.store && panel.store.items.length > 0
                text: "Clear all"
                onClicked: panel.store.clearAll()
            }
        }

        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: col.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                width: scroller.width
                spacing: 14

                Repeater {
                    model: panel.groups

                    ColumnLayout {
                        id: group
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: group.modelData.app.toUpperCase()
                                color: "#ffffff"
                                opacity: 0.45
                                font.pixelSize: 10
                                font.weight: 600
                                font.letterSpacing: 0.5
                                font.family: Theme.fontText
                                Layout.fillWidth: true
                            }
                            TextButton {
                                text: "Clear"
                                font.pixelSize: 10
                                onClicked: panel.store.clearApp(group.modelData.app)
                            }
                        }

                        Repeater {
                            model: group.modelData.items

                            Item {
                                id: row
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: card.implicitHeight
                                clip: false

                                Rectangle {
                                    id: card
                                    width: parent.width
                                    implicitHeight: content.implicitHeight + 20
                                    radius: Theme.radiusMedium
                                    color: cardHover.hovered ? Qt.rgba(1, 1, 1, 0.1) : Theme.card
                                    opacity: 1 - Math.min(0.8, Math.abs(x) / (width * 0.6))
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Behavior on x { enabled: !swipe.drag.active; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                    HoverHandler { id: cardHover }

                                    RowLayout {
                                        id: content
                                        x: 12
                                        y: 10
                                        width: parent.width - 24
                                        spacing: 10

                                        Item {
                                            Layout.alignment: Qt.AlignTop
                                            implicitWidth: 32
                                            implicitHeight: 32
                                            IconImage {
                                                anchors.fill: parent
                                                visible: row.modelData.icon !== ""
                                                source: row.modelData.icon
                                                asynchronous: true
                                            }
                                            Rectangle {
                                                anchors.fill: parent
                                                visible: row.modelData.icon === ""
                                                radius: 8
                                                color: Theme.cardElevated
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: row.modelData.app.charAt(0).toUpperCase()
                                                    color: "#ffffff"
                                                    font.pixelSize: 14
                                                    font.weight: 700
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text {
                                                    text: row.modelData.summary
                                                    color: "#ffffff"
                                                    font.pixelSize: 13
                                                    font.weight: 600
                                                    font.family: Theme.font
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                                Text {
                                                    text: panel.ago(row.modelData.time)
                                                    color: "#ffffff"
                                                    opacity: 0.4
                                                    font.pixelSize: 10
                                                    font.family: Theme.fontText
                                                }
                                            }
                                            Text {
                                                visible: text !== ""
                                                text: row.modelData.body
                                                color: "#ffffff"
                                                opacity: 0.7
                                                font.pixelSize: 12
                                                font.family: Theme.fontText
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                    }

                                    // Click = action; drag sideways = dismiss.
                                    MouseArea {
                                        id: swipe
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        drag.target: card
                                        drag.axis: Drag.XAxis
                                        drag.threshold: 12
                                        onReleased: {
                                            if (Math.abs(card.x) > card.width * 0.35) panel.store.remove(row.modelData.uid)
                                            else card.x = 0
                                        }
                                        onClicked: if (Math.abs(card.x) < 4) panel.store.activate(row.modelData.uid)
                                    }

                                    // ✕ on hover.
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: -6
                                        width: 20
                                        height: 20
                                        radius: 10
                                        color: Theme.cardElevated
                                        border.color: Qt.rgba(1, 1, 1, 0.15)
                                        border.width: 1
                                        visible: cardHover.hovered
                                        Text {
                                            anchors.centerIn: parent
                                            text: "✕"
                                            color: "#ffffff"
                                            font.pixelSize: 10
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: panel.store.remove(row.modelData.uid)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Empty state.
            Column {
                anchors.centerIn: parent
                visible: !panel.store || panel.store.items.length === 0
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "🔔"
                    font.pixelSize: 28
                    opacity: 0.35
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications"
                    color: "#ffffff"
                    opacity: 0.4
                    font.pixelSize: 13
                    font.family: Theme.fontText
                }
            }
        }
    }
}
