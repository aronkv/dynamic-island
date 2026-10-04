import Quickshell.Networking
import Quickshell.Io
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects

// Wi-Fi sub-view, iOS Settings style: a status card on top (current
// network or "Not connected", plus the Ethernet state), then grouped lists
// ("My Networks" = saved, "Other Networks" = available) with hairline
// dividers. Click a row: connect / open the password field (secured, not
// saved) / disconnect (connected). The ⓘ button (or right-click) expands the
// row's details + Disconnect / Modify / Forget. All logic is NetworkMonitor's.
ColumnLayout {
    id: panel
    property var monitor: null
    spacing: 10

    // Password-entry state lives here, not on the Repeater delegate: the
    // network list is a fresh JS array every time any visible network's
    // connected/known/signalStrength changes (the sort comparator reads
    // those), and Repeater recreates every delegate whenever the model
    // array identity changes — delegate-local state would be wiped mid-entry.
    property string activeNetworkName: ""
    property string pendingPassword: ""
    property string connectError: ""
    property string errorNetworkName: ""
    readonly property bool passwordEntryOpen: activeNetworkName !== ""

    // Expanded detail row — same reasoning as above.
    property string expandedNetworkName: ""

    // "Modify network" (change a saved network's stored password).
    property string modifyNetworkName: ""
    property string pendingModifyPassword: ""
    readonly property bool modifyEntryOpen: modifyNetworkName !== ""

    signal settingsRequested()
    signal closeRequested()

    // ── Share password (QR) ──────────────────────────────────────────
    // "Click to share password" on the connected network: reads the saved
    // PSK with nmcli (argv list) and renders the standard Wi-Fi QR payload
    // (WIFI:T:WPA;S:…;P:…;;) as an SVG via qrencode on stdout, shown as a
    // data: URL — nothing is written to disk. Cleared when closed/hidden.
    property bool shareOpen: false
    property string sharePsk: ""
    property string shareQr: ""          // non-empty once a code is ready
    property var shareQrMatrix: []       // rows of booleans (dark modules)
    property bool shareBig: false        // tap the code to enlarge it
    property bool shareReveal: false
    property string shareError: ""
    onVisibleChanged: if (!visible) closeShare()
    // Closing only collapses the sheet; its content is cleared after the
    // collapse animation, so nothing inside changes size/text mid-collapse.
    function closeShare() { shareOpen = false; shareReveal = false; shareClearTimer.restart() }
    function _clearShare() { sharePsk = ""; shareQr = ""; shareQrMatrix = []; shareBig = false; shareError = "" }
    Timer { id: shareClearTimer; interval: 380; onTriggered: if (!panel.shareOpen) panel._clearShare() }
    function qrEscape(t) { return t.replace(/([\\;,:"])/g, "\\$1") }
    function toggleShare() {
        if (shareOpen) { closeShare(); return }
        if (!current) return
        shareClearTimer.stop()
        _clearShare()
        shareOpen = true
        expandedNetworkName = ""
        if (!isSecured(current)) { makeQr(""); return }
        pskProc.command = ["nmcli", "-s", "-g", "802-11-wireless-security.psk", "connection", "show", "id", current.name]
        pskProc.running = true
    }
    function makeQr(psk) {
        sharePsk = psk
        const payload = "WIFI:T:" + (psk !== "" ? "WPA" : "nopass") + ";S:" + qrEscape(current ? current.name : "")
            + ";" + (psk !== "" ? "P:" + qrEscape(psk) + ";" : "") + ";"
        // ASCII output ("##" = dark module) drawn pixel-exact below: the old
        // SVG, rasterized at 304 px and drawn at ~152 px without smoothing,
        // gave uneven module sizes that phone cameras refused to read.
        qrProc.command = ["qrencode", "-t", "ASCII", "-m", "0", "-l", "M", "-o", "-", payload]
        qrProc.running = true
    }
    Process {
        id: pskProc
        stdout: StdioCollector {
            onStreamFinished: {
                const psk = text.replace(/\n$/, "")
                if (psk === "") panel.shareError = "Password not available"
                else panel.makeQr(psk)
            }
        }
    }
    Process {
        id: qrProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (!panel.shareOpen) return
                const rows = text.split("\n").filter(l => l.length > 0).map(l => {
                    const row = []
                    for (let i = 0; i + 1 < l.length; i += 2) row.push(l[i] === "#")
                    return row
                })
                if (rows.length < 21) return
                panel.shareQrMatrix = rows
                panel.shareQr = "ready"
            }
        }
    }

    readonly property var connectedNetworks: monitor ? monitor.networks.filter(n => n.connected) : []
    readonly property var savedNetworks: monitor ? monitor.networks.filter(n => !n.connected && n.known) : []
    readonly property var availableNetworks: monitor ? monitor.networks.filter(n => !n.connected && !n.known) : []
    readonly property var current: connectedNetworks.length > 0 ? connectedNetworks[0] : null

    function isSecured(network) {
        return network.security !== WifiSecurityType.Open && network.security !== WifiSecurityType.Unknown
    }

    function failReasonText(reason) {
        if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout)
            return "Wrong password"
        return "Connection failed"
    }

    // "5 GHz" / "2.4 GHz" / "2.4 + 5 GHz" from the scan's band string
    // (NetworkMonitor.wifiDetails, see wifi_details.py). Empty if unknown.
    function bandTag(name) {
        const details = (monitor && monitor.wifiDetails) ? monitor.wifiDetails[name] : null
        const band = details ? details.band : ""
        if (!band) return ""
        const has24 = band.indexOf("2.4") !== -1
        const has5 = band.indexOf("5") !== -1
        // Only 5 GHz-capable networks get a tag (plain 2.4 GHz shows none).
        if (has24 && has5) return "2.4/5G"
        if (has5) return "5G"
        return ""
    }

    // "Wi-Fi 6" etc. — the access point's own capability, from its beacons
    // (wifi_details.py `generation`); what phones show next to a network.
    function genName(name) {
        const details = (monitor && monitor.wifiDetails) ? monitor.wifiDetails[name] : null
        return details && details.generation ? "Wi-Fi " + details.generation : ""
    }
    function rowTag(name) {
        return [genName(name), bandTag(name)].filter(t => t !== "").join(" · ")
    }

    function activate(network) {
        if (network.connected) {
            network.disconnect()
        } else if (network.known || !isSecured(network)) {
            connectError = ""
            errorNetworkName = ""
            network.connect()
        } else {
            const opening = activeNetworkName !== network.name
            activeNetworkName = opening ? network.name : ""
            connectError = ""
            errorNetworkName = ""
            pendingPassword = ""
        }
    }
    function toggleDetails(network) {
        expandedNetworkName = expandedNetworkName === network.name ? "" : network.name
    }

    // ── Small building blocks ────────────────────────────────────────
    component RowIcon: Item {
        id: rowIcon
        property string icon: ""
        property color iconColor: "#ffffff"
        implicitWidth: 16
        implicitHeight: 16
        IconImage {
            id: iconImg
            anchors.fill: parent
            source: rowIcon.icon !== "" ? "image://icon/" + rowIcon.icon : ""
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }
        Rectangle { id: flatFill; anchors.fill: parent; color: rowIcon.iconColor; visible: false }
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

    // Wi-Fi glyph (dot + 3 arcs) lit up to the signal level. Vector Shape
    // (Adwaita's "excellent"/"good" signal SVGs are byte-identical, and a
    // Canvas may not paint in a hidden panel).
    component WifiGlyph: Item {
        id: glyph
        property real strength: 0
        property color onColor: "#ffffff"
        property color offColor: Qt.rgba(1, 1, 1, 0.25)
        readonly property real pct: (strength > 0 && strength <= 1) ? strength * 100 : strength
        readonly property int level: pct >= 75 ? 3 : pct >= 50 ? 2 : pct >= 25 ? 1 : 0
        implicitWidth: 18
        implicitHeight: 18
        readonly property real s: width / 18
        Rectangle {
            x: 9 * glyph.s - width / 2
            y: 14.2 * glyph.s - height / 2
            width: 3.2 * glyph.s
            height: width
            radius: width / 2
            color: glyph.onColor
        }
        Repeater {
            model: 3
            Shape {
                required property int index
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: "transparent"
                    strokeColor: glyph.level >= index + 1 ? glyph.onColor : glyph.offColor
                    strokeWidth: 1.9 * glyph.s
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        moveToStart: true
                        centerX: 9 * glyph.s; centerY: 14.2 * glyph.s
                        radiusX: (4.2 + index * 3.6) * glyph.s; radiusY: radiusX
                        startAngle: -135; sweepAngle: 90
                    }
                }
            }
        }
    }

    component Spinner: Item {
        id: sp
        property color color: "#ffffff"
        implicitWidth: 14
        implicitHeight: 14
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: "transparent"
                strokeColor: sp.color
                strokeWidth: 1.8
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    moveToStart: true
                    centerX: sp.width / 2; centerY: sp.height / 2
                    radiusX: sp.width / 2 - 1; radiusY: radiusX
                    startAngle: 0; sweepAngle: 270
                }
            }
            RotationAnimation on rotation {
                running: sp.visible
                from: 0; to: 360
                duration: 800
                loops: Animation.Infinite
            }
        }
    }

    component PillButton: Rectangle {
        id: pb
        property string label: ""
        property bool primary: false
        property bool destructive: false
        property bool enabledState: true
        signal clicked()
        implicitWidth: pbText.implicitWidth + 24
        implicitHeight: 28
        radius: 14
        opacity: enabledState ? 1 : 0.4
        color: primary ? "#ffffff"
            : destructive ? (pbMouse.containsMouse ? Qt.rgba(1, 0.27, 0.23, 0.28) : Qt.rgba(1, 0.27, 0.23, 0.16))
            : (pbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.1))
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: pbMouse.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        Text {
            id: pbText
            anchors.centerIn: parent
            text: pb.label
            color: pb.primary ? "#000000" : pb.destructive ? Theme.red : "#ffffff"
            font.pixelSize: 12
            font.weight: 600
            font.family: Theme.fontText
        }
        MouseArea {
            id: pbMouse
            anchors.fill: parent
            enabled: pb.enabledState
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pb.clicked()
        }
    }

    // Launcher-style password pill with a show/hide eye.
    component PasswordField: Rectangle {
        id: pf
        property alias text: pfInput.text
        property string placeholder: "Password"
        property bool wantFocus: false
        signal accepted()
        Layout.fillWidth: true
        implicitHeight: 36
        radius: 18
        color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, pfInput.activeFocus ? 0.25 : 0.08)
        Behavior on border.color { ColorAnimation { duration: 120 } }
        RowIcon {
            id: pfLock
            anchors.left: parent.left
            anchors.leftMargin: 13
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14
            icon: "channel-secure-symbolic"
            opacity: 0.5
        }
        TextInput {
            id: pfInput
            anchors.left: pfLock.right
            anchors.leftMargin: 9
            anchors.right: pfEye.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: "#ffffff"
            font.pixelSize: 13
            font.family: Theme.fontText
            echoMode: pfEye.checked ? TextInput.Normal : TextInput.Password
            clip: true
            focus: pf.wantFocus
            onVisibleChanged: if (visible && pf.wantFocus) forceActiveFocus()
            Keys.onReturnPressed: pf.accepted()
            Keys.onEnterPressed: pf.accepted()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: pfInput.text.length === 0
                text: pf.placeholder
                color: "#ffffff"
                opacity: 0.35
                font: pfInput.font
            }
        }
        RowIcon {
            id: pfEye
            property bool checked: false
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 15; height: 15
            icon: checked ? "view-conceal-symbolic" : "view-reveal-symbolic"
            opacity: 0.6
            MouseArea {
                anchors.fill: parent
                anchors.margins: -5
                cursorShape: Qt.PointingHandCursor
                onClicked: pfEye.checked = !pfEye.checked
            }
        }
    }

    // Outlined "5G" / "2.4/5G" tag next to a network name.
    component BandTag: Rectangle {
        property string tag: ""
        visible: tag !== ""
        width: tagText.implicitWidth + 8
        height: 15
        radius: 4
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.45)
        Text {
            id: tagText
            anchors.centerIn: parent
            text: parent.tag
            color: "#ffffff"
            opacity: 0.7
            font.pixelSize: 9
            font.weight: 600
            font.family: Theme.fontText
        }
    }

    component DetailRow: RowLayout {
        Layout.fillWidth: true
        property string label: ""
        property string value: ""
        visible: value.length > 0
        spacing: 8
        Text {
            text: parent.label
            color: "#ffffff"
            opacity: 0.5
            font.pixelSize: 11
            font.family: Theme.fontText
        }
        Item { Layout.fillWidth: true }
        Text {
            text: parent.value
            color: "#ffffff"
            opacity: 0.85
            font.pixelSize: 11
            font.weight: 500
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }

    // Round ⓘ button that toggles a row's details.
    component InfoButton: Rectangle {
        id: ib
        property bool open: false
        signal clicked()
        implicitWidth: 24
        implicitHeight: 24
        radius: 12
        color: open ? "#ffffff" : (ibMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent")
        border.width: open ? 0 : 1.2
        border.color: Qt.rgba(1, 1, 1, 0.45)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            text: "i"
            color: ib.open ? "#000000" : "#ffffff"
            opacity: ib.open ? 1 : 0.7
            font.pixelSize: 12
            font.weight: 700
            font.italic: false
            font.family: "SF Pro Rounded"
        }
        MouseArea {
            id: ibMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: ib.clicked()
        }
    }

    // One network row inside a grouped list. Expands in place for the
    // password field, details, or the modify-password field.
    component NetworkRow: Item {
        id: row
        property var network: null
        property bool first: false
        Layout.fillWidth: true
        implicitHeight: rowCol.implicitHeight
        clip: true

        readonly property bool connecting: network.stateChanging || network.state === ConnectionState.Connecting
        readonly property bool showPasswordEntry: panel.activeNetworkName === network.name
        readonly property bool showDetails: panel.expandedNetworkName === network.name
        readonly property bool showModify: panel.modifyNetworkName === network.name
        readonly property var details: (panel.monitor && panel.monitor.wifiDetails) ? panel.monitor.wifiDetails[network.name] : null
        readonly property var connInfo: (panel.monitor && panel.monitor.wifiDetails) ? panel.monitor.wifiDetails["_connection"] : null
        readonly property string band: panel.rowTag(network.name)
        readonly property bool hasError: panel.errorNetworkName === network.name && panel.connectError.length > 0

        Connections {
            target: row.network
            function onConnectionFailed(reason) {
                panel.connectError = panel.failReasonText(reason)
                panel.errorNetworkName = row.network.name
                if (panel.isSecured(row.network) && !row.network.known)
                    panel.activeNetworkName = row.network.name
            }
            // Close the password entry once this network connects.
            function onConnectedChanged() {
                if (row.network.connected && panel.activeNetworkName === row.network.name) {
                    panel.activeNetworkName = ""
                    panel.pendingPassword = ""
                }
            }
        }

        // Hairline divider (inset past the icon), not above the first row.
        Rectangle {
            visible: !row.first
            x: 44
            width: parent.width - 44
            height: 1
            color: Qt.rgba(1, 1, 1, 0.07)
        }

        ColumnLayout {
            id: rowCol
            width: parent.width
            spacing: 0

            Item {
                Layout.fillWidth: true
                implicitHeight: 44

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(1, 1, 1, rowMouse.containsMouse ? 0.05 : 0)
                }

                WifiGlyph {
                    id: sig
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    strength: row.network.signalStrength
                }

                Column {
                    anchors.left: sig.right
                    anchors.leftMargin: 12
                    anchors.right: trailing.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    Row {
                        width: parent.width
                        spacing: 6
                        Text {
                            id: rowName
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, parent.width - (row.band !== "" ? rowTag.width + 6 : 0))
                            text: row.network.name
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.weight: 500
                            font.family: Theme.fontText
                            elide: Text.ElideRight
                        }
                        BandTag { id: rowTag; anchors.verticalCenter: parent.verticalCenter; tag: row.band }
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: row.connecting ? "Connecting…"
                            : row.hasError ? panel.connectError
                            : ""
                        color: row.hasError ? Theme.red : "#ffffff"
                        opacity: row.hasError ? 1 : 0.45
                        font.pixelSize: 10
                        font.family: Theme.fontText
                    }
                }

                Row {
                    id: trailing
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Spinner { anchors.verticalCenter: parent.verticalCenter; visible: row.connecting }
                    RowIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 13; height: 13
                        icon: "channel-secure-symbolic"
                        visible: panel.isSecured(row.network)
                        opacity: 0.55
                    }
                    InfoButton {
                        anchors.verticalCenter: parent.verticalCenter
                        open: row.showDetails
                        onClicked: panel.toggleDetails(row.network)
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    anchors.rightMargin: 44
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) panel.toggleDetails(row.network)
                        else panel.activate(row.network)
                    }
                }
            }

            // Password entry for a secured, not-yet-saved network.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 12
                spacing: 8
                visible: row.showPasswordEntry

                PasswordField {
                    id: psk
                    placeholder: "Password for " + row.network.name
                    text: panel.pendingPassword
                    wantFocus: row.showPasswordEntry
                    onTextChanged: panel.pendingPassword = text
                    onAccepted: if (text.length > 0) { panel.connectError = ""; panel.errorNetworkName = ""; row.network.connectWithPsk(text) }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    PillButton {
                        label: "Cancel"
                        onClicked: { panel.activeNetworkName = ""; panel.connectError = ""; panel.errorNetworkName = ""; panel.pendingPassword = "" }
                    }
                    PillButton {
                        label: "Join"
                        primary: true
                        enabledState: psk.text.length > 0
                        onClicked: { panel.connectError = ""; panel.errorNetworkName = ""; row.network.connectWithPsk(psk.text) }
                    }
                }
            }

            // Details + actions.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 12
                spacing: 4
                visible: row.showDetails

                DetailRow {
                    label: "Technology"
                    value: (row.network.connected && row.connInfo) ? row.connInfo.technology : panel.genName(row.network.name)
                }
                // The router can be newer than this laptop's adapter (the
                // T480's Intel 8265 tops out at Wi-Fi 5).
                DetailRow {
                    label: "Connected as"
                    value: row.network.connected && row.connInfo && row.connInfo.linkTechnology
                        && row.connInfo.linkGeneration !== row.connInfo.apGeneration ? row.connInfo.linkTechnology : ""
                }
                DetailRow { label: "Security"; value: row.details ? row.details.security : "" }
                DetailRow { label: "IP address"; value: (row.network.connected && row.connInfo) ? row.connInfo.ip : "" }
                DetailRow { label: "Subnet mask"; value: (row.network.connected && row.connInfo) ? row.connInfo.subnet : "" }
                DetailRow { label: "Router"; value: (row.network.connected && row.connInfo) ? row.connInfo.gateway : "" }
                DetailRow { label: "Proxy"; value: (row.network.connected && row.connInfo) ? row.connInfo.proxy : "" }
                DetailRow { label: "IP settings"; value: (row.network.connected && row.connInfo) ? row.connInfo.method : "" }
                DetailRow { label: "Privacy"; value: (row.network.connected && row.connInfo) ? row.connInfo.privacy : "" }
                DetailRow { label: "Band"; value: row.details ? row.details.band : "" }
                DetailRow { label: "Channel"; value: row.details ? row.details.channel : "" }
                DetailRow { label: "Frequency"; value: row.details ? row.details.freq : "" }
                DetailRow { label: "Max speed"; value: row.details ? row.details.rate : "" }
                DetailRow { label: "BSSID"; value: row.details ? row.details.bssid : "" }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8
                    PillButton {
                        visible: row.network.connected
                        label: "Disconnect"
                        onClicked: row.network.disconnect()
                    }
                    PillButton {
                        visible: !row.network.connected
                        label: "Join"
                        primary: true
                        onClicked: panel.activate(row.network)
                    }
                    PillButton {
                        visible: row.network.known
                        label: "Change Password"
                        onClicked: {
                            const opening = panel.modifyNetworkName !== row.network.name
                            panel.modifyNetworkName = opening ? row.network.name : ""
                            panel.pendingModifyPassword = ""
                        }
                    }
                    Item { Layout.fillWidth: true }
                    PillButton {
                        visible: row.network.known
                        label: "Forget"
                        destructive: true
                        onClicked: {
                            if (panel.monitor) panel.monitor.forgetNetwork(row.network.name)
                            panel.expandedNetworkName = ""
                            if (panel.modifyNetworkName === row.network.name) panel.modifyNetworkName = ""
                        }
                    }
                }
            }

            // Change a saved network's password (empty = unchanged).
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 14
                Layout.rightMargin: 14
                Layout.bottomMargin: 12
                spacing: 8
                visible: row.showModify

                PasswordField {
                    id: modifyField
                    placeholder: "New password (unchanged)"
                    text: panel.pendingModifyPassword
                    wantFocus: row.showModify
                    onTextChanged: panel.pendingModifyPassword = text
                    onAccepted: {
                        if (text.length > 0 && panel.monitor) panel.monitor.modifyPassword(row.network.name, text)
                        panel.modifyNetworkName = ""
                        panel.pendingModifyPassword = ""
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    PillButton {
                        label: "Cancel"
                        onClicked: { panel.modifyNetworkName = ""; panel.pendingModifyPassword = "" }
                    }
                    PillButton {
                        label: "Save"
                        primary: true
                        onClicked: {
                            if (modifyField.text.length > 0 && panel.monitor) panel.monitor.modifyPassword(row.network.name, modifyField.text)
                            panel.modifyNetworkName = ""
                            panel.pendingModifyPassword = ""
                        }
                    }
                }
            }
        }
    }

    component SectionLabel: Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.leftMargin: 14
        color: "#ffffff"
        opacity: 0.45
        font.pixelSize: 11
        font.weight: 600
        font.letterSpacing: 0.4
        font.family: Theme.fontText
    }

    // Rounded group container for a list of rows.
    component Group: Rectangle {
        default property alias rows: groupCol.data
        Layout.fillWidth: true
        implicitHeight: groupCol.implicitHeight
        radius: 14
        color: Theme.card
        clip: true
        ColumnLayout {
            id: groupCol
            width: parent.width
            spacing: 0
        }
    }

    // ── Header ───────────────────────────────────────────────────────
    PanelHeader {
        showIdentity: false
        Layout.fillWidth: true
        icon: "network-wireless-symbolic"
        title: "Wi-Fi"
        subtitle: !(panel.monitor && panel.monitor.wifiEnabled) ? "Off"
            : panel.current ? panel.current.name : (panel.monitor.networks.length + " networks nearby")
        showToggle: true
        toggleChecked: panel.monitor ? panel.monitor.wifiEnabled : false
        showRefresh: panel.monitor ? panel.monitor.wifiEnabled : false
        onToggled: if (panel.monitor) panel.monitor.setWifiEnabled(!panel.monitor.wifiEnabled)
        onRefreshRequested: if (panel.monitor) panel.monitor.rescan()
        onSettingsRequested: panel.settingsRequested()
        onCloseRequested: panel.closeRequested()
    }

    Flickable {
        id: netFlick
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: listCol.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: listCol
            width: parent.width
            spacing: 6

            // ── Status card ──────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statusCol.implicitHeight
                radius: 14
                color: Theme.card
                clip: true

                ColumnLayout {
                    id: statusCol
                    width: parent.width
                    spacing: 0

                    // Current Wi-Fi network (hero row).
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 60
                        visible: panel.monitor && panel.monitor.wifiEnabled

                        Rectangle {
                            id: heroBadge
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 36; height: 36
                            radius: 18
                            color: panel.current ? "#ffffff" : Qt.rgba(1, 1, 1, 0.1)
                            WifiGlyph {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                width: 20; height: 20
                                strength: panel.current ? panel.current.signalStrength : 0
                                onColor: panel.current ? "#000000" : "#ffffff"
                                offColor: panel.current ? Qt.rgba(0, 0, 0, 0.25) : Qt.rgba(1, 1, 1, 0.25)
                            }
                            // Wi-Fi generation ("5", "6", "6E", "7") of the
                            // live link, from `iw dev … link` (wifi_details.py).
                            Rectangle {
                                readonly property var conn: panel.current && panel.monitor && panel.monitor.wifiDetails
                                    ? panel.monitor.wifiDetails["_connection"] : null
                                readonly property string gen: conn && conn.apGeneration ? conn.apGeneration : ""
                                visible: gen !== ""
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: -4
                                anchors.bottomMargin: -3
                                width: Math.max(17, genText.implicitWidth + 8)
                                height: 17
                                radius: 8.5
                                color: "#000000"
                                border.width: 1.5
                                border.color: "#ffffff"
                                Text {
                                    id: genText
                                    anchors.centerIn: parent
                                    text: parent.gen
                                    color: "#ffffff"
                                    font.pixelSize: 9
                                    font.weight: 700
                                    font.family: Theme.fontText
                                }
                            }
                        }
                        Column {
                            anchors.left: heroBadge.right
                            anchors.leftMargin: 12
                            anchors.right: heroTrailing.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Row {
                                width: parent.width
                                spacing: 7
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.min(implicitWidth, parent.width - (heroTag.visible ? heroTag.width + 7 : 0))
                                    text: panel.current ? panel.current.name : "Not Connected"
                                    color: "#ffffff"
                                    font.pixelSize: 15
                                    font.weight: 700
                                    font.family: Theme.font
                                    elide: Text.ElideRight
                                }
                                BandTag { id: heroTag; anchors.verticalCenter: parent.verticalCenter; tag: panel.current ? panel.bandTag(panel.current.name) : "" }
                            }
                            Text {
                                width: parent.width
                                text: panel.current
                                    ? (panel.shareOpen ? "Click to hide" : "Click to share password")
                                    : "Choose a network below"
                                color: "#ffffff"
                                opacity: 0.5
                                font.pixelSize: 11
                                font.family: Theme.fontText
                                elide: Text.ElideRight
                            }
                        }
                        Row {
                            id: heroTrailing
                            anchors.right: parent.right
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            visible: panel.current !== null
                            InfoButton {
                                open: panel.current !== null && panel.expandedNetworkName === panel.current.name
                                onClicked: { panel.closeShare(); panel.toggleDetails(panel.current) }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.rightMargin: 44
                            enabled: panel.current !== null
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) { panel.closeShare(); panel.toggleDetails(panel.current) }
                                else panel.toggleShare()
                            }
                        }
                    }

                    // Share sheet: QR + name + password. Revealed by animating the
                    // wrapper height (clipped) + a fade, instead of popping in.
                    Item {
                        id: shareWrap
                        readonly property bool open: panel.shareOpen && panel.current !== null
                        Layout.fillWidth: true
                        Layout.preferredHeight: open ? shareSheet.implicitHeight + 14 : 0
                        // Open: 340 ms ease-out; close: a quicker 260 ms ease-in.
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.reduceMotion ? 0 : (shareWrap.open ? 340 : 260); easing.type: shareWrap.open ? Easing.OutCubic : Easing.InCubic } }
                        clip: true
                        visible: Layout.preferredHeight > 0.5
                        opacity: open ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : (shareWrap.open ? 240 : 180); easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            id: shareSheet
                            width: statusCol.width
                            spacing: 8

                            // Fixed-size slot: the layout height doesn't change
                            // when qrencode's matrix arrives (the card used to
                            // open at 240 px, then shrink to the integer-module
                            // size — the "jump").
                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 4
                                implicitWidth: qrCard.width
                                implicitHeight: qrCard.height
                            Rectangle {
                                id: qrCard
                                // Integer pixels per module + a 4-module white quiet
                                // zone (the QR standard), so every module is exactly
                                // the same size on screen. Click to enlarge. Before
                                // the matrix exists, sized for the typical 33-module
                                // Wi-Fi code so the size doesn't change on arrival.
                                readonly property int modules: panel.shareQrMatrix.length > 0 ? panel.shareQrMatrix.length : 33
                                readonly property int target: panel.shareBig ? Math.min(statusCol.width, 400) : 240
                                readonly property int px: Math.max(3, Math.floor(target / (modules + 8)))
                                width: px * (modules + 8)
                                height: width
                                radius: 14
                                color: "#ffffff"
                                // Animate only the enlarge toggle, never the first layout.
                                Behavior on width { enabled: panel.shareQr !== ""; NumberAnimation { duration: Theme.reduceMotion ? 0 : 220; easing.type: Easing.OutCubic } }
                                // Hidden until the code exists (or an error does), then
                                // fades/scales in as one piece — it used to show an
                                // empty white card for a frame before the code popped in.
                                readonly property bool shown: panel.shareQr !== "" || panel.shareError !== ""
                                opacity: shown ? 1 : 0
                                scale: shown ? 1 : 0.9
                                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 320; easing.type: Easing.OutCubic } }
                                Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 0 : 420; easing.type: Easing.OutQuint } }

                                Shape {
                                    x: qrCard.px * 4
                                    y: qrCard.px * 4
                                    width: qrCard.px * qrCard.modules
                                    height: width
                                    visible: panel.shareQr !== ""
                                    antialiasing: false
                                    ShapePath {
                                        strokeWidth: 0
                                        strokeColor: "transparent"
                                        fillColor: "#000000"
                                        PathSvg {
                                            path: {
                                                const m = panel.shareQrMatrix, p = qrCard.px
                                                let d = ""
                                                for (let y = 0; y < m.length; y++)
                                                    for (let x = 0; x < m[y].length; x++)
                                                        if (m[y][x]) d += "M" + (x * p) + " " + (y * p) + "h" + p + "v" + p + "h-" + p + "z"
                                                return d
                                            }
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: panel.shareQr !== ""
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.shareBig = !panel.shareBig
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: panel.shareQr === ""
                                    text: panel.shareError
                                    color: "#000000"
                                    opacity: 0.5
                                    font.pixelSize: 12
                                    font.family: Theme.fontText
                                }
                            }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: panel.current ? panel.current.name : ""
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.weight: 600
                                font.family: Theme.font
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                visible: panel.sharePsk !== ""
                                text: "Password: " + (panel.shareReveal ? panel.sharePsk : "•".repeat(Math.min(12, panel.sharePsk.length)))
                                color: "#ffffff"
                                opacity: 0.55
                                font.pixelSize: 12
                                font.family: Theme.fontText
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.shareReveal = !panel.shareReveal
                                }
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: panel.sharePsk === "" ? "Open network" : (panel.shareReveal ? "Click to hide" : "Click to show · scan with your phone")
                                color: "#ffffff"
                                opacity: 0.3
                                font.pixelSize: 10
                                font.family: Theme.fontText
                            }
                        }
                    }

                    // Expanded details of the connected network reuse the
                    // regular row (hidden header) — rendered as a NetworkRow
                    // so actions/password logic stay in one place.
                    Repeater {
                        model: panel.connectedNetworks
                        delegate: Item {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: panel.expandedNetworkName === modelData.name || panel.modifyNetworkName === modelData.name
                                ? connRow.implicitHeight - 44 : 0
                            clip: true
                            NetworkRow {
                                id: connRow
                                y: -44
                                width: parent.width
                                network: modelData
                                first: true
                            }
                        }
                    }

                    // Ethernet line.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.leftMargin: 60
                        implicitHeight: 1
                        color: Qt.rgba(1, 1, 1, 0.07)
                        visible: panel.monitor && panel.monitor.wifiEnabled
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        RowIcon {
                            id: ethIcon
                            x: 22
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "network-wired-symbolic"
                            opacity: panel.monitor && panel.monitor.ethernetConnected ? 0.9 : 0.4
                        }
                        Text {
                            anchors.left: ethIcon.right
                            anchors.leftMargin: 22
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Ethernet"
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.family: Theme.fontText
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.monitor && panel.monitor.ethernetActive ? "Connected"
                                : panel.monitor && panel.monitor.ethernetConnected ? "Cable connected" : "Not connected"
                            color: "#ffffff"
                            opacity: 0.45
                            font.pixelSize: 12
                            font.family: Theme.fontText
                        }
                    }
                }
            }

            // ── Saved ────────────────────────────────────────────────
            SectionLabel {
                text: "MY NETWORKS"
                visible: panel.monitor && panel.monitor.wifiEnabled && panel.savedNetworks.length > 0
            }
            Group {
                visible: panel.monitor && panel.monitor.wifiEnabled && panel.savedNetworks.length > 0
                Repeater {
                    model: panel.savedNetworks
                    delegate: NetworkRow {
                        required property var modelData
                        required property int index
                        network: modelData
                        first: index === 0
                    }
                }
            }

            // ── Available ────────────────────────────────────────────
            SectionLabel {
                text: "OTHER NETWORKS"
                visible: panel.monitor && panel.monitor.wifiEnabled && panel.availableNetworks.length > 0
            }
            Group {
                visible: panel.monitor && panel.monitor.wifiEnabled && panel.availableNetworks.length > 0
                Repeater {
                    model: panel.availableNetworks
                    delegate: NetworkRow {
                        required property var modelData
                        required property int index
                        network: modelData
                        first: index === 0
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 20
                horizontalAlignment: Text.AlignHCenter
                visible: !(panel.monitor && panel.monitor.wifiEnabled) || panel.monitor.networks.length === 0
                text: !(panel.monitor && panel.monitor.wifiEnabled) ? "Wi-Fi is off" : "Searching for networks…"
                color: "#ffffff"
                opacity: 0.4
                font.pixelSize: 12
                font.family: Theme.fontText
            }
        }
    }
}
