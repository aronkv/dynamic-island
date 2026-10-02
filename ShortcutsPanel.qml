import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Live keyboard-shortcuts sheet (SUPER+H). Reads
// ~/.config/hypr/config/keybindings.lua's own text on every open rather
// than `hyprctl binds -j` — binds made through the Lua `hl.bind(...)`
// wrapper report back from hyprctl as an opaque `__lua` dispatcher, not the
// real command. Every `hl.bind(...)` line is parsed into
// { group, label, keys[] }: the island's `qs ipc call` targets, apps,
// windows, workspaces (the 1–0 loop), media/hardware keys and system
// actions; binds with the same label whose combos differ only in the last
// key (the four arrow binds, scroll up/down…) are merged into one row.
// Keys render as keycaps; the search field filters by label or key.
ColumnLayout {
    id: panel
    signal closeRequested()
    property bool active: false
    spacing: 10

    property var groups: []          // [{ name, rows: [{ label, keys: [..] }] }]
    property string query: ""

    onActiveChanged: if (active) { refresh(); searchInput.text = ""; searchInput.forceActiveFocus() }

    readonly property var ipcLabels: ({
        calculator: "Calculator", weather: "Weather", theme: "Themes", wallpaper: "Wallpapers",
        settings: "Settings", shortcuts: "Keyboard shortcuts", power: "Power menu", battery: "Battery",
        clipboard: "Clipboard history", calendar: "Calendar", tray: "Tray apps", launcher: "App launcher",
        overview: "Island · now playing (tap)"
    })
    readonly property var groupOrder: ["Island", "Apps", "Windows", "Workspaces", "Media & Hardware", "System"]

    function prettyKey(k) {
        const map = {
            "SUPER": "Super", "SHIFT": "⇧ Shift", "CONTROL": "Ctrl", "CTRL": "Ctrl", "ALT": "Alt",
            "Return": "↵ Return", "Escape": "Esc", "Space": "Space", "Super_L": "Super",
            "left": "←", "right": "→", "up": "↑", "down": "↓",
            "mouse:272": "Left drag", "mouse:273": "Right drag", "mouse_down": "Scroll ↓", "mouse_up": "Scroll ↑",
            "XF86AudioRaiseVolume": "Vol +", "XF86AudioLowerVolume": "Vol −", "XF86AudioMute": "Mute",
            "XF86AudioMicMute": "Mic mute", "XF86MonBrightnessUp": "Bright +", "XF86MonBrightnessDown": "Bright −",
            "XF86AudioNext": "Next", "XF86AudioPrev": "Prev", "XF86AudioPlay": "Play", "XF86AudioPause": "Play"
        }
        return map[k] !== undefined ? map[k] : (k.length === 1 ? k.toUpperCase() : k)
    }

    // action text → [group, label] (null = skip).
    function describe(action) {
        let m = action.match(/qs ipc call (\w+) (\w+)/)
        if (m) {
            if (m[1] === "lock") return ["System", "Lock screen"]
            if (m[1] === "brightness") return ["Media & Hardware", m[2] === "up" ? "Brightness up" : "Brightness down"]
            return ["Island", ipcLabels[m[1]] || (m[1].charAt(0).toUpperCase() + m[1].slice(1))]
        }
        if (/exec_cmd\(terminal \.\. " -e btop"\)/.test(action)) return ["Apps", "System monitor"]
        if (/exec_cmd\(terminal\)/.test(action)) return ["Apps", "Terminal"]
        if (/exec_cmd\(fileManager\)/.test(action)) return ["Apps", "File manager"]
        if (/exec_cmd\(editor\)/.test(action)) return ["Apps", "Editor"]
        if (/exec_cmd\(menu\)/.test(action)) return ["Island", "App launcher"]
        if (/hyprshutdown|dsp\.exit/.test(action)) return ["System", "Log out"]
        if (/hyprshot/.test(action)) return ["System", "Screenshot (region)"]
        if (/set-volume[^"]*\+/.test(action)) return ["Media & Hardware", "Volume up"]
        if (/set-volume[^"]*-/.test(action)) return ["Media & Hardware", "Volume down"]
        if (/SINK@ toggle/.test(action)) return ["Media & Hardware", "Mute"]
        if (/SOURCE@ toggle/.test(action)) return ["Media & Hardware", "Microphone mute"]
        if (/brightnessctl[^"]*\+/.test(action)) return ["Media & Hardware", "Brightness up"]
        if (/brightnessctl[^"]*-/.test(action)) return ["Media & Hardware", "Brightness down"]
        if (/playerctl next/.test(action)) return ["Media & Hardware", "Next track"]
        if (/playerctl previous/.test(action)) return ["Media & Hardware", "Previous track"]
        if (/playerctl play-pause/.test(action)) return ["Media & Hardware", "Play / pause"]
        if (/window\.close/.test(action)) return ["Windows", "Close window"]
        if (/window\.float/.test(action)) return ["Windows", "Toggle floating"]
        if (/window\.fullscreen/.test(action)) return ["Windows", "Fullscreen"]
        if (/window\.pseudo/.test(action)) return ["Windows", "Pseudo-tile"]
        if (/togglesplit/.test(action)) return ["Windows", "Toggle split"]
        if (/window\.drag/.test(action)) return ["Windows", "Move window with mouse"]
        if (/window\.resize/.test(action)) return ["Windows", "Resize window with mouse"]
        if (/window\.move\(\{ *direction/.test(action)) return ["Windows", "Move window"]
        if (/focus\(\{ *direction/.test(action)) return ["Windows", "Move focus"]
        if (/special:/.test(action)) return ["Workspaces", "Send window to scratchpad"]
        if (/toggle_special/.test(action)) return ["Workspaces", "Scratchpad"]
        if (/window\.move\(\{ *workspace *= *i/.test(action)) return ["Workspaces", "Send window to workspace"]
        if (/focus\(\{ *workspace *= *i/.test(action)) return ["Workspaces", "Switch workspace"]
        if (/workspace *= *"e[+-]1"/.test(action)) return ["Workspaces", "Cycle workspaces"]
        return null
    }

    function parse(text) {
        // Strip comments, then join multi-line hl.bind( … ) calls.
        const statements = []
        let buf = "", depth = 0
        for (const raw of text.split("\n")) {
            const line = raw.replace(/--.*$/, "")
            if (buf === "" && line.indexOf("hl.bind(") === -1) continue
            buf += " " + line.trim()
            depth += (line.match(/\(/g) || []).length - (line.match(/\)/g) || []).length
            if (depth <= 0) { statements.push(buf.trim()); buf = ""; depth = 0 }
        }
        const rows = []
        for (const st of statements) {
            const m = st.match(/hl\.bind\((.+?),\s*(hl\..*)\)\s*$/)
            if (!m) continue
            // Key part: mainMod .. " + X" | "COMBO" | mainMod .. " + SHIFT + " .. key
            const combo = m[1].replace(/mainMod\s*\.\.\s*/g, "SUPER").replace(/"/g, "").replace(/\s*\.\.\s*key/, "1–0")
            const keys = []
            for (const k of combo.split("+").map(x => x.trim()).filter(x => x !== "").map(panel.prettyKey))
                if (keys[keys.length - 1] !== k) keys.push(k)
            const d = panel.describe(m[2])
            if (!d) continue
            rows.push({ group: d[0], label: d[1], keys: keys })
        }
        // Merge rows with the same label whose keys differ only in the last
        // one: the last key becomes a list of alternatives (← → ↑ ↓).
        const merged = []
        const lastOf = r => [].concat(r.keys[r.keys.length - 1])
        for (const r of rows) {
            const prev = merged.find(x => x.label === r.label && x.group === r.group
                && x.keys.length === r.keys.length && x.keys.slice(0, -1).join("|") === r.keys.slice(0, -1).join("|"))
            if (prev) {
                const alts = lastOf(prev)
                for (const k of lastOf(r)) if (alts.indexOf(k) === -1) alts.push(k)
                prev.keys[prev.keys.length - 1] = alts.length > 1 ? alts : alts[0]
            } else {
                merged.push({ group: r.group, label: r.label, keys: r.keys.slice() })
            }
        }
        const out = []
        for (const g of groupOrder) {
            const gr = merged.filter(r => r.group === g)
            if (gr.length > 0) out.push({ name: g, rows: gr })
        }
        return out
    }

    readonly property var filteredGroups: {
        const q = query.trim().toLowerCase()
        if (q === "") return groups
        return groups.map(g => ({ name: g.name, rows: g.rows.filter(r =>
            r.label.toLowerCase().indexOf(q) !== -1 || g.name.toLowerCase().indexOf(q) !== -1
            || [].concat.apply([], r.keys).join(" ").toLowerCase().indexOf(q) !== -1) })).filter(g => g.rows.length > 0)
    }

    function refresh() { catProc.running = true }

    Process {
        id: catProc
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/config/keybindings.lua"]
        stdout: StdioCollector {
            onStreamFinished: panel.groups = panel.parse(text)
        }
    }

    Component.onCompleted: refresh()

    component Keycap: Rectangle {
        property string label: ""
        implicitWidth: Math.max(22, capText.implicitWidth + 12)
        implicitHeight: 22
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.1)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)
        // Bottom edge: a subtle key "depth".
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: 3
            anchors.rightMargin: 3
            height: 1
            color: Qt.rgba(0, 0, 0, 0.5)
        }
        Text {
            id: capText
            anchors.centerIn: parent
            text: parent.label
            color: "#ffffff"
            font.pixelSize: 11
            font.weight: 600
            font.family: Theme.fontText
        }
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: "input-keyboard-symbolic"
        title: "Shortcuts"
        subtitle: {
            let n = 0
            for (const g of panel.groups) n += g.rows.length
            return n + " shortcuts · from keybindings.lua"
        }
        showSettingsGear: false
        onCloseRequested: panel.closeRequested()
    }

    // Search pill.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 18
        color: Theme.card
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, searchInput.activeFocus ? 0.14 : 0.06)
        TextInput {
            id: searchInput
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            verticalAlignment: TextInput.AlignVCenter
            color: "#ffffff"
            font.pixelSize: 14
            font.family: Theme.fontText
            clip: true
            focus: true
            onTextChanged: panel.query = text
            Keys.onEscapePressed: {
                if (text !== "") text = ""
                else panel.closeRequested()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: searchInput.text.length === 0
                text: "Search shortcuts"
                color: "#ffffff"
                opacity: 0.35
                font: searchInput.font
            }
        }
    }

    Flickable {
        id: flick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: listColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: listColumn
            width: parent.width
            spacing: 6

            Repeater {
                model: panel.filteredGroups
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.leftMargin: 14
                        Layout.topMargin: 4
                        text: modelData.name.toUpperCase()
                        color: "#ffffff"
                        opacity: 0.45
                        font.pixelSize: 11
                        font.weight: 600
                        font.letterSpacing: 0.4
                        font.family: Theme.fontText
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: rowsCol.implicitHeight
                        radius: 14
                        color: Theme.card

                        Column {
                            id: rowsCol
                            width: parent.width
                            Repeater {
                                model: modelData.rows
                                delegate: Item {
                                    required property var modelData
                                    required property int index
                                    width: rowsCol.width
                                    height: 38
                                    Rectangle {
                                        visible: index > 0
                                        x: 14
                                        width: parent.width - 14
                                        height: 1
                                        color: Qt.rgba(1, 1, 1, 0.07)
                                    }
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 14
                                        anchors.right: caps.left
                                        anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData.label
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.family: Theme.fontText
                                        elide: Text.ElideRight
                                    }
                                    Row {
                                        id: caps
                                        anchors.right: parent.right
                                        anchors.rightMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Repeater {
                                            model: modelData.keys
                                            delegate: Row {
                                                required property var modelData
                                                required property int index
                                                spacing: 4
                                                Text {
                                                    visible: index > 0
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: "+"
                                                    color: "#ffffff"
                                                    opacity: 0.3
                                                    font.pixelSize: 11
                                                }
                                                // Alternatives (merged binds) become several caps.
                                                Repeater {
                                                    model: Array.isArray(modelData) ? modelData : [modelData]
                                                    delegate: Keycap { required property var modelData; label: modelData }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 20
                visible: panel.filteredGroups.length === 0
                text: panel.groups.length === 0 ? "No shortcuts found" : "No matches"
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 12
                font.family: Theme.fontText
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
