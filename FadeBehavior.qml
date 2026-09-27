import QtQuick

// Asymmetric content fade for island states: leaving content fades out
// fast (so it never lingers over what's coming in, e.g. the media card
// over the idle cover thumbnail while the notch shrinks), incoming content
// waits a beat for the morph to start, then fades in.
// Usage: `FadeBehavior on opacity {}`
Behavior {
    id: fb
    SequentialAnimation {
        PauseAnimation { duration: fb.targetValue > 0.5 && !Theme.reduceMotion ? 70 : 0 }
        NumberAnimation {
            duration: Theme.reduceMotion ? 120 : fb.targetValue > 0.5 ? 230 : 70
            easing.type: fb.targetValue > 0.5 ? Easing.OutCubic : Easing.InQuad
        }
    }
}
