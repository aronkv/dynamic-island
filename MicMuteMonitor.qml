import Quickshell.Services.Pipewire
import QtQuick

// Mirrors VolumeMonitor.qml exactly, but for the default audio SOURCE (mic)
// instead of the sink — drives the mic-mute OSD (Extension 12). The
// dedicated hardware mic-mute key (XF86AudioMicMute) is already bound in
// keybindings.lua to `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle`; this
// monitor just reacts to whatever actually changes that state, from any
// source (the key, or `pactl`/`wpctl` run any other way).
Item {
    id: micMuteMonitor

    readonly property var source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: micMuteMonitor.source ? [micMuteMonitor.source] : []
    }

    readonly property bool ready: Pipewire.ready && source !== null && source.ready && source.audio !== null
    readonly property bool muted: ready ? source.audio.muted : false
}
