import QtQuick

// Content scale for island states: grows in with an ease-out (no
// overshoot — it read as the panel jumping at the end of opening), shrinks
// away quickly. During a panel-to-panel switch (Theme.switching) the
// incoming content appears at full size and the outgoing one barely moves
// while it fades, so the switch doesn't look like a reopen.
// Usage: `ScaleBehavior on scale {}`
Behavior {
    id: sb
    NumberAnimation {
        duration: Theme.reduceMotion ? 0
            : Theme.switching ? (sb.targetValue > 0.95 ? 0 : 600)
            : sb.targetValue > 0.95 ? Theme.contentScaleDuration : 140
        easing.type: Theme.switching ? Easing.Linear : sb.targetValue > 0.95 ? Easing.OutCubic : Easing.InQuad
    }
}
