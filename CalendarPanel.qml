import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "CalendarParse.js" as Parse

// Calendar sub-view (activeView "calendar", SUPER+K or the clock in the
// overview): month grid on the left (today filled, selection ring, a dot on
// days with reminders), the selected day's reminders on the right (or the
// upcoming ones when the day is empty), and a quick-add field at the bottom
// that understands "tomorrow 9:00 dentist" (CalendarParse.js) with a live
// preview of what will be saved. Reminders live in CalendarStore.
ColumnLayout {
    id: panel
    property var store: null
    property bool active: false
    signal closeRequested()
    spacing: 12

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var dayNames: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()
    property date selected: today

    function iso(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0") }
    function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate() }
    function shiftMonth(d) {
        let m = viewMonth + d, y = viewYear
        if (m < 0) { m = 11; y-- } else if (m > 11) { m = 0; y++ }
        viewMonth = m; viewYear = y
    }
    function goToday() {
        today = new Date()
        selected = today
        viewYear = today.getFullYear(); viewMonth = today.getMonth()
    }

    onActiveChanged: if (active) { goToday(); addInput.text = ""; addInput.forceActiveFocus() }

    // 42 cells, weeks starting on Monday.
    readonly property var cells: {
        const first = new Date(viewYear, viewMonth, 1)
        const offset = (first.getDay() + 6) % 7
        const out = []
        for (let i = 0; i < 42; i++) out.push(new Date(viewYear, viewMonth, 1 - offset + i))
        return out
    }
    readonly property var dayItems: store ? (store.reminders, store.forDay(iso(selected))) : []
    readonly property var upcomingItems: store ? (store.reminders, store.upcoming(5)) : []
    readonly property var preview: addInput.text.trim() === "" ? null : Parse.parse(addInput.text, new Date(), selected)

    function describe(p) {
        const d = new Date(+p.date.slice(0, 4), +p.date.slice(5, 7) - 1, +p.date.slice(8, 10))
        const t = new Date()
        const rel = sameDay(d, t) ? "Today" : sameDay(d, new Date(t.getFullYear(), t.getMonth(), t.getDate() + 1)) ? "Tomorrow"
            : dayNames[d.getDay()].slice(0, 3) + " " + d.getDate() + " " + monthNames[d.getMonth()].slice(0, 3)
        return rel + (p.time ? " · " + p.time : " · All day")
    }
    function submit() {
        const p = panel.preview
        if (!p || !store) return
        store.add(p.title, p.date, p.time)
        const d = new Date(+p.date.slice(0, 4), +p.date.slice(5, 7) - 1, +p.date.slice(8, 10))
        selected = d
        viewYear = d.getFullYear(); viewMonth = d.getMonth()
        addInput.text = ""
    }

    component MaskIcon: Item {
        id: mi
        property string name: ""
        property color tint: "#ffffff"
        width: 14
        height: 14
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

    component RoundButton: Rectangle {
        id: rb
        property string icon: ""
        property string label: ""
        signal clicked()
        implicitWidth: label !== "" ? rbText.implicitWidth + 20 : 28
        implicitHeight: 28
        radius: 14
        color: rbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Theme.card
        Behavior on color { ColorAnimation { duration: 120 } }
        MaskIcon { anchors.centerIn: parent; visible: rb.icon !== ""; name: rb.icon; opacity: 0.8 }
        Text {
            id: rbText
            anchors.centerIn: parent
            visible: rb.label !== ""
            text: rb.label
            color: "#ffffff"
            font.pixelSize: 12
            font.weight: 600
            font.family: Theme.fontText
        }
        MouseArea {
            id: rbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { rb.clicked(); addInput.forceActiveFocus() }
        }
    }

    component ReminderRow: Rectangle {
        id: rr
        property var item: null
        property bool showDate: false
        width: parent ? parent.width : 0
        height: 44
        radius: 12
        color: rrHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
        HoverHandler { id: rrHover }
        readonly property bool past: rr.item && panel.store ? panel.store.dueDate(rr.item) < new Date() : false

        Rectangle {
            id: bar
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 3
            height: 28
            radius: 1.5
            color: rr.past ? Qt.rgba(1, 1, 1, 0.25) : Theme.orange
        }
        Column {
            anchors.left: bar.right
            anchors.leftMargin: 10
            anchors.right: del.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: rr.item ? rr.item.title : ""
                color: "#ffffff"
                opacity: rr.past ? 0.5 : 1
                font.pixelSize: 13
                font.weight: 600
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: rr.item ? (rr.showDate ? panel.describe(rr.item) : (rr.item.time || "All day")) : ""
                color: "#ffffff"
                opacity: 0.45
                font.pixelSize: 11
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }
        Rectangle {
            id: del
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            opacity: rrHover.hovered ? 1 : 0
            color: delMouse.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.25) : "transparent"
            Behavior on opacity { NumberAnimation { duration: 120 } }
            MaskIcon {
                anchors.centerIn: parent
                width: 12
                height: 12
                name: "window-close-symbolic"
                tint: delMouse.containsMouse ? Theme.red : "#ffffff"
            }
            MouseArea {
                id: delMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (rr.item && panel.store) panel.store.remove(rr.item.id)
            }
        }
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: "x-office-calendar-symbolic"
        title: "Calendar"
        subtitle: {
            const n = panel.upcomingItems.length
            return n === 0 ? "No upcoming reminders" : n + (n === 1 ? " upcoming reminder" : (n === 5 ? "+" : "") + " upcoming reminders")
        }
        showSettingsGear: false
        onCloseRequested: panel.closeRequested()
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 14

        // ── Month grid ────────────────────────────────────────────────
        Rectangle {
            Layout.preferredWidth: 262
            Layout.fillHeight: true
            radius: Theme.radiusMedium
            color: Theme.card

            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                RowLayout {
                    width: parent.width
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: panel.monthNames[panel.viewMonth] + " " + panel.viewYear
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.weight: 700
                        font.family: Theme.font
                    }
                    RoundButton { icon: "go-previous-symbolic"; onClicked: panel.shiftMonth(-1) }
                    RoundButton { label: "Today"; onClicked: panel.goToday() }
                    RoundButton { icon: "go-next-symbolic"; onClicked: panel.shiftMonth(1) }
                }

                Row {
                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]
                        Text {
                            required property var modelData
                            required property int index
                            width: 34.5
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: "#ffffff"
                            opacity: index >= 5 ? 0.3 : 0.45
                            font.pixelSize: 10
                            font.weight: 600
                            font.family: Theme.fontText
                        }
                    }
                }

                Grid {
                    columns: 7
                    Repeater {
                        model: panel.cells
                        Item {
                            id: cell
                            required property var modelData
                            readonly property bool inMonth: modelData.getMonth() === panel.viewMonth
                            readonly property bool isToday: panel.sameDay(modelData, panel.today)
                            readonly property bool isSelected: panel.sameDay(modelData, panel.selected)
                            readonly property int count: panel.store ? (panel.store.countsByDay[panel.iso(modelData)] || 0) : 0
                            width: 34.5
                            height: 31

                            Rectangle {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -2
                                width: 26
                                height: 26
                                radius: 13
                                color: cell.isToday ? "#ffffff" : cellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                                border.width: cell.isSelected && !cell.isToday ? 1.5 : 0
                                border.color: Qt.rgba(1, 1, 1, 0.7)
                                Text {
                                    anchors.centerIn: parent
                                    text: cell.modelData.getDate()
                                    color: cell.isToday ? "#000000" : "#ffffff"
                                    opacity: cell.inMonth ? 1 : 0.25
                                    font.pixelSize: 12
                                    font.weight: cell.isToday || cell.isSelected ? 700 : 500
                                    font.family: Theme.fontText
                                    font.features: { "tnum": 1 }
                                }
                            }
                            Rectangle {
                                visible: cell.count > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 0
                                width: 4
                                height: 4
                                radius: 2
                                color: Theme.orange
                                opacity: cell.inMonth ? 1 : 0.4
                            }
                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    panel.selected = cell.modelData
                                    if (!cell.inMonth) { panel.viewYear = cell.modelData.getFullYear(); panel.viewMonth = cell.modelData.getMonth() }
                                    addInput.forceActiveFocus()
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Day / upcoming list ───────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 6

            Text {
                Layout.fillWidth: true
                text: (panel.sameDay(panel.selected, panel.today) ? "Today · " : "")
                    + panel.dayNames[panel.selected.getDay()] + ", " + panel.selected.getDate() + " " + panel.monthNames[panel.selected.getMonth()]
                color: "#ffffff"
                font.pixelSize: 14
                font.weight: 700
                font.family: Theme.font
                elide: Text.ElideRight
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentHeight: dayCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: dayCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: panel.dayItems
                        ReminderRow { required property var modelData; item: modelData }
                    }

                    Text {
                        visible: panel.dayItems.length === 0
                        topPadding: 4
                        bottomPadding: 10
                        text: "No reminders"
                        color: "#ffffff"
                        opacity: 0.4
                        font.pixelSize: 12
                        font.family: Theme.fontText
                    }

                    Text {
                        visible: panel.dayItems.length === 0 && panel.upcomingItems.length > 0
                        bottomPadding: 2
                        text: "UPCOMING"
                        color: "#ffffff"
                        opacity: 0.4
                        font.pixelSize: 10
                        font.weight: 600
                        font.letterSpacing: 0.5
                        font.family: Theme.fontText
                    }
                    Repeater {
                        model: panel.dayItems.length === 0 ? panel.upcomingItems : []
                        ReminderRow { required property var modelData; item: modelData; showDate: true }
                    }
                }
            }
        }
    }

    // ── Quick add ─────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 44
        radius: 22
        color: Theme.card
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, addInput.activeFocus ? 0.14 : 0.06)

        MaskIcon {
            id: addIcon
            anchors.left: parent.left
            anchors.leftMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            name: "list-add-symbolic"
            opacity: 0.5
        }

        TextInput {
            id: addInput
            anchors.left: addIcon.right
            anchors.leftMargin: 10
            anchors.right: previewText.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"
            font.pixelSize: 15
            font.family: Theme.font
            clip: true
            focus: true
            selectByMouse: true
            Keys.onReturnPressed: panel.submit()
            Keys.onEnterPressed: panel.submit()
            Keys.onEscapePressed: {
                if (text !== "") text = ""
                else panel.closeRequested()
            }
            Keys.onPressed: (event) => {
                // Month / day navigation while the field is empty.
                if (text !== "") return
                if (event.key === Qt.Key_PageUp) { panel.shiftMonth(-1); event.accepted = true }
                else if (event.key === Qt.Key_PageDown) { panel.shiftMonth(1); event.accepted = true }
                else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    const step = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 : event.key === Qt.Key_Up ? -7 : 7
                    const s = panel.selected
                    const d = new Date(s.getFullYear(), s.getMonth(), s.getDate() + step)
                    panel.selected = d
                    panel.viewYear = d.getFullYear(); panel.viewMonth = d.getMonth()
                    event.accepted = true
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: addInput.text.length === 0
                text: "Add a reminder — tomorrow 9:00 dentist"
                color: "#ffffff"
                opacity: 0.35
                font: addInput.font
            }
        }

        Text {
            id: previewText
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.preview !== null
            text: panel.preview ? panel.describe(panel.preview) + "  ↵" : ""
            color: Theme.orange
            font.pixelSize: 12
            font.weight: 600
            font.family: Theme.fontText
            width: visible ? implicitWidth : 0
        }
    }
}
