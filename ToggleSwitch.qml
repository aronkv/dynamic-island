import QtQuick

// Shared iOS-style switch (replaces four identical inline copies). Scales
// with its size: the knob is always height - 2*pad. While pressed the knob
// stretches sideways, like iOS. Monochrome per the project palette: white
// track + black knob = on.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled()

    implicitWidth: 34
    implicitHeight: 18
    radius: height / 2
    color: checked ? "#ffffff" : "#3a3a3c"
    Behavior on color { ColorAnimation { duration: 180 } }

    readonly property real pad: Math.max(2, Math.round(height * 0.1))
    readonly property real knobSize: height - pad * 2

    Rectangle {
        height: sw.knobSize
        width: sw.knobSize + (mouse.pressed ? sw.knobSize * 0.3 : 0)
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? sw.width - width - sw.pad : sw.pad
        color: sw.checked ? "#000000" : "#ffffff"

        Behavior on x { SpringAnimation { spring: 5; damping: 0.45; epsilon: 0.2 } }
        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
