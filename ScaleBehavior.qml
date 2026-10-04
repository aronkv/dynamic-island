import QtQuick

// Content scale for island states: grows in with an ease-out (no
// overshoot — it read as the panel jumping at the end of opening), shrinks
// away quickly. Usage: `ScaleBehavior on scale {}`
Behavior {
    id: sb
    NumberAnimation {
        duration: Theme.reduceMotion ? 0 : sb.targetValue > 0.95 ? Theme.contentScaleDuration : 140
        easing.type: sb.targetValue > 0.95 ? Easing.OutCubic : Easing.InQuad
    }
}
