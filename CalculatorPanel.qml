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

    PanelHeader {
        accent: Theme.orange
        Layout.fillWidth: true
        icon: "accessories-calculator-symbolic"
        title: "Calculator"
        showSettingsGear: false
        onCloseRequested: panel.closeRequested()
    }

    RowLayout {
    Layout.fillWidth: true
    Layout.fillHeight: panel.historyVisible
    Layout.alignment: Qt.AlignTop
    spacing: 12

    ColumnLayout {
    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: 6

    // ── Input line (+ history toggle) ──────────────────────────────────
    RowLayout {
    Layout.fillWidth: true
    spacing: 8

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 48
        radius: Theme.radiusMedium
        color: Theme.card
        border.width: 1
        border.color: exprInput.activeFocus ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
        Behavior on border.color { ColorAnimation { duration: 150 } }

        Text {
            id: promptGlyph
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: "="
            color: Theme.orange
            font.pixelSize: 20
            font.weight: 600
            font.family: Theme.font
        }

        TextInput {
            id: exprInput
            anchors.left: promptGlyph.right
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"
            font.pixelSize: 20
            font.family: Theme.font
            clip: true
            focus: true
            selectByMouse: true

            onTextChanged: panel.runCalculation()
            Keys.onReturnPressed: panel.commit()
            Keys.onEnterPressed: panel.commit()
            Keys.onEscapePressed: {
                if (text.length > 0) text = ""
                else panel.closeRequested()
            }
            Keys.onUpPressed: if (panel.history.length > 0) text = panel.history[0].expr
            Keys.onPressed: (event) => {
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
                text: panel.history.length > 0 ? "ans × 2 · 100 usd · 5 km to mi · days until xmas" : "12 × 3.5 · 100 usd · 5 km to mi · days until xmas"
                color: "#ffffff"
                opacity: 0.3
                font.pixelSize: 16
                font.family: Theme.fontText
            }
        }
    }

    // History toggle (hidden when "always show" is on in Settings).
    Rectangle {
        visible: !(panel.settingsStore && panel.settingsStore.calcHistoryAlways)
        implicitWidth: 48
        implicitHeight: 48
        radius: Theme.radiusMedium
        color: panel.historyOpen ? Qt.rgba(1, 1, 1, 0.16) : Theme.card
        Behavior on color { ColorAnimation { duration: 150 } }

        IconImage {
            id: histIcon
            anchors.centerIn: parent
            implicitSize: 18
            source: "image://icon/document-open-recent-symbolic"
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }
        Rectangle { id: histIconFill; anchors.fill: histIcon; color: "#ffffff"; visible: false }
        MultiEffect {
            anchors.fill: histIcon
            source: histIconFill
            maskEnabled: true
            maskSource: histIcon
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.0
            maskThresholdMax: 1.0
            maskSpreadAtMax: 0.0
            opacity: panel.historyOpen ? 1 : 0.6
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { panel.historyOpen = !panel.historyOpen; exprInput.forceActiveFocus() }
        }
    }
    } // input row

    // ── Result line ────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        implicitHeight: 52
        Layout.bottomMargin: panel.subVisible ? 18 : 0

        // Conversion / date detail, right-aligned under the big result.
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.top: parent.bottom
            anchors.topMargin: -2
            width: parent.width - 8
            horizontalAlignment: Text.AlignRight
            visible: panel.subVisible
            text: panel.subText
            color: "#ffffff"
            opacity: 0.5
            font.pixelSize: 12
            font.family: Theme.fontText
            elide: Text.ElideLeft
        }

        Text {
            id: resultView
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 8
            horizontalAlignment: Text.AlignRight
            text: panel.errorText !== "" ? panel.errorText
                : panel.resultText !== "" ? panel.resultText
                : panel.history.length > 0 ? panel.history[0].result : "0"
            color: panel.errorText !== "" ? Theme.red : "#ffffff"
            opacity: panel.errorText !== "" ? 0.9 : panel.resultText !== "" ? 1 : 0.25
            font.pixelSize: panel.errorText !== "" ? 14 : (panel.resultText.indexOf("x") !== -1 || panel.resultText.length > 14 ? 22 : 38)
            font.weight: 300
            font.family: Theme.font
            elide: Text.ElideLeft
            Behavior on opacity { NumberAnimation { duration: 160 } }

            // Small "pop" every time the result changes.
            onTextChanged: if (panel.resultText !== "") resultPop.restart()
            SequentialAnimation {
                id: resultPop
                NumberAnimation { target: resultView; property: "scale"; to: 1.04; duration: 70; easing.type: Easing.OutQuad }
                NumberAnimation { target: resultView; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 }
            }
            transformOrigin: Item.Right
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            visible: panel.resultText !== "" || panel.copiedFlash
            text: panel.copiedFlash ? "Copied" : "Click to copy"
            color: "#ffffff"
            opacity: panel.copiedFlash ? 0.8 : 0.3
            font.pixelSize: 10
            font.family: Theme.fontText
        }

        MouseArea {
            anchors.fill: parent
            enabled: panel.resultText !== "" || panel.history.length > 0
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (panel.resultText !== "") {
                    if (panel.copyText !== "") panel.copyResult(panel.copyText, true)
                    else panel.copyResult(panel.resultText)
                } else if (panel.history[0].copy) panel.copyResult(panel.history[0].copy, true)
                else panel.copyResult(panel.history[0].result)
            }
        }
    }

    CalcGraph {
        Layout.fillWidth: true
        Layout.preferredHeight: 140
        visible: panel.graphVisible
        analysis: panel.analysis
        accent: Theme.orange
    }
    } // left column

    // ── History (right column) ─────────────────────────────────────────
    Rectangle {
        Layout.preferredWidth: 200
        Layout.fillHeight: true
        visible: panel.historyVisible
        radius: Theme.radiusMedium
        color: Theme.card

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

                Item {
                    required property var modelData
                    width: histCol.width
                    height: 34

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
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
                        anchors.fill: parent
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
