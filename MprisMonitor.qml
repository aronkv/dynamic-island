import Quickshell.Services.Mpris
import QtQuick

Item {
    // A browser tab can show up as two MPRIS players at once: Brave's own
    // (no artUrl) and the Plasma Browser Integration extension's (with the
    // cover as a /tmp file). Prefer whichever has art so the island shows
    // the cover instead of an empty placeholder.
    function _pick(list) {
        return list.find(p => p.trackArtUrl) ?? list[0] ?? null
    }

    readonly property var activePlayer: _pick(Mpris.players.values.filter(p => p.isPlaying))

    // Prefers a playing player, but falls back to the first player found at
    // all (e.g. Spotify open but paused) — used wherever the UI should keep
    // showing track info through a pause instead of treating "paused" the
    // same as "nothing running at all". activePlayer stays strict (playing
    // only) since it also drives the automatic mini-pill-replaces-clock
    // behavior, which shouldn't fire just because a paused player exists.
    // A stopped player with nothing loaded (Strawberry open but stopped)
    // doesn't count: the island showed an empty cover, title and player
    // card for it. Paused players with a track still count.
    readonly property var anyPlayer: activePlayer ?? _pick(Mpris.players.values.filter(p =>
        p.playbackState !== MprisPlaybackState.Stopped && (p.trackTitle || "") !== ""))

    // Lower-case names identifying a player's app, for matching its PipeWire
    // output stream (CavaMonitor): the D-Bus name segment ("spotify",
    // "brave" from org.mpris.MediaPlayer2.brave.instance123) and the first
    // word of its Identity ("Brave" for the browser extension's player).
    function appKeys(p) {
        if (!p) return []
        const keys = []
        const seg = (p.dbusName || "").replace("org.mpris.MediaPlayer2.", "").split(".")[0].toLowerCase()
        if (seg) keys.push(seg)
        const id = (p.identity || "").split(" ")[0].toLowerCase()
        if (id && !keys.includes(id)) keys.push(id)
        return keys
    }
}
