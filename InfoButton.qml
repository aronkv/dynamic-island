import QtQuick

// Round "i" button that toggles a row's details (Bluetooth / Wi-Fi panels).
Rectangle {
    id: ib
    property bool open: false
    signal clicked()
    implicitWidth: 24
    implicitHeight: 24
    radius: 12
    color: open ? "#ffffff" : (ibMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : "transparent")
    border.width: open ? 0 : 1.2
    border.color: Qt.rgba(1, 1, 1, 0.45)
    // No colour animation: the "i" flips colour instantly, so a fading
    // fill left it white on white for a moment.
    // Drawn instead of a text "i": the glyph's line box sat off-centre.
    Column {
        anchors.centerIn: parent
        spacing: 2
        opacity: ib.open ? 1 : 0.7
        // Whole-pixel sizes, same width: the dot stays over the stem.
        Rectangle { width: 2; height: 2; radius: 1; color: ib.open ? "#000000" : "#ffffff" }
        Rectangle { width: 2; height: 6; radius: 1; color: ib.open ? "#000000" : "#ffffff" }
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
