import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// Visual content of the lock screen (iOS/macOS style), kept separate from
// the WlSessionLock wrapper so it can also be previewed in a normal window.
// Blurred + dimmed wallpaper, big clock and date, a now-playing card when
// something plays, and a password pill that shakes on a wrong password.
Item {
    id: root
    property string wallpaperPath: ""
    property var player: null
    property real batteryPercent: -1
    property bool charging: false
    property bool busy: false          // PAM check running
    property string errorText: ""
    signal submit(string password)

    function fail(msg) {
        root.errorText = msg
        passwordInput.text = ""
        shake.restart()
    }
    function clearError() { root.errorText = "" }

    Rectangle { anchors.fill: parent; color: "#000000" }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
        sourceSize.width: 960
        fillMode: Image.PreserveAspectCrop
        visible: false
        asynchronous: true
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        blurMax: 64
        brightness: -0.25
        saturation: 0.2
    }
    // Vignette toward the bottom for the password area.
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.15) }
            GradientStop { position: 0.6; color: Qt.rgba(0, 0, 0, 0.2) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.6) }
        }
    }

    // Entry animation.
    opacity: 0
    Component.onCompleted: fadeIn.start()
    NumberAnimation { id: fadeIn; target: root; property: "opacity"; to: 1; duration: 400; easing.type: Easing.OutCubic }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // Top-right status: iOS-style horizontal battery with the percentage
    // inside it (green while charging, red at 20% or below).
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        spacing: 4
        visible: root.batteryPercent >= 0

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.charging
            text: "\u26A1"
            color: "#ffffff"
            font.pixelSize: 16
        }

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 50
            height: 24

            Rectangle {
                id: battBody
                width: 46
                height: parent.height
                radius: 7
                color: Qt.rgba(1, 1, 1, 0.3)

                // Level fill, clipped to the body's rounded shape.
                Rectangle {
                    width: Math.max(parent.radius * 2, parent.width * Math.min(1, root.batteryPercent / 100))
                    height: parent.height
                    radius: parent.radius
                    color: root.charging ? "#32d74b"
                        : root.batteryPercent <= 20 ? "#ff453a" : "#ffffff"
                }

                Text {
                    anchors.centerIn: parent
                    text: Math.round(root.batteryPercent)
                    // Dark digits on a white/green fill, white on a red or
                    // mostly-empty one.
                    color: !root.charging && root.batteryPercent <= 20 ? "#ffffff"
                        : root.batteryPercent >= 45 ? "#000000" : "#ffffff"
                    font.pixelSize: 15
                    font.weight: 800
                    font.family: Theme.fontText
                    font.features: { "tnum": 1 }
                }
            }

            // Terminal nub.
            Rectangle {
                anchors.left: battBody.right
                anchors.leftMargin: 1
                anchors.verticalCenter: battBody.verticalCenter
                width: 3
                height: 8
                radius: 1.5
                color: Qt.rgba(1, 1, 1, 0.4)
            }
        }
    }

    ColumnLayout {
        id: clockColumn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.12
        spacing: 0

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(clock.date, "dddd, MMMM d")
            color: "#ffffff"
            opacity: 0.85
            font.pixelSize: 22
            font.weight: 600
            font.family: Theme.font
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: "#ffffff"
            font.pixelSize: 128
            font.weight: 700
            font.family: Theme.fontRounded
            font.letterSpacing: -3
        }
    }

    // Now playing card.
    Rectangle {
        id: nowPlaying
        visible: root.player !== null && root.player.trackTitle !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: clockColumn.bottom
        anchors.topMargin: 28
        width: 380
        height: 76
        radius: 20
        color: Qt.rgba(1, 1, 1, 0.10)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1

        ClippingRectangle {
            id: art
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            height: 52
            radius: 10
            color: "#222222"
            Image {
                anchors.fill: parent
                source: root.player ? root.player.trackArtUrl : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: 104
            }
        }

        Column {
            anchors.left: art.right
            anchors.leftMargin: 12
            anchors.right: controls.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                width: parent.width
                text: root.player ? root.player.trackTitle : ""
                color: "#ffffff"
                font.pixelSize: 14
                font.weight: 700
                font.family: Theme.font
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.player ? root.player.trackArtist : ""
                color: "#ffffff"
                opacity: 0.65
                font.pixelSize: 12
                font.family: Theme.fontText
                elide: Text.ElideRight
            }
        }

        Row {
            id: controls
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            LockMediaButton {
                icon: "media-skip-backward-symbolic"
                onClicked: if (root.player) root.player.previous()
            }
            LockMediaButton {
                primary: true
                icon: root.player && root.player.isPlaying ? "media-playback-pause-symbolic" : "media-playback-start-symbolic"
                onClicked: if (root.player) root.player.togglePlaying()
            }
            LockMediaButton {
                icon: "media-skip-forward-symbolic"
                onClicked: if (root.player) root.player.next()
            }
        }
    }

    // Transport button: symbolic Adwaita icon recolored through a mask
    // (threshold 0.5, no spread — see CLAUDE.md). The play/pause one sits in
    // a white disc with a dark glyph; the others get a faint hover circle.
    component LockMediaButton: Item {
        id: btn
        property string icon: ""
        property bool primary: false
        signal clicked()
        width: 36
        height: 36
        Rectangle {
            anchors.centerIn: parent
            width: btn.primary ? 36 : 32
            height: width
            radius: width / 2
            color: btn.primary ? "#ffffff" : Qt.rgba(1, 1, 1, btnMouse.containsMouse ? 0.14 : 0)
            scale: btnMouse.pressed ? 0.9 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        IconImage {
            id: glyph
            anchors.centerIn: parent
            width: btn.primary ? 16 : 18
            height: width
            source: "image://icon/" + btn.icon
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }
        Rectangle { id: glyphFill; anchors.fill: glyph; color: btn.primary ? "#111111" : "#ffffff"; visible: false }
        MultiEffect {
            anchors.fill: glyph
            source: glyphFill
            maskEnabled: true
            maskSource: glyph
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.0
            maskThresholdMax: 1.0
            maskSpreadAtMax: 0.0
            scale: btnMouse.pressed ? 0.9 : 1
        }
        MouseArea {
            id: btnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // Password area.
    ColumnLayout {
        id: authColumn
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.12
        spacing: 12

        // Avatar: initial in a circle.
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 64
            height: 64
            radius: 32
            color: Qt.rgba(1, 1, 1, 0.15)
            border.color: Qt.rgba(1, 1, 1, 0.25)
            border.width: 1
            Text {
                anchors.centerIn: parent
                text: (Quickshell.env("USER") || "?").charAt(0).toUpperCase()
                color: "#ffffff"
                font.pixelSize: 28
                font.weight: 600
                font.family: Theme.fontRounded
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Quickshell.env("USER") || ""
            color: "#ffffff"
            font.pixelSize: 15
            font.weight: 600
            font.family: Theme.font
        }

        Rectangle {
            id: pill
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 4
            width: 260
            height: 40
            radius: 20
            color: Qt.rgba(1, 1, 1, 0.14)
            border.color: root.errorText !== "" ? Qt.rgba(1, 0.27, 0.23, 0.8) : Qt.rgba(1, 1, 1, 0.2)
            border.width: 1
            Behavior on border.color { ColorAnimation { duration: 200 } }

            transform: Translate { id: shakeT; x: 0 }

            TextInput {
                id: passwordInput
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 44
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                passwordCharacter: "●"
                color: "#ffffff"
                font.pixelSize: 14
                font.letterSpacing: 2
                font.family: Theme.fontText
                focus: true
                enabled: !root.busy
                clip: true
                onTextChanged: if (text.length > 0) root.clearError()
                Keys.onReturnPressed: if (text.length > 0) root.submit(text)
                Keys.onEnterPressed: if (text.length > 0) root.submit(text)
                Keys.onEscapePressed: text = ""

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: passwordInput.text.length === 0
                    text: root.busy ? "Checking…" : "Enter Password"
                    color: "#ffffff"
                    opacity: 0.55
                    font.pixelSize: 13
                    font.family: Theme.fontText
                }
            }

            // Submit arrow.
            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                radius: 15
                color: passwordInput.text.length > 0 ? "#ffffff" : Qt.rgba(1, 1, 1, 0.2)
                Behavior on color { ColorAnimation { duration: 150 } }
                Text {
                    anchors.centerIn: parent
                    text: "→"
                    color: passwordInput.text.length > 0 ? "#000000" : "#ffffff"
                    font.pixelSize: 15
                    font.weight: 700
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (passwordInput.text.length > 0) root.submit(passwordInput.text)
                }
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.errorText !== "" ? root.errorText : " "
            color: "#ff6961"
            font.pixelSize: 12
            font.family: Theme.fontText
        }
    }

    SequentialAnimation {
        id: shake
        loops: 1
        NumberAnimation { target: shakeT; property: "x"; to: -14; duration: 50 }
        NumberAnimation { target: shakeT; property: "x"; to: 12; duration: 70 }
        NumberAnimation { target: shakeT; property: "x"; to: -8; duration: 70 }
        NumberAnimation { target: shakeT; property: "x"; to: 5; duration: 60 }
        NumberAnimation { target: shakeT; property: "x"; to: 0; duration: 60 }
    }

    // Keep the keyboard on the password field whatever is clicked.
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: passwordInput.forceActiveFocus()
    }
    function focusInput() { passwordInput.forceActiveFocus() }
}
