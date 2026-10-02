import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.Mpris

// Apple Music style transport: seek bar (thickens while hovered/dragged)
// with elapsed / remaining time, then shuffle · prev · big round play ·
// next · repeat.
ColumnLayout {
    id: controls
    property var player: null
    property color accentColor: "#ffffff"
    spacing: 8

    function formatTime(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0
        const m = Math.floor(sec / 60)
        const s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    component MediaButton: Item {
        id: btn
        property string icon: ""
        property bool btnEnabled: true
        property int iconSize: 18
        property color colorizationColor: "#ffffff"
        signal clicked()

        implicitWidth: 34
        implicitHeight: 34
        opacity: btnEnabled ? 1 : 0.3
        scale: mouse.pressed ? 0.82 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 2 } }

        // Soft circular press highlight, like iOS.
        Rectangle {
            anchors.centerIn: parent
            width: parent.width
            height: width
            radius: width / 2
            color: "#ffffff"
            opacity: mouse.pressed ? 0.12 : mouse.containsMouse ? 0.06 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
        }

        IconImage {
            id: iconImg
            anchors.centerIn: parent
            implicitSize: btn.iconSize
            source: "image://icon/" + btn.icon
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }

        Rectangle {
            id: flatFill
            anchors.fill: iconImg
            color: btn.colorizationColor
            visible: false
            Behavior on color { ColorAnimation { duration: 150 } }
        }

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

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.btnEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    // ── Seek bar ────────────────────────────────────────────────────────
    Item {
        id: seekBar
        Layout.fillWidth: true
        implicitHeight: 14
        z: 5

        // Live position, interpolated every frame from the last real reading
        // (MPRIS position isn't reactive while playing). A fresh reading is
        // taken immediately when the controls appear, so opening the card
        // shows the right spot at once — no sliding in from zero — and the
        // fill then moves continuously with the music.
        property real basePos: 0
        property real baseTime: 0
        property real livePos: 0
        // Re-entrancy guard: forcing positionChanged() can make the player
        // re-emit isPlaying/length/track changes, whose handlers call sync()
        // again — that loop ended in "RangeError: Maximum call stack size
        // exceeded" in the live log.
        property bool _syncing: false
        function sync() {
            if (_syncing) return
            _syncing = true
            try {
                if (!controls.player) { basePos = 0; livePos = 0; return }
                controls.player.positionChanged()
                basePos = controls.player.position
                baseTime = Date.now()
                livePos = basePos
            } finally {
                _syncing = false
            }
        }
        Connections {
            target: controls
            function onVisibleChanged() { if (controls.visible) seekBar.sync() }
            function onPlayerChanged() { seekBar.sync() }
        }
        Connections {
            target: controls.player
            ignoreUnknownSignals: true
            function onIsPlayingChanged() { seekBar.sync() }
            function onTrackTitleChanged() { seekBar.sync() }
            function onLengthChanged() { seekBar.sync() }
        }
        Component.onCompleted: sync()
        // Re-anchor to the real position now and then (drift, external seeks).
        Timer {
            interval: 1000
            repeat: true
            running: controls.visible && controls.player !== null && !seekMouse.pressed
            onTriggered: seekBar.sync()
        }
        FrameAnimation {
            running: controls.visible && controls.player !== null && controls.player.isPlaying && !seekMouse.pressed
            onTriggered: seekBar.livePos = seekBar.basePos + (Date.now() - seekBar.baseTime) / 1000
        }

        readonly property real length: controls.player ? controls.player.length : 0
        property real dragProgress: -1
        readonly property real progress: dragProgress >= 0 ? dragProgress
            : length > 0 ? Math.max(0, Math.min(1, livePos / length)) : 0
        readonly property bool active: seekMouse.containsMouse || seekMouse.pressed
        readonly property real hoverRatio: seekMouse.containsMouse ? Math.max(0, Math.min(1, seekMouse.mouseX / seekMouse.width)) : 0

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: seekBar.active ? 6 : 4
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.25)
            Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // Hover preview: lighter band up to the cursor.
            Rectangle {
                visible: seekMouse.containsMouse && !seekMouse.pressed
                height: parent.height
                radius: parent.radius
                width: track.width * seekBar.hoverRatio
                color: Qt.rgba(1, 1, 1, 0.18)
            }

            Rectangle {
                id: fill
                height: parent.height
                radius: parent.radius
                width: Math.max(height, track.width * seekBar.progress)
                color: controls.accentColor
            }
        }

        // Knob at the playback position while hovered / dragged.
        Rectangle {
            width: seekBar.active ? 13 : 0
            height: width
            radius: width / 2
            anchors.verticalCenter: track.verticalCenter
            x: Math.max(0, Math.min(track.width, track.width * seekBar.progress)) - width / 2
            color: controls.accentColor
            Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutBack; easing.overshoot: 2 } }
        }

        // Time bubble above the cursor (drag: at the drag position).
        Rectangle {
            id: bubble
            readonly property real ratio: seekMouse.pressed ? seekBar.progress : seekBar.hoverRatio
            visible: seekBar.active && seekBar.length > 0
            width: bubbleText.implicitWidth + 14
            height: 20
            radius: 6
            color: Qt.rgba(0.08, 0.08, 0.09, 0.95)
            border.color: Qt.rgba(1, 1, 1, 0.12)
            border.width: 1
            y: -height - 6
            x: Math.max(-4, Math.min(seekBar.width - width + 4, track.width * ratio - width / 2))
            Text {
                id: bubbleText
                anchors.centerIn: parent
                text: controls.formatTime(bubble.ratio * seekBar.length)
                color: "#ffffff"
                font.pixelSize: 11
                font.weight: 600
                font.family: Theme.fontText
                font.features: { "tnum": 1 }
            }
        }

        MouseArea {
            id: seekMouse
            anchors.fill: parent
            anchors.topMargin: -6
            anchors.bottomMargin: -6
            hoverEnabled: true
            enabled: controls.player && controls.player.canSeek
            cursorShape: Qt.PointingHandCursor

            function ratio(x) { return Math.max(0, Math.min(1, x / width)) }
            onPressed: (mouse) => seekBar.dragProgress = ratio(mouse.x)
            onPositionChanged: (mouse) => { if (pressed) seekBar.dragProgress = ratio(mouse.x) }
            onReleased: {
                if (controls.player && seekBar.dragProgress >= 0) {
                    const target = seekBar.dragProgress * seekBar.length
                    controls.player.position = target
                    seekBar.basePos = target
                    seekBar.baseTime = Date.now()
                    seekBar.livePos = target
                }
                seekBar.dragProgress = -1
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: -2

        Text {
            text: controls.formatTime(controls.player ? seekBar.progress * controls.player.length : 0)
            color: "#ffffff"
            opacity: 0.55
            font.pixelSize: 10
            font.weight: 500
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "-" + controls.formatTime(controls.player ? (1 - seekBar.progress) * controls.player.length : 0)
            color: "#ffffff"
            opacity: 0.55
            font.pixelSize: 10
            font.weight: 500
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }

    // ── Transport ───────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        spacing: 0

        MediaButton {
            icon: "media-playlist-shuffle-symbolic"
            iconSize: 15
            btnEnabled: controls.player && controls.player.shuffleSupported
            colorizationColor: controls.player && controls.player.shuffle ? controls.accentColor : "#ffffff"
            opacity: !btnEnabled ? 0.3 : (controls.player && controls.player.shuffle ? 1 : 0.55)
            onClicked: controls.player.shuffle = !controls.player.shuffle
        }

        Item { Layout.fillWidth: true }

        MediaButton {
            icon: "media-skip-backward-symbolic"
            iconSize: 20
            implicitWidth: 40
            implicitHeight: 40
            btnEnabled: controls.player && controls.player.canGoPrevious
            onClicked: controls.player.previous()
        }

        Item { implicitWidth: 18 }

        // Big round play/pause: white disc, black glyph; the glyph swaps
        // with a quick scale+fade morph.
        Item {
            id: playBtn
            implicitWidth: 46
            implicitHeight: 46
            readonly property bool playing: controls.player ? controls.player.isPlaying : false
            readonly property bool usable: controls.player && (controls.player.canPause || controls.player.canPlay)
            opacity: usable ? 1 : 0.35
            scale: playMouse.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 2 } }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#ffffff"
            }

            Repeater {
                model: ["media-playback-pause-symbolic", "media-playback-start-symbolic"]

                Item {
                    required property string modelData
                    required property int index
                    readonly property bool shown: (index === 0) === playBtn.playing
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    opacity: shown ? 1 : 0
                    scale: shown ? 1 : 0.4
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }

                    IconImage {
                        id: playIcon
                        anchors.fill: parent
                        // Optical centering: the play triangle sits a bit left.
                        anchors.leftMargin: parent.index === 1 ? 2 : 0
                        source: "image://icon/" + parent.modelData
                        visible: false
                        layer.enabled: true
                        smooth: true
                        mipmap: true
                    }

                    Rectangle {
                        id: playFill
                        anchors.fill: playIcon
                        color: "#000000"
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: playIcon
                        source: playFill
                        maskEnabled: true
                        maskSource: playIcon
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 0.0
                        maskThresholdMax: 1.0
                        maskSpreadAtMax: 0.0
                    }
                }
            }

            MouseArea {
                id: playMouse
                anchors.fill: parent
                enabled: playBtn.usable
                cursorShape: Qt.PointingHandCursor
                onClicked: controls.player.togglePlaying()
            }
        }

        Item { implicitWidth: 18 }

        MediaButton {
            icon: "media-skip-forward-symbolic"
            iconSize: 20
            implicitWidth: 40
            implicitHeight: 40
            btnEnabled: controls.player && controls.player.canGoNext
            onClicked: controls.player.next()
        }

        Item { Layout.fillWidth: true }

        MediaButton {
            icon: controls.player && controls.player.loopState === MprisLoopState.Track
                ? "media-playlist-repeat-song-symbolic" : "media-playlist-repeat-symbolic"
            iconSize: 15
            btnEnabled: controls.player && controls.player.loopSupported
            colorizationColor: controls.player && controls.player.loopState !== MprisLoopState.None ? controls.accentColor : "#ffffff"
            opacity: !btnEnabled ? 0.3 : (controls.player && controls.player.loopState !== MprisLoopState.None ? 1 : 0.55)
            onClicked: {
                const next = {
                    [MprisLoopState.None]: MprisLoopState.Track,
                    [MprisLoopState.Track]: MprisLoopState.Playlist,
                    [MprisLoopState.Playlist]: MprisLoopState.None
                }
                controls.player.loopState = next[controls.player.loopState]
            }
        }
    }
}
