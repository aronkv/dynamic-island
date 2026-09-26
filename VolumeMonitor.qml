import Quickshell.Services.Pipewire
import QtQuick

Item {
    id: volumeMonitor

    readonly property var sink: Pipewire.defaultAudioSink

    // A PwNode's live properties (audio.volume/audio.muted) don't update
    // over the wire unless the node is registered here — without this the
    // monitor would just read whatever the volume was at bind time, once,
    // and appear frozen forever.
    PwObjectTracker {
        objects: volumeMonitor.sink ? [volumeMonitor.sink] : []
    }

    readonly property bool ready: Pipewire.ready && sink !== null && sink.ready && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false
}
