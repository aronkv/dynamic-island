import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Clipboard history (displayState "clipboard", SUPER+SHIFT+V), type-first
// like the launcher: search field, category chips (All · Text · Links ·
// Code · Colors · Images · Files, with counts), then the history list —
// color swatches for colors, thumbnails for images, monospace for code.
// Keys: ↑/↓ select, Enter copies back and closes, Tab / Shift+Tab switch
// category, Delete removes the entry, Esc clears the search / closes.
// Click a row = copy; the trash icon on hover removes; "Clear" asks once.
FocusScope {
    id: panel
    property bool active: false
    property var monitor: null
    signal closeRequested()

    readonly property var categories: [
        { key: "all", label: "All" }, { key: "text", label: "Text" }, { key: "link", label: "Links" },
        { key: "code", label: "Code" }, { key: "color", label: "Colors" }, { key: "image", label: "Images" },
        { key: "file", label: "Files" }
    ]
    property string category: "all"
    property string query: ""
    property int currentIndex: 0
    property bool confirmClear: false
    property bool _mouseSelect: false

    readonly property var all: monitor ? monitor.entries : []
    readonly property var counts: {
        const c = { all: all.length }
        for (const e of all) c[e.kind] = (c[e.kind] || 0) + 1
        return c
    }
    readonly property var filtered: {
        const q = query.trim().toLowerCase()
        return all.filter(e => (category === "all" || e.kind === category)
            && (q === "" || e.text.toLowerCase().indexOf(q) !== -1 || e.meta.toLowerCase().indexOf(q) !== -1))
    }

    onActiveChanged: {
        searchInput.text = ""
        category = "all"
        currentIndex = 0
        confirmClear = false
        if (active) {
            if (monitor) monitor.refresh()
            searchInput.forceActiveFocus()
            list.positionViewAtBeginning()
        }
    }
    onFilteredChanged: if (currentIndex >= filtered.length) currentIndex = Math.max(0, filtered.length - 1)
    onCategoryChanged: { currentIndex = 0; list.positionViewAtBeginning() }
    onQueryChanged: { currentIndex = 0; list.positionViewAtBeginning() }

    function cycleCategory(d) {
        let i = categories.findIndex(c => c.key === category)
        // Skip empty categories (All is never empty-skipped).
        for (let n = 0; n < categories.length; n++) {
            i = (i + d + categories.length) % categories.length
            if (categories[i].key === "all" || (counts[categories[i].key] || 0) > 0) break
        }
        category = categories[i].key
    }
    function activate(i) {
        const e = filtered[i]
        if (!e || !monitor) return
        monitor.copy(e.id)
        panel.closeRequested()
    }
    function removeAt(i) {
        const e = filtered[i]
        if (e && monitor) monitor.remove(e.id)
    }

    readonly property var kindIcons: ({
        text: "format-justify-left-symbolic", link: "insert-link-symbolic", code: "utilities-terminal-symbolic",
        color: "color-select-symbolic", image: "image-x-generic-symbolic", file: "folder-symbolic"
    })

    component MaskIcon: Item {
        id: mi
        property string name: ""
        property color tint: "#ffffff"
        width: 16
        height: 16
        IconImage {
            id: miImg
            anchors.fill: parent
            source: mi.name !== "" ? "image://icon/" + mi.name : ""
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }
        Rectangle { id: miFill; anchors.fill: miImg; color: mi.tint; visible: false }
        MultiEffect {
            anchors.fill: miImg
            source: miFill
            maskEnabled: true
            maskSource: miImg
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.0
            maskThresholdMax: 1.0
            maskSpreadAtMax: 0.0
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 12
        spacing: 10

        // ── Search + clear ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: 22
                color: Theme.card
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.14 : 0.06)

                MaskIcon {
                    id: searchIconSlot
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    name: "edit-paste-symbolic"
                    opacity: 0.5
                }

                TextInput {
                    id: searchInput
                    anchors.left: searchIconSlot.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#ffffff"
                    font.pixelSize: 17
                    font.family: Theme.font
                    focus: true
                    clip: true
                    selectByMouse: true
                    onTextChanged: panel.query = text

                    Keys.onDownPressed: { panel._mouseSelect = false; panel.currentIndex = Math.min(panel.filtered.length - 1, panel.currentIndex + 1) }
                    Keys.onUpPressed: { panel._mouseSelect = false; panel.currentIndex = Math.max(0, panel.currentIndex - 1) }
                    Keys.onTabPressed: panel.cycleCategory(1)
                    Keys.onBacktabPressed: panel.cycleCategory(-1)
                    Keys.onReturnPressed: panel.activate(panel.currentIndex)
                    Keys.onEnterPressed: panel.activate(panel.currentIndex)
                    Keys.onEscapePressed: {
                        if (text !== "") text = ""
                        else panel.closeRequested()
                    }
                    Keys.onDeletePressed: (event) => {
                        // Delete removes the selected entry unless the cursor
                        // is inside typed text.
                        if (text !== "" && cursorPosition < text.length) { event.accepted = false; return }
                        panel.removeAt(panel.currentIndex)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: searchInput.text.length === 0
                        text: "Search clipboard history"
                        color: "#ffffff"
                        opacity: 0.35
                        font: searchInput.font
                    }
                }
            }

            // Clear all — first click arms, second click wipes.
            Rectangle {
                implicitWidth: clearLabel.implicitWidth + 28
                implicitHeight: 44
                radius: 22
                visible: panel.all.length > 0
                color: panel.confirmClear ? Theme.red : (clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Theme.card)
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: panel.confirmClear ? "Clear all?" : "Clear"
                    color: "#ffffff"
                    font.pixelSize: 13
                    font.weight: 600
                    font.family: Theme.fontText
                }
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (panel.confirmClear) { panel.monitor.wipe(); panel.confirmClear = false }
                        else { panel.confirmClear = true; disarm.restart() }
                        searchInput.forceActiveFocus()
                    }
                }
                Timer { id: disarm; interval: 3000; onTriggered: panel.confirmClear = false }
            }
        }

        // ── Category chips ────────────────────────────────────────────
        Row {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: panel.categories
                Rectangle {
                    required property var modelData
                    readonly property bool selected: panel.category === modelData.key
                    readonly property int count: panel.counts[modelData.key] || 0
                    visible: modelData.key === "all" || count > 0
                    width: chipRow.implicitWidth + 22
                    height: 28
                    radius: 14
                    color: selected ? "#ffffff" : (chipMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Theme.card)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            text: modelData.label
                            color: selected ? "#000000" : "#ffffff"
                            font.pixelSize: 12
                            font.weight: 600
                            font.family: Theme.fontText
                        }
                        Text {
                            text: count
                            color: selected ? "#000000" : "#ffffff"
                            opacity: 0.45
                            font.pixelSize: 11
                            font.weight: 600
                            font.family: Theme.fontText
                        }
                    }
                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { panel.category = modelData.key; searchInput.forceActiveFocus() }
                    }
                }
            }
        }

        // ── History list ──────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                anchors.centerIn: parent
                visible: panel.filtered.length === 0
                text: panel.monitor && panel.monitor.loading ? "Loading…"
                    : panel.all.length === 0 ? "Nothing copied yet"
                    : "No matches"
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 13
                font.family: Theme.fontText
            }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 2
                model: panel.filtered
                currentIndex: panel.currentIndex
                boundsBehavior: Flickable.StopAtBounds
                highlightMoveDuration: 0
                onCurrentIndexChanged: if (!panel._mouseSelect) positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === panel.currentIndex
                    readonly property bool isImage: modelData.kind === "image"
                    width: list.width
                    height: isImage ? 64 : 48
                    radius: 12
                    color: selected ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

                    HoverHandler {
                        id: rowHover
                        onHoveredChanged: if (hovered) { panel._mouseSelect = true; panel.currentIndex = row.index }
                    }

                    // Leading: swatch / thumbnail / kind icon.
                    Item {
                        id: lead
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: row.isImage ? 72 : 32
                        height: row.isImage ? 52 : 32

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            visible: !row.isImage
                            color: row.modelData.kind === "color" ? row.modelData.meta : Qt.rgba(1, 1, 1, 0.08)
                            border.width: row.modelData.kind === "color" ? 1 : 0
                            border.color: Qt.rgba(1, 1, 1, 0.2)
                            MaskIcon {
                                anchors.centerIn: parent
                                visible: row.modelData.kind !== "color"
                                name: panel.kindIcons[row.modelData.kind] || "edit-paste-symbolic"
                                opacity: 0.75
                            }
                        }
                        ClippingRectangle {
                            anchors.fill: parent
                            visible: row.isImage
                            radius: 8
                            color: Qt.rgba(1, 1, 1, 0.08)
                            Image {
                                anchors.fill: parent
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: 144
                                source: row.isImage && panel.monitor
                                    ? panel.monitor.thumbUrl(row.modelData.id) + "?v=" + panel.monitor.thumbVersion : ""
                            }
                        }
                    }

                    Column {
                        anchors.left: lead.right
                        anchors.leftMargin: 12
                        anchors.right: trash.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            text: row.isImage ? "Image" : row.modelData.text
                            color: "#ffffff"
                            font.pixelSize: row.modelData.kind === "code" ? 12 : 13
                            font.family: row.modelData.kind === "code" ? "monospace" : Theme.fontText
                            font.weight: row.isImage ? 600 : 400
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                        Text {
                            width: parent.width
                            visible: text !== ""
                            text: row.isImage ? row.modelData.meta
                                : row.modelData.kind === "link" ? row.modelData.meta
                                : row.modelData.kind === "color" ? "Color"
                                : ""
                            color: "#ffffff"
                            opacity: 0.45
                            font.pixelSize: 11
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }
                    }

                    // Trash (visible on hover / selection).
                    Item {
                        id: trash
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 28
                        opacity: row.selected ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: trashMouse.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.25) : "transparent"
                        }
                        MaskIcon {
                            anchors.centerIn: parent
                            width: 14
                            height: 14
                            name: "user-trash-symbolic"
                            tint: trashMouse.containsMouse ? Theme.red : "#ffffff"
                            opacity: trashMouse.containsMouse ? 1 : 0.5
                        }
                        MouseArea {
                            id: trashMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { panel.removeAt(row.index); searchInput.forceActiveFocus() }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 44
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.activate(row.index)
                    }
                }
            }
        }

        // ── Footer hints ──────────────────────────────────────────────
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "↵ Copy   ⇥ Category   Del Remove   Esc Close"
            color: "#ffffff"
            opacity: 0.3
            font.pixelSize: 10
            font.family: Theme.fontText
        }
    }
}
