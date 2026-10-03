import QtQuick

// Screen-recording indicator: a floating black capsule (pulsing red dot +
// elapsed time) in idleBadgeLeft, next to the charging badge, instead of
// inside the idle pill — same fade/scale-in as IndicatorBadge.
// Click → the expanded activity view (signal `openRequested`).
Rectangle {
    id: badge
    property var store: null
    property int size: 44
    // Liquid Glass, same as the tray badge: translucent surface + stacked
    // 0.3-alpha rings fading into a black core (glassRim 0 = solid black).
    property color surfaceColor: "#000000"
    property real glassRim: 0
    signal openRequested()

    readonly property bool active: !!store && store.recording

    width: Math.max(size, row.implicitWidth + 24)
    height: size
    radius: height / 2
    color: surfaceColor

    opacity: active ? 1 : 0
    scale: active ? 1 : 0.7
    visible: opacity > 0

    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 300 } }

    Repeater {
        model: 4
        Rectangle {
            required property int index
            anchors.fill: parent
            anchors.margins: badge.glassRim * 0.6 * index / 4
            radius: height / 2
            color: Qt.rgba(0, 0, 0, badge.glassRim > 0 ? 0.3 : 1)
            visible: badge.glassRim > 0 || index === 0
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: badge.glassRim * 0.6
        radius: height / 2
        color: "#000000"
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10
            height: 10
            radius: 5
            color: "#ff453a"
            SequentialAnimation on opacity {
                running: badge.active
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: badge.store ? badge.store.format(badge.store.recordElapsed) : ""
            color: "#ff453a"
            font.pixelSize: 13
            font.weight: 600
            font.family: Theme.fontText
            font.features: { "tnum": 1 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: badge.openRequested()
    }
}
