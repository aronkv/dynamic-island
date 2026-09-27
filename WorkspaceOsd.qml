import Quickshell
import Quickshell.Hyprland
import QtQuick

// Workspace indicator shown INSIDE the idle pill (the pill doesn't resize):
// for a moment after a workspace switch the pill's content is replaced by a
// row of dots in the theme accent color — occupied workspaces brighter, the
// active one a wider pill. The active pill moves with an iOS page-control
// style stretch: the leading edge races to the new slot, the trailing edge
// follows a beat later, so it stretches across and then snaps together.
Item {
    id: osd
    property color accent: "#ffffff"
    // Dark theme accents (e.g. a deep wallpaper green) are brightened so
    // the dots stay readable on the black pill.
    readonly property real _lum: 0.2126 * accent.r + 0.7152 * accent.g + 0.0722 * accent.b
    readonly property color dotColor: _lum < 0.35 ? Qt.lighter(accent, 0.35 / Math.max(0.05, _lum)) : accent

    readonly property int activeId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0)
    // Includes the workspace we came FROM (_fromId), so the pill animates
    // between two slots that both exist: leaving an empty 9 → 1 used to
    // drop slot 9 at the moment of the switch and the pill flew in from
    // outside the row. _fromId is reset once the dots are hidden again.
    property int _fromId: activeId
    readonly property int slotCount: Math.max(5, activeId, _fromId, workspaces.reduce((m, w) => Math.max(m, w.id), 0))
    onVisibleChanged: if (!visible) _fromId = activeId

    function occupied(id) {
        const ws = workspaces.find(w => w.id === id)
        return ws ? ws.toplevels.values.length > 0 : false
    }

    // Shrink the spacing when many workspaces wouldn't fit in the pill.
    readonly property real _fit: Math.min(1, (width - 28) / ((slotCount - 1) * 14 + 20))
    readonly property real dotSize: 7 * Math.max(0.7, _fit)
    readonly property real gap: 7 * _fit
    readonly property real pillWidth: 20 * _fit
    // Dots sit on a fixed grid; the active pill covers its slot and grows
    // to the right by (pillWidth - dotSize), with later dots shifted over.
    readonly property real rowWidth: (slotCount - 1) * (dotSize + gap) + pillWidth
    readonly property real originX: (width - rowWidth) / 2

    function slotX(id) {
        const i = id - 1
        const a = activeId - 1
        return originX + i * (dotSize + gap) + (i > a ? pillWidth - dotSize : 0)
    }

    // Stretch animation: animate the pill's two edges separately.
    property int _prevId: activeId
    property bool _movingRight: true
    property real leftEdge: slotX(activeId)
    property real rightEdge: slotX(activeId) + pillWidth
    onActiveIdChanged: {
        _fromId = _prevId
        _movingRight = activeId > _prevId
        _prevId = activeId
        leftEdge = slotX(activeId)
        rightEdge = slotX(activeId) + pillWidth
    }
    onWidthChanged: { leftEdge = slotX(activeId); rightEdge = slotX(activeId) + pillWidth }

    Behavior on leftEdge {
        NumberAnimation {
            duration: Theme.reduceMotion ? 0 : osd._movingRight ? 380 : 190
            easing.type: osd._movingRight ? Easing.OutBack : Easing.OutCubic
            easing.overshoot: 1.2
        }
    }
    Behavior on rightEdge {
        NumberAnimation {
            duration: Theme.reduceMotion ? 0 : osd._movingRight ? 190 : 380
            easing.type: osd._movingRight ? Easing.OutCubic : Easing.OutBack
            easing.overshoot: 1.2
        }
    }

    Repeater {
        model: osd.slotCount
        Rectangle {
            required property int index
            readonly property int wsId: index + 1
            visible: wsId !== osd.activeId
            anchors.verticalCenter: parent.verticalCenter
            x: osd.slotX(wsId)
            width: osd.dotSize
            height: osd.dotSize
            radius: osd.dotSize / 2
            color: osd.dotColor
            opacity: osd.occupied(wsId) ? 0.75 : 0.28
            Behavior on x { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: Math.min(osd.leftEdge, osd.rightEdge - osd.dotSize)
        width: Math.max(osd.dotSize, osd.rightEdge - osd.leftEdge)
        height: osd.dotSize
        radius: osd.dotSize / 2
        color: osd.dotColor
    }
}
