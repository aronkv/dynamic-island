import QtQuick

// Content scale for island states: pops in with a slight overshoot,
// shrinks away quickly without one. Usage: `ScaleBehavior on scale {}`
Behavior {
    id: sb
    NumberAnimation {
        duration: Theme.reduceMotion ? 0 : sb.targetValue > 0.95 ? Theme.contentScaleDuration : 140
        easing.type: sb.targetValue > 0.95 ? Easing.OutBack : Easing.InQuad
        easing.overshoot: 1.4
    }
}
