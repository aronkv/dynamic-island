import Quickshell.Services.Mpris
import QtQuick

Item {
    readonly property var activePlayer: {
        for (const p of Mpris.players.values) {
            if (p.isPlaying) return p
        }
        return null
    }

    // Prefers a playing player, but falls back to the first player found at
    // all (e.g. Spotify open but paused) — used wherever the UI should keep
    // showing track info through a pause instead of treating "paused" the
    // same as "nothing running at all". activePlayer stays strict (playing
    // only) since it also drives the automatic mini-pill-replaces-clock
    // behavior, which shouldn't fire just because a paused player exists.
    readonly property var anyPlayer: activePlayer ?? (Mpris.players.values.length > 0 ? Mpris.players.values[0] : null)
}
