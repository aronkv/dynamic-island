import QtQuick

// Asymmetric content fade for island states: leaving content fades out
// fast (so it never lingers over what's coming in, e.g. the media card
// over the idle cover thumbnail while the notch shrinks); incoming content
// fades in with a slow start instead of a delay. A delay kept it invisible
// (`visible: opacity > 0`) for the first 90 ms, so its first-render cost
// landed mid-morph as a hitch; now it becomes visible on the first frame,
// inside the notch's own short start delay (DynamicIsland morphState).
// Usage: `FadeBehavior on opacity {}`
Behavior {
    id: fb
    NumberAnimation {
        duration: Theme.reduceMotion ? 120 : fb.targetValue > 0.5 ? 340 : 70
        easing.type: fb.targetValue > 0.5 ? Easing.InOutQuad : Easing.InQuad
    }
}
