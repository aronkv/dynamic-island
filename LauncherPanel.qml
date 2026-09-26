import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Spotlight-style app launcher that grows out of the island
// (displayState "launcher").
//  • Search field on top.
//  • Starred apps as square tiles (only while the query is empty).
//  • A vertical list of apps below — all apps (most launched first) when
//    the query is empty, ranked matches while typing.
//  • A math expression adds a "= result" row (Enter copies it).
// Star/unstar: the ☆ on a row, Ctrl+S on the selected item, or right-click
// a tile. Keys: arrows move (tiles: ←/→, ↓ into the list), Enter launches,
// Esc clears / closes. Stars + launch counts live in launcher-history.json.
FocusScope {
    id: launcher
    property bool active: false
    signal closeRequested()

    property string query: ""
    property int currentIndex: 0
    // Mouse-driven selection must not auto-scroll the list: scrolling moves
    // a different row under the cursor, which re-selects, which scrolls…
    property bool _mouseSelect: false
    function selectFromMouse(i) { _mouseSelect = true; currentIndex = i }

    onActiveChanged: {
        searchInput.text = ""
        currentIndex = 0
        list.positionViewAtBeginning()
        if (active) searchInput.forceActiveFocus()
    }
    onQueryChanged: { currentIndex = 0; list.positionViewAtBeginning() }

    // ── Persistence: launch counts + favorites ─────────────────────────
    FileView {
        id: historyFile
        path: Quickshell.shellDir + "/launcher-history.json"
        printErrors: false
        watchChanges: false
        onAdapterUpdated: saveTimer.restart()
        JsonAdapter {
            id: history
            property var counts: ({})
            property var favorites: []
        }
    }
    // Debounced save (see CLAUDE.md: writeAdapter re-reads the file).
    Timer { id: saveTimer; interval: 200; onTriggered: historyFile.writeAdapter() }

    function bump(id) {
        const c = Object.assign({}, history.counts)
        c[id] = (c[id] || 0) + 1
        history.counts = c
    }
    function isFavorite(id) { return (history.favorites || []).indexOf(id) !== -1 }
    function toggleFavorite(id) {
        const f = (history.favorites || []).slice()
        const i = f.indexOf(id)
        if (i === -1) f.push(id)
        else f.splice(i, 1)
        history.favorites = f
    }

    // ── Data ───────────────────────────────────────────────────────────
    readonly property var apps: DesktopEntries.applications.values.filter(e => !e.noDisplay)

    readonly property var favoriteApps: {
        const favs = history.favorites || []
        const out = []
        for (const id of favs) {
            const e = apps.find(a => a.id === id)
            if (e) out.push(e)
        }
        return out
    }

    function score(entry, q) {
        const name = (entry.name || "").toLowerCase()
        const generic = (entry.genericName || "").toLowerCase()
        const kw = (entry.keywords || []).join(" ").toLowerCase()
        const cmd = (entry.command || []).join(" ").toLowerCase()
        if (name === q) return 100
        if (name.startsWith(q)) return 80
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 65
        if (name.includes(q)) return 50
        if (generic.includes(q)) return 35
        if (kw.includes(q)) return 30
        if (cmd.includes(q)) return 20
        let i = 0
        for (const ch of name) if (ch === q[i]) i++
        return i === q.length ? 10 : -1
    }

    readonly property bool searching: query.trim() !== ""

    readonly property var listApps: {
        const q = launcher.query.trim().toLowerCase()
        const counts = history.counts || {}
        if (q === "")
            return apps.slice().sort((a, b) => (counts[b.id] || 0) - (counts[a.id] || 0) || a.name.localeCompare(b.name))
        return apps.map(e => ({ entry: e, s: launcher.score(e, q) }))
            .filter(r => r.s >= 0)
            .map(r => ({ entry: r.entry, s: r.s + Math.min(20, (counts[r.entry.id] || 0) * 2) }))
            .sort((a, b) => b.s - a.s || a.entry.name.localeCompare(b.entry.name))
            .map(r => r.entry)
    }

    CalcEngine { id: calc }
    // Date / currency / unit answers ("100 usd", "5 km to mi", "days until
    // xmas") first, then plain math.
    readonly property var calcSmart: {
        const q = launcher.query.trim()
        if (q.length < 3) return null
        const r = calc.smart(q)
        return r && !r.pending && !r.error ? r : null
    }
    readonly property string calcResult: {
        if (calcSmart) return calcSmart.text
        const q = launcher.query.trim()
        if (q.length < 2 || !/[0-9]/.test(q) || !/[+\-*/^%()×÷]|sqrt|sin|cos|log|ln|pi/.test(q)) return ""
        try { return calc.format(calc.evaluate(q)) } catch (e) { return "" }
    }

    // One flat selection index across: [favorite tiles] + [calc row] + [list rows].
    readonly property int tileCount: searching ? 0 : favoriteApps.length
    readonly property int calcCount: calcResult !== "" ? 1 : 0
    readonly property int itemCount: tileCount + calcCount + listApps.length

    function itemAt(i) {
        if (i < tileCount) return { kind: "tile", entry: favoriteApps[i] }
        i -= tileCount
        if (i < calcCount) return { kind: "calc", entry: null }
        return { kind: "row", entry: listApps[i - calcCount] }
    }

    function moveH(d) {
        if (currentIndex < tileCount) currentIndex = Math.max(0, Math.min(tileCount - 1, currentIndex + d))
    }
    function moveV(d) {
        if (itemCount === 0) return
        if (currentIndex < tileCount) {
            const cols = tilesFlow.columns
            const next = currentIndex + d * cols
            if (d > 0 && next >= tileCount) currentIndex = tileCount       // into the list
            else if (next >= 0) currentIndex = next
            return
        }
        const next = currentIndex + d
        if (next < tileCount) currentIndex = Math.max(0, tileCount - 1)  // back up into the tiles
        else currentIndex = Math.max(0, Math.min(itemCount - 1, next))
    }

    function launchEntry(entry) {
        if (!entry) return
        bump(entry.id)
        if (entry.runInTerminal) {
            termProc.command = ["kitty", "-e"].concat(entry.command)
            termProc.startDetached()
        } else {
            entry.execute()
        }
        launcher.closeRequested()
    }

    function activate(i) {
        const it = itemAt(i)
        if (it.kind === "calc") {
            copyProc.command = ["wl-copy", "--", calcSmart ? calcSmart.copy : calcResult.replace(/ /g, "")]
            copyProc.running = true
            launcher.closeRequested()
            return
        }
        launchEntry(it.entry)
    }

    Process { id: copyProc }
    Process { id: termProc }

    component AppIcon: IconImage {
        property var entry: null
        source: entry ? Quickshell.iconPath(entry.icon, "application-x-executable") : ""
        asynchronous: true
        smooth: true
        mipmap: true
    }

    component SectionLabel: Text {
        color: "#ffffff"
        opacity: 0.4
        font.pixelSize: 11
        font.weight: 600
        font.letterSpacing: 0.4
        font.family: Theme.fontText
    }

    // Star button used on list rows.
    component StarButton: Item {
        id: star
        property bool on: false
        property bool shown: true
        signal toggled()
        implicitWidth: 26
        implicitHeight: 26
        opacity: shown || on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: star.on ? "★" : "☆"
            color: star.on ? Theme.yellow : "#ffffff"
            opacity: star.on ? 1 : (starMouse.containsMouse ? 0.9 : 0.45)
            font.pixelSize: 16
            scale: starMouse.pressed ? 0.8 : 1
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
        }
        MouseArea {
            id: starMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: star.toggled()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: 14
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 12
        spacing: 12

        // ── Search field ──────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: 22
            color: Theme.card
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.14 : 0.06)

            Item {
                id: searchIconSlot
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                IconImage {
                    id: searchIcon
                    anchors.fill: parent
                    source: "image://icon/system-search-symbolic"
                    visible: false
                    layer.enabled: true
                    smooth: true
                    mipmap: true
                }
                Rectangle { id: searchFill; anchors.fill: searchIcon; color: "#ffffff"; visible: false }
                MultiEffect {
                    anchors.fill: searchIcon
                    source: searchFill
                    maskEnabled: true
                    maskSource: searchIcon
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.0
                    maskThresholdMax: 1.0
                    maskSpreadAtMax: 0.0
                    opacity: 0.5
                }
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
                onTextChanged: launcher.query = text

                Keys.onDownPressed: launcher.moveV(1)
                Keys.onUpPressed: launcher.moveV(-1)
                Keys.onRightPressed: (event) => {
                    if (launcher.currentIndex < launcher.tileCount) launcher.moveH(1)
                    else event.accepted = false
                }
                Keys.onLeftPressed: (event) => {
                    if (launcher.currentIndex < launcher.tileCount) launcher.moveH(-1)
                    else event.accepted = false
                }
                Keys.onTabPressed: launcher.currentIndex = (launcher.currentIndex + 1) % Math.max(1, launcher.itemCount)
                Keys.onReturnPressed: launcher.activate(launcher.currentIndex)
                Keys.onEnterPressed: launcher.activate(launcher.currentIndex)
                Keys.onEscapePressed: {
                    if (text !== "") text = ""
                    else launcher.closeRequested()
                }
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) {
                        const it = launcher.itemAt(launcher.currentIndex)
                        if (it.entry) launcher.toggleFavorite(it.entry.id)
                        event.accepted = true
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: searchInput.text.length === 0
                    text: "Search apps or calculate"
                    color: "#ffffff"
                    opacity: 0.35
                    font: searchInput.font
                }
            }
        }

        // ── Favorite tiles ────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: launcher.tileCount > 0
            spacing: 8

            SectionLabel { text: "Favorites" }

            Grid {
                id: tilesFlow
                Layout.fillWidth: true
                columns: 6
                columnSpacing: 8
                rowSpacing: 8
                readonly property real tileSize: (width - columnSpacing * (columns - 1)) / columns

                Repeater {
                    model: launcher.searching ? [] : launcher.favoriteApps

                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        // Keyboard selection and mouse hover are separate and
                        // purely visual here: hover never changes the selection
                        // (that coupling made the tiles twitch while moving
                        // across them), it just lightens the tile instantly.
                        readonly property bool selected: launcher.currentIndex === index
                        readonly property bool hovered: tileHover.hovered
                        width: tilesFlow.tileSize
                        height: tilesFlow.tileSize
                        radius: 16
                        color: hovered ? Qt.rgba(1, 1, 1, 0.14) : Theme.card
                        border.width: 1.5
                        border.color: selected ? Qt.rgba(1, 1, 1, 0.45) : "transparent"
                        scale: tileMouse.pressed ? 0.95 : 1

                        AppIcon {
                            id: tileIcon
                            entry: tile.modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: parent.height * 0.16
                            implicitSize: parent.width * 0.42
                        }
                        Text {
                            anchors.top: tileIcon.bottom
                            anchors.topMargin: 5
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width - 10
                            horizontalAlignment: Text.AlignHCenter
                            text: tile.modelData.name
                            color: "#ffffff"
                            opacity: tile.selected || tile.hovered ? 1 : 0.8
                            font.pixelSize: 10
                            font.weight: 500
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }

                        HoverHandler { id: tileHover }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) launcher.toggleFavorite(tile.modelData.id)
                                else launcher.activate(tile.index)
                            }
                        }
                    }
                }
            }
        }

        SectionLabel {
            visible: !launcher.searching
            text: "All Apps"
        }

        // ── App list ──────────────────────────────────────────────────
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: launcher.calcCount + launcher.listApps.length
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: 400

            readonly property int selectedRow: launcher.currentIndex - launcher.tileCount
            onSelectedRowChanged: {
                if (selectedRow >= 0 && !launcher._mouseSelect) positionViewAtIndex(selectedRow, ListView.Contain)
                launcher._mouseSelect = false
            }

            delegate: Item {
                id: row
                required property int index
                readonly property bool isCalc: index < launcher.calcCount
                readonly property var entry: isCalc ? null : launcher.listApps[index - launcher.calcCount]
                readonly property bool selected: list.selectedRow === index
                readonly property bool hovered: rowHover.hovered
                width: list.width
                height: 44

                Rectangle {
                    anchors.fill: parent
                    radius: 11
                    color: row.selected ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                    Behavior on color { ColorAnimation { duration: 110 } }
                }

                // HoverHandler instead of MouseArea hover: it keeps reporting
                // while the cursor is over the ☆ (a child MouseArea), so the
                // star no longer vanishes exactly when you point at it.
                HoverHandler {
                    id: rowHover
                    onHoveredChanged: if (hovered) launcher.selectFromMouse(launcher.tileCount + row.index)
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: launcher.activate(launcher.tileCount + row.index)
                }

                Item {
                    id: iconSlot
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30

                    AppIcon {
                        anchors.fill: parent
                        visible: !row.isCalc
                        entry: row.entry
                    }
                    Rectangle {
                        anchors.fill: parent
                        visible: row.isCalc
                        radius: 8
                        color: Theme.orange
                        Text {
                            anchors.centerIn: parent
                            text: "="
                            color: "#ffffff"
                            font.pixelSize: 18
                            font.weight: 700
                        }
                    }
                }

                Column {
                    anchors.left: iconSlot.right
                    anchors.leftMargin: 12
                    anchors.right: trailing.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: row.isCalc ? launcher.calcResult : (row.entry ? row.entry.name : "")
                        color: "#ffffff"
                        font.pixelSize: row.isCalc ? 17 : 14
                        font.weight: 600
                        font.family: Theme.font
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: row.isCalc ? (launcher.calcSmart && launcher.calcSmart.sub ? launcher.calcSmart.sub : launcher.query.trim())
                            : row.entry ? (row.entry.genericName || row.entry.comment || "") : ""
                        color: "#ffffff"
                        opacity: 0.45
                        font.pixelSize: 11
                        font.family: Theme.fontText
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.selected && row.isCalc
                        width: hintText.implicitWidth + 14
                        height: 22
                        radius: 6
                        color: Qt.rgba(1, 1, 1, 0.1)
                        Text {
                            id: hintText
                            anchors.centerIn: parent
                            text: "Copy ↵"
                            color: "#ffffff"
                            opacity: 0.7
                            font.pixelSize: 10
                            font.weight: 600
                            font.family: Theme.fontText
                        }
                    }

                    StarButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.isCalc
                        on: row.entry ? launcher.isFavorite(row.entry.id) : false
                        shown: row.selected || row.hovered
                        onToggled: if (row.entry) launcher.toggleFavorite(row.entry.id)
                    }
                }
            }

            Text {
                anchors.centerIn: parent
                visible: list.count === 0
                text: "No results for “" + launcher.query.trim() + "”"
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 13
                font.family: Theme.fontText
            }
        }
    }
}
