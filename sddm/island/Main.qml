import QtQuick
import QtQuick.Effects

// "Island" SDDM theme — Apple-style, matching the Quickshell lock screen.
// Two stages (inspired by SilentSDDM):
//   1. Lock view: wallpaper, big rounded clock + date, "Press any key".
//   2. Login view (any key / click): background blurs and dims, the clock
//      glides up and shrinks, avatar + name + password pill appear, session
//      picker bottom-left, power buttons bottom-right. Idle → back to 1.
// SDDM runs as its own user, so fonts and the wallpaper ship inside the theme.
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: "#000000"

    // ── Fonts (bundled) ───────────────────────────────────────────────
    FontLoader { id: fDisplay; source: "fonts/SF-Pro-Display-Regular.otf" }
    FontLoader { source: "fonts/SF-Pro-Display-Medium.otf" }
    FontLoader { source: "fonts/SF-Pro-Display-Semibold.otf" }
    FontLoader { source: "fonts/SF-Pro-Display-Bold.otf" }
    FontLoader { id: fRounded; source: "fonts/SF-Pro-Rounded-Bold.otf" }
    FontLoader { source: "fonts/SF-Pro-Rounded-Semibold.otf" }
    FontLoader { id: fText; source: "fonts/SF-Pro-Text-Regular.otf" }
    FontLoader { source: "fonts/SF-Pro-Text-Semibold.otf" }
    readonly property string display: fDisplay.name || "sans-serif"
    readonly property string rounded: fRounded.name || display
    readonly property string text: fText.name || display

    // ── State ─────────────────────────────────────────────────────────
    property bool loginMode: false
    property bool busy: false
    property string errorText: ""
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

    // Plain JS copies of the model rows (role data is only reachable from
    // delegates, so two Instantiators collect it).
    property var users: []
    property var sessions: []
    Instantiator {
        model: userModel
        delegate: QtObject {
            required property int index
            required property string name
            required property string realName
            required property string icon
            Component.onCompleted: {
                const u = root.users.slice()
                u[index] = { name: name, realName: realName, icon: icon }
                root.users = u
            }
        }
    }
    Instantiator {
        model: sessionModel
        delegate: QtObject {
            required property int index
            required property string name
            Component.onCompleted: {
                const s = root.sessions.slice()
                s[index] = name
                root.sessions = s
            }
        }
    }
    readonly property var currentUser: users[userIndex] || { name: userModel.lastUser || "", realName: "", icon: "" }
    readonly property string displayName: currentUser.realName || currentUser.name

    function enterLogin() {
        if (loginMode) return
        loginMode = true
        password.forceActiveFocus()
        idleTimer.restart()
    }
    function exitLogin() {
        loginMode = false
        password.text = ""
        errorText = ""
        keyCatcher.forceActiveFocus()
    }
    function tryLogin() {
        if (busy || !currentUser.name) return
        busy = true
        errorText = ""
        sddm.login(currentUser.name, password.text, sessionIndex)
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false
            root.errorText = "Incorrect password"
            password.text = ""
            shake.restart()
            password.forceActiveFocus()
        }
        function onLoginSucceeded() { root.busy = false }
    }

    Timer {
        id: idleTimer
        interval: (Number(config.idleTimeout) || 30) * 1000
        onTriggered: if (root.loginMode && password.text === "" && !root.busy) root.exitLogin()
    }

    // ── Background ────────────────────────────────────────────────────
    Image {
        id: bg
        anchors.fill: parent
        source: config.background || "background.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: bg
        blurEnabled: true
        blurMax: 64
        blur: root.loginMode ? 1.0 : 0.0
        brightness: root.loginMode ? -0.3 : -0.08
        saturation: root.loginMode ? 0.15 : 0.0
        Behavior on blur { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        Behavior on brightness { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }
        Behavior on saturation { NumberAnimation { duration: 450 } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.15) }
            GradientStop { position: 0.65; color: Qt.rgba(0, 0, 0, 0.1) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
        }
    }

    // Any key / click in lock view → login view.
    Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => { root.enterLogin(); event.accepted = true }
    }
    MouseArea {
        anchors.fill: parent
        onClicked: root.loginMode ? password.forceActiveFocus() : root.enterLogin()
        onPositionChanged: if (root.loginMode) idleTimer.restart()
        hoverEnabled: true
    }

    // ── Clock ─────────────────────────────────────────────────────────
    Column {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.loginMode ? root.height * 0.08 : root.height * 0.2
        scale: root.loginMode ? 0.55 : 1
        transformOrigin: Item.Top
        spacing: 0
        Behavior on y { NumberAnimation { duration: 550; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on scale { NumberAnimation { duration: 550; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }

        property date now: new Date()
        Timer { interval: 1000; running: true; repeat: true; onTriggered: clock.now = new Date() }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.now, "dddd, MMMM d")
            color: "#ffffff"
            opacity: 0.9
            font.family: root.display
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.now, "HH:mm")
            color: "#ffffff"
            font.family: root.rounded
            font.pixelSize: 168
            font.weight: Font.Bold
            font.letterSpacing: -4
        }
    }

    // ── Lock-view hint ────────────────────────────────────────────────
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        text: "Press any key or click to log in"
        color: "#ffffff"
        font.family: root.text
        font.pixelSize: 15
        opacity: root.loginMode ? 0 : 0.6
        Behavior on opacity { NumberAnimation { duration: 250 } }

        SequentialAnimation on anchors.bottomMargin {
            running: !root.loginMode
            loops: Animation.Infinite
            NumberAnimation { to: 62; duration: 1200; easing.type: Easing.InOutSine }
            NumberAnimation { to: 56; duration: 1200; easing.type: Easing.InOutSine }
        }
    }

    // ── Login card ────────────────────────────────────────────────────
    Column {
        id: loginCard
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.46 + (root.loginMode ? 0 : 40)
        spacing: 14
        opacity: root.loginMode ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 450; easing.type: Easing.OutCubic } }

        // Avatar: AccountsService icon if there is one, else the initial.
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 104
            height: 104

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: Qt.rgba(1, 1, 1, 0.16)
                border.color: Qt.rgba(1, 1, 1, 0.3)
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    visible: avatarImg.status !== Image.Ready
                    text: root.displayName.charAt(0).toUpperCase()
                    color: "#ffffff"
                    font.family: root.rounded
                    font.pixelSize: 46
                    font.weight: Font.Bold
                }
            }
            Image {
                id: avatarImg
                anchors.fill: parent
                source: root.currentUser.icon ? root.currentUser.icon : ""
                fillMode: Image.PreserveAspectCrop
                visible: false
            }
            Rectangle { id: avatarMask; anchors.fill: parent; radius: width / 2; visible: false; layer.enabled: true }
            MultiEffect {
                anchors.fill: parent
                visible: avatarImg.status === Image.Ready
                source: avatarImg
                maskEnabled: true
                maskSource: avatarMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

        // Name, with ‹ › to switch user when there is more than one.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Text {
                visible: root.users.length > 1
                text: "‹"
                color: "#ffffff"
                opacity: 0.6
                font.pixelSize: 22
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.userIndex = (root.userIndex + root.users.length - 1) % root.users.length }
            }
            Text {
                text: root.displayName
                color: "#ffffff"
                font.family: root.display
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
            Text {
                visible: root.users.length > 1
                text: "›"
                color: "#ffffff"
                opacity: 0.6
                font.pixelSize: 22
                MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.userIndex = (root.userIndex + 1) % root.users.length }
            }
        }

        // Password pill.
        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            width: 300
            height: 44
            radius: 22
            color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1
            border.color: root.errorText !== "" ? Qt.rgba(1, 0.27, 0.23, 0.85) : Qt.rgba(1, 1, 1, 0.22)
            Behavior on border.color { ColorAnimation { duration: 200 } }
            transform: Translate { id: shakeT }

            TextInput {
                id: password
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 48
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: "#ffffff"
                font.family: root.text
                font.pixelSize: 15
                font.letterSpacing: 2
                enabled: !root.busy
                clip: true
                onTextChanged: { if (text !== "") root.errorText = ""; idleTimer.restart() }
                Keys.onReturnPressed: root.tryLogin()
                Keys.onEnterPressed: root.tryLogin()
                Keys.onEscapePressed: root.exitLogin()

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: password.text.length === 0
                    text: root.busy ? "Signing in…" : (keyboard.capsLock ? "Enter Password  ⇪" : "Enter Password")
                    color: "#ffffff"
                    opacity: 0.55
                    font.family: root.text
                    font.pixelSize: 14
                }
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 32
                height: 32
                radius: 16
                color: password.text.length > 0 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.2)
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: password.text.length > 0 ? "#000000" : "#ffffff"
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                MouseArea { anchors.fill: parent; onClicked: root.tryLogin() }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.errorText !== "" ? root.errorText : " "
            color: "#ff6961"
            font.family: root.text
            font.pixelSize: 13
        }
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: shakeT; property: "x"; to: -16; duration: 50 }
        NumberAnimation { target: shakeT; property: "x"; to: 14; duration: 70 }
        NumberAnimation { target: shakeT; property: "x"; to: -9; duration: 70 }
        NumberAnimation { target: shakeT; property: "x"; to: 5; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
    }

    // ── Bottom bar: session picker (left), power (right) ──────────────
    component GlassButton: Rectangle {
        id: gb
        property string icon: ""       // icons/<name>.svg, recolored white
        property string label: ""
        signal clicked()
        width: label !== "" ? gbRow.implicitWidth + 28 : 44
        height: 44
        radius: 22
        color: gbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.24) : Qt.rgba(1, 1, 1, 0.13)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.16)
        scale: gbMouse.pressed ? 0.93 : 1
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        Row {
            id: gbRow
            anchors.centerIn: parent
            spacing: 8
            Item {
                visible: gb.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                height: 18
                Image {
                    id: gbIcon
                    anchors.fill: parent
                    source: gb.icon !== "" ? "icons/" + gb.icon + ".svg" : ""
                    sourceSize.width: 36
                    sourceSize.height: 36
                    smooth: true
                    visible: false
                    layer.enabled: true
                }
                Rectangle { id: gbFill; anchors.fill: parent; color: "#ffffff"; visible: false }
                MultiEffect {
                    anchors.fill: parent
                    source: gbFill
                    maskEnabled: true
                    maskSource: gbIcon
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 0.2
                    maskThresholdMax: 1.0
                    maskSpreadAtMax: 0.0
                }
            }
            Text {
                visible: gb.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: gb.label
                color: "#ffffff"
                font.family: root.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
        MouseArea {
            id: gbMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: gb.clicked()
        }
    }

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 32
        spacing: 10
        opacity: root.loginMode ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 350 } }

        GlassButton {
            icon: "view-list-symbolic"
            label: root.sessions[root.sessionIndex] || "Session"
            onClicked: { if (root.sessions.length > 0) root.sessionIndex = (root.sessionIndex + 1) % root.sessions.length; idleTimer.restart() }
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 32
        spacing: 10

        GlassButton { visible: sddm.canSuspend; icon: "weather-clear-night-symbolic"; onClicked: sddm.suspend() }
        GlassButton { visible: sddm.canReboot; icon: "system-reboot-symbolic"; onClicked: sddm.reboot() }
        GlassButton { visible: sddm.canPowerOff; icon: "system-shutdown-symbolic"; onClicked: sddm.powerOff() }
    }

    Component.onCompleted: keyCatcher.forceActiveFocus()
}
