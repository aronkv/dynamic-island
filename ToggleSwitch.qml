import QtQuick

// Shared iOS-style switch (replaces four identical inline copies). Scales
// with its size: the knob is always height - 2*pad. While pressed the knob
// stretches toward the side it will travel to, like iOS. Monochrome per the
// project palette: white track + black knob = on.
//
// Motion: one eased NumberAnimation for the knob's left/right edges plus
// color fades on the same curve — no spring (the old under-damped spring
// wobbled and fought the press-stretch on release).
Rectangle {
    id: sw
    property bool checked: false
    signal toggled()

    implicitWidth: 34
    implicitHeight: 18
    radius: height / 2
    color: checked ? "#ffffff" : "#3a3a3c"

    readonly property int duration: Theme.reduceMotion ? 0 : 260
    readonly property real pad: Math.max(2, Math.round(height * 0.1))
    readonly property real knobSize: height - pad * 2
    readonly property real stretch: mouse.pressed ? Math.round(knobSize * 0.3) : 0

    Behavior on color { ColorAnimation { duration: sw.duration; easing.type: Easing.OutCubic } }

    // The knob is defined by its left and right edges; the stretch extends
    // the edge facing the travel direction, so pressing never moves the
    // resting edge and releasing never makes it jump back.
    property real knobLeft: checked ? width - pad - knobSize - (mouse.pressed ? stretch : 0) : pad
    property real knobRight: checked ? width - pad : pad + knobSize + stretch
    Behavior on knobLeft { NumberAnimation { duration: sw.duration; easing.type: Easing.OutCubic } }
    Behavior on knobRight { NumberAnimation { duration: sw.duration; easing.type: Easing.OutCubic } }

    Rectangle {
        x: Math.round(sw.knobLeft)
        y: Math.round(sw.pad)
        width: Math.round(sw.knobRight - sw.knobLeft)
        height: sw.knobSize
        radius: height / 2
        color: sw.checked ? "#000000" : "#ffffff"
        Behavior on color { ColorAnimation { duration: sw.duration; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
}
