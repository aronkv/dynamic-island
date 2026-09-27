import Quickshell.Widgets
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Spotlight-style calculator: one input line, the live result right under
// it. Supports + − × ÷ ^ %, parentheses, functions (sqrt sin cos tan asin
// acos atan log ln abs round floor ceil), constants pi / e, and `ans` (the
// last committed result). Enter commits to a small history (click an entry
// to reuse it), clicking the result copies it.
//
// Deliberately NOT eval()/Function(): a small hand-written recursive-descent
// parser only knows numbers, the operators above and a fixed whitelist of
// names, so there's no code-injection surface whatever is typed.
ColumnLayout {
    id: panel
    signal closeRequested()
    property var settingsStore: null
    property bool historyOpen: false
    // True while the calculator is the visible view. Each time it becomes
    // visible the input takes the keyboard focus again (another sub-view,
    // e.g. Settings, may have taken it in the meantime), so typing works
    // right away. Retried shortly after, once the focus grab has landed.
    property bool active: false
    onActiveChanged: if (active) { exprInput.forceActiveFocus(); refocusTimer.restart() }
    Timer { id: refocusTimer; interval: 120; onTriggered: if (panel.active) exprInput.forceActiveFocus() }
    property bool helpOpen: false
    // Last equation/inequality analysis (drives the graph), null otherwise.
    property var analysis: null
    readonly property bool graphVisible: analysis !== null && errorText === ""
    readonly property bool historyVisible: historyOpen || (settingsStore ? settingsStore.calcHistoryAlways : false)
    spacing: 10

    property var history: []        // [{expr, result}], newest first, max 4
    CalcEngine { id: engine }
    // Kept as a property so older callers (`panel.ans`) keep working.
    property alias ans: engine.ans

    property string resultText: ""
    property real resultValue: 0
    property string errorText: ""
    // Detail line under the result (conversions, dates) and what the copy
    // action copies for those (plain number / ISO date).
    property string subText: ""
    property string copyText: ""
    // Natural height of header + left column (the island sizes to it).
    readonly property real naturalHeight: headerRow.implicitHeight + spacing + leftCol.implicitHeight
    readonly property bool subVisible: subText !== "" && errorText === ""

    Connections {
        target: engine
        function onRatesChanged() { panel.runCalculation() }
    }

    function runCalculation() {
        const expr = exprInput.text.trim()
        panel.errorText = ""
        panel.subText = ""
        panel.copyText = ""
        if (expr.length === 0) { panel.resultText = ""; panel.analysis = null; return }
        const sm = engine.smart(expr)
        if (sm) {
            panel.analysis = null
            if (sm.pending) { panel.resultText = "…"; panel.subText = "Loading exchange rates"; return }
            if (sm.error) { panel.resultText = ""; panel.errorText = sm.error; return }
            panel.resultText = sm.text
            panel.resultValue = sm.value
            panel.subText = sm.sub || ""
            panel.copyText = sm.copy || ""
            return
        }
        try {
            if (/[=<>≤≥]/.test(expr)) {
                // Equation / inequality in x.
                const res = engine.analyze(expr)
                panel.analysis = res
                panel.resultValue = res.roots.length > 0 ? res.roots[0] : 0
                panel.resultText = res.text
                return
            }
            panel.analysis = null
            const v = engine.evaluate(expr)
            panel.resultValue = v
            panel.resultText = engine.format(v)
        } catch (e) {
            if (e && e.incomplete) return   // keep the last result while typing
            panel.resultText = ""
            panel.analysis = null
            panel.errorText = /Unknown name: x$/.test(e && e.message) ? "Add = to solve for x, e.g. 2x+3=7"
                : (e && e.message ? e.message : "Invalid expression")
        }
    }

    function setExpression(t) { exprInput.text = t; exprInput.cursorPosition = t.length }
    function copyCurrent() {
        if (panel.resultText !== "") {
            if (panel.copyText !== "") panel.copyResult(panel.copyText, true)
            else panel.copyResult(panel.resultText)
        } else if (panel.history.length > 0) {
            if (panel.history[0].copy) panel.copyResult(panel.history[0].copy, true)
            else panel.copyResult(panel.history[0].result)
        }
    }

    function commit() {
        runCalculation()
        if (panel.resultText === "" || panel.errorText !== "") return
        const h = panel.history.slice()
        if (panel.resultText === "…") return
        h.unshift({ expr: exprInput.text.trim(), result: panel.resultText, copy: panel.copyText })
        panel.history = h.slice(0, 4)
        panel.ans = panel.resultValue
        exprInput.text = ""
        panel.resultText = ""
    }

    Process { id: copyProc }
    property bool copiedFlash: false
    Timer { id: copiedTimer; interval: 1200; onTriggered: panel.copiedFlash = false }
    function copyResult(text, exact) {
        copyProc.command = ["wl-copy", "--", exact ? text : text.replace(/ /g, "")]
        copyProc.running = true
        panel.copiedFlash = true
        copiedTimer.restart()
    }

    // ── Chips ──────────────────────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property color tint: Qt.rgba(1, 1, 1, 0.08)
        property color textColor: "#ffffff"
        signal clicked()
        implicitWidth: chipText.implicitWidth + 22
        implicitHeight: 28
        radius: 14
        color: chipMouse.containsMouse ? Qt.lighter(tint, 1.6) : tint
        scale: chipMouse.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 110 } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: chip.textColor
            font.pixelSize: 12
            font.weight: 600
            font.family: Theme.fontText
        }
        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.clicked()
        }
    }

    component IconButton: Rectangle {
        id: ib
        property string icon: ""
        property string glyph: ""
        property bool on: false
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: on ? Qt.rgba(1, 1, 1, 0.18) : ibMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            visible: ib.glyph !== ""
            text: ib.glyph
            color: "#ffffff"
            font.pixelSize: 12
            font.weight: 700
        }
        Item {
            anchors.centerIn: parent
            width: 15
            height: 15
            visible: ib.icon !== ""
            IconImage {
                id: ibIcon
                anchors.fill: parent
                source: ib.icon ? "image://icon/" + ib.icon : ""
                visible: false
                layer.enabled: true
                smooth: true
                mipmap: true
            }
            Rectangle { id: ibFill; anchors.fill: parent; color: "#ffffff"; visible: false }
            MultiEffect {
                anchors.fill: parent
                source: ibFill
                maskEnabled: true
                maskSource: ibIcon
                maskThresholdMin: 0.5
                maskSpreadAtMin: 0.0
                maskThresholdMax: 1.0
                maskSpreadAtMax: 0.0
            }
        }
        MouseArea { id: ibMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ib.clicked() }
    }

    // What kind of answer is showing (label on the result card).
    readonly property string modeLabel: errorText !== "" ? "Error"
        : analysis ? (analysis.kind === "inequality" ? "Inequality" : "Equation")
        : subVisible ? "Conversion"
        : resultText !== "" ? "Result"
        : history.length > 0 ? "Last result" : ""

    // ── Header ─────────────────────────────────────────────────────────
    RowLayout {
        id: headerRow
        Layout.fillWidth: true
        spacing: 10
        Text {
            text: "Calculator"
            color: "#ffffff"
            font.pixelSize: 22
            font.weight: 700
            font.letterSpacing: -0.3
            font.family: Theme.font
            Layout.fillWidth: true
        }
        IconButton {
            glyph: "?"
            on: panel.helpOpen
            onClicked: { panel.helpOpen = !panel.helpOpen; exprInput.forceActiveFocus() }
        }
        IconButton {
            visible: !(panel.settingsStore && panel.settingsStore.calcHistoryAlways)
            icon: "document-open-recent-symbolic"
            on: panel.historyOpen
            onClicked: { panel.historyOpen = !panel.historyOpen; exprInput.forceActiveFocus() }
        }
        IconButton {
            glyph: "✕"
            onClicked: panel.closeRequested()
        }
    }

    RowLayout {
    Layout.fillWidth: true
    Layout.fillHeight: panel.historyVisible
    Layout.alignment: Qt.AlignTop
    spacing: 12

    ColumnLayout {
    id: leftCol
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: 8

    // ── Input card ─────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 54
        radius: 16
        color: Theme.card
        border.width: 1
        border.color: exprInput.activeFocus ? Qt.rgba(1, 1, 1, 0.55) : "transparent"
        Behavior on border.color { ColorAnimation { duration: 150 } }

        TextInput {
            id: exprInput
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"
            font.pixelSize: 22
            font.family: Theme.font
            clip: true
            focus: true
            selectByMouse: true
            selectionColor: Qt.rgba(1, 0.62, 0.04, 0.45)

            onTextChanged: {
                if (text.length > 0) panel.helpOpen = false   // typing replaces the help with the result
                panel.runCalculation()
            }
            Keys.onReturnPressed: panel.commit()
            Keys.onEnterPressed: panel.commit()
            Keys.onEscapePressed: {
                if (panel.helpOpen) panel.helpOpen = false
                else if (text.length > 0) text = ""
                else panel.closeRequested()
            }
            Keys.onUpPressed: if (panel.history.length > 0) text = panel.history[0].expr
            Keys.onPressed: (event) => {
                // "?" on an empty line (or Ctrl+/) toggles the help sheet.
                if ((event.text === "?" && text.length === 0)
                        || (event.key === Qt.Key_Slash && (event.modifiers & Qt.ControlModifier))) {
                    panel.helpOpen = !panel.helpOpen
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_H && (event.modifiers & Qt.ControlModifier)) {
                    panel.historyOpen = !panel.historyOpen
                    event.accepted = true
                    return
                }
                if (event.key === Qt.Key_L && (event.modifiers & Qt.ControlModifier)) {
                    panel.history = []
                    event.accepted = true
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: exprInput.text.length === 0
                text: "Challenge me…"
                color: "#ffffff"
                opacity: 0.28
                font.pixelSize: 18
                font.family: Theme.fontText
            }
        }
    }

    // ── Help sheet ("?" / Ctrl+/): what the calculator understands ───────
    Rectangle {
        id: helpCard
        Layout.fillWidth: true
        visible: panel.helpOpen
        implicitHeight: helpCol.implicitHeight + 24
        radius: 16
        color: Theme.card
        opacity: panel.helpOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 200; easing.type: Easing.OutCubic } }

        readonly property var sections: [
            { title: "MATH", desc: "+ − × ÷ ^ %, sqrt sin cos tan log ln abs round, pi, e, ans (degrees)",
              ex: ["sqrt(2)^3", "80*15%", "sin(30)", "log(1000)", "2pi"] },
            { title: "EQUATIONS & INEQUALITIES", desc: "Solve for x, with a graph",
              ex: ["2x+3=7", "x^2-4=0", "x^2-4>=0", "sin(x)=0.5"] },
            { title: "CURRENCY", desc: "Live ECB rates",
              ex: ["100 usd to huf", "50 eur"] },
            { title: "UNITS", desc: "Length, weight, temperature, data…",
              ex: ["5 km to miles", "70 kg to lb", "30 c to f", "1 gb to mb"] },
            { title: "DATES", desc: "Countdowns and date math",
              ex: ["days until christmas", "today + 90 days"] }
        ]

        ColumnLayout {
            id: helpCol
            x: 16
            y: 12
            width: parent.width - 32
            spacing: 10
            Repeater {
                model: helpCard.sections
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 5
                    Text {
                        text: modelData.title
                        color: "#ffffff"
                        opacity: 0.45
                        font.pixelSize: 10
                        font.weight: 700
                        font.letterSpacing: 0.6
                        font.family: Theme.fontText
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.desc
                        color: "#ffffff"
                        opacity: 0.7
                        font.pixelSize: 11
                        font.family: Theme.fontText
                        wrapMode: Text.WordWrap
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: modelData.ex
                            Chip {
                                required property string modelData
                                label: modelData
                                onClicked: { panel.helpOpen = false; panel.setExpression(modelData); exprInput.forceActiveFocus() }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Result card ────────────────────────────────────────────────────
    Rectangle {
        id: resultCard
        visible: !panel.helpOpen
        Layout.fillWidth: true
        implicitHeight: resultCol.implicitHeight + 24
        radius: 16
        color: Theme.card

        ColumnLayout {
            id: resultCol
            x: 16
            y: 12
            width: parent.width - 32
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: panel.modeLabel.toUpperCase()
                    visible: text !== ""
                    color: panel.errorText !== "" ? Theme.red : Theme.orange
                    font.pixelSize: 10
                    font.weight: 700
                    font.letterSpacing: 0.6
                    font.family: Theme.fontText
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: panel.copiedFlash
                    text: "Copied"
                    color: Theme.green
                    font.pixelSize: 10
                    font.weight: 700
                    font.family: Theme.fontText
                }
            }

            // Big result; slides up + fades in whenever it changes.
            Item {
                Layout.fillWidth: true
                implicitHeight: resultView.implicitHeight
                clip: true

                Text {
                    id: resultView
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    text: panel.errorText !== "" ? panel.errorText
                        : panel.resultText !== "" ? panel.resultText
                        : panel.history.length > 0 ? panel.history[0].result : "0"
                    color: panel.errorText !== "" ? Theme.red : "#ffffff"
                    opacity: panel.errorText !== "" ? 0.9 : panel.resultText !== "" ? 1 : 0.3
                    font.pixelSize: panel.errorText !== "" ? 14 : (panel.resultText.indexOf("x") !== -1 || panel.resultText.length > 14 ? 24 : 40)
                    font.weight: 300
                    font.family: Theme.font
                    font.features: { "tnum": 1 }
                    elide: Text.ElideLeft
                    transform: Translate { id: resultSlide }
                    onTextChanged: if (panel.resultText !== "" && !Theme.reduceMotion) resultIn.restart()
                    ParallelAnimation {
                        id: resultIn
                        NumberAnimation { target: resultSlide; property: "y"; from: 10; to: 0; duration: 220; easing.type: Easing.OutCubic }
                        NumberAnimation { target: resultView; property: "opacity"; from: 0.4; to: 1; duration: 220 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: panel.resultText !== "" || panel.history.length > 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.copyCurrent()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                visible: panel.subVisible
                text: panel.subText
                color: "#ffffff"
                opacity: 0.5
                font.pixelSize: 12
                font.family: Theme.fontText
                elide: Text.ElideLeft
            }

            // Actions (with a result) or examples (empty input).
            Flow {
                Layout.fillWidth: true
                layoutDirection: Qt.RightToLeft
                spacing: 6
                visible: panel.resultText !== "" && panel.resultText !== "…" && panel.errorText === ""

                Chip { label: "Use as ans"; onClicked: panel.commit() }
                Chip { label: "Copy"; tint: Qt.rgba(1, 0.62, 0.04, 0.22); onClicked: panel.copyCurrent() }
                Repeater {
                    model: panel.analysis && panel.analysis.roots.length > 1 ? panel.analysis.roots.slice().reverse() : []
                    Chip {
                        required property real modelData
                        label: "x = " + engine.format(modelData)
                        onClicked: panel.copyResult(engine.format(modelData))
                    }
                }
            }
        }
    }

    CalcGraph {
        Layout.fillWidth: true
        Layout.preferredHeight: 140
        visible: panel.graphVisible && !panel.helpOpen
        analysis: panel.analysis
        accent: Theme.orange
    }
    } // left column

    // ── History (right column) ─────────────────────────────────────────
    Rectangle {
        id: historySheet
        Layout.preferredWidth: 200
        Layout.fillHeight: true
        visible: panel.historyVisible
        radius: 16
        color: Theme.card
        clip: true
        // Slides in from the right edge when opened.
        transform: Translate { id: sheetSlide }
        onVisibleChanged: if (visible && !Theme.reduceMotion) sheetIn.restart()
        ParallelAnimation {
            id: sheetIn
            NumberAnimation { target: sheetSlide; property: "x"; from: 40; to: 0; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { target: historySheet; property: "opacity"; from: 0; to: 1; duration: 200 }
        }

        RowLayout {
            id: histHeader
            x: 12
            y: 8
            width: parent.width - 24

            Text {
                text: "HISTORY"
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 10
                font.weight: 600
                font.letterSpacing: 0.5
                font.family: Theme.fontText
                Layout.fillWidth: true
            }
            Text {
                visible: panel.history.length > 0
                text: "Clear"
                color: Theme.orange
                opacity: clearMouse.pressed ? 0.5 : 1
                font.pixelSize: 11
                font.weight: 600
                font.family: Theme.fontText
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { panel.history = []; exprInput.forceActiveFocus() }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: panel.history.length === 0
            text: "No calculations yet"
            color: "#ffffff"
            opacity: 0.3
            font.pixelSize: 11
            font.family: Theme.fontText
        }

        Column {
            id: histCol
            x: 12
            anchors.top: histHeader.bottom
            anchors.topMargin: 4
            width: parent.width - 24

            Repeater {
                model: panel.history

                Rectangle {
                    required property var modelData
                    width: histCol.width
                    height: 38
                    radius: 10
                    color: histMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent"

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 6
                        width: parent.width - 12
                        Text {
                            width: parent.width
                            text: modelData.expr
                            color: "#ffffff"
                            opacity: 0.45
                            font.pixelSize: 10
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: "= " + modelData.result
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.weight: 600
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: histMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { exprInput.text = modelData.expr; exprInput.forceActiveFocus() }
                    }
                }
            }
        }
    }
    } // row

    // Keeps the content top-aligned while the history column is hidden.
    Item { Layout.fillHeight: !panel.historyVisible }
}
