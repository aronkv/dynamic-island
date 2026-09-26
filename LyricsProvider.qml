import Quickshell.Io
import QtQuick

Item {
    id: lyricsProvider
    property var player: null

    // Only works for local-file players (mpv etc.) that expose a file:// url
    // in their MPRIS metadata. Streaming apps (Spotify, browser tabs) have
    // no local file to look next to, so this stays "" for them.
    readonly property string lrcPath: {
        if (!player) return ""
        const meta = player.metadata
        const url = meta ? meta["xesam:url"] : undefined
        if (!url || !url.startsWith("file://")) return ""
        const path = decodeURIComponent(url.slice("file://".length))
        return path.replace(/\.[^./]+$/, ".lrc")
    }

    FileView {
        id: lrcFile
        path: lyricsProvider.lrcPath
        printErrors: false
    }

    readonly property string lrcText: lyricsProvider.lrcPath ? lrcFile.text() : ""
    readonly property var localSyncedLines: lrcText ? parseLrc(lrcText) : []

    readonly property string trackKey: player ? (player.trackTitle + "::" + player.trackArtist) : ""

    property string _fetchedForKey: ""
    property string _onlineState: "none" // "none" | "loading" | "synced" | "plain" | "notFound"
    property var onlineSyncedLines: []
    property string onlinePlainLyrics: ""

    // Local always wins when it has something; online is the fallback.
    readonly property var syncedLines: localSyncedLines.length > 0 ? localSyncedLines : onlineSyncedLines
    readonly property string plainLyrics: onlinePlainLyrics

    readonly property string state: {
        if (!player) return "none"
        if (localSyncedLines.length > 0) return "synced"
        if (_onlineState === "none") return "loading"
        return _onlineState
    }

    onTrackKeyChanged: {
        onlineSyncedLines = []
        onlinePlainLyrics = ""
        _onlineState = "none"
        _fetchedForKey = ""
        maybeFetchOnline()
    }

    onLrcTextChanged: maybeFetchOnline()

    // Browser-sourced MPRIS metadata (YouTube etc.) is often noisy compared
    // to a real music player's tags — clean the two most common patterns
    // before querying lrclib, without touching what's actually displayed.
    function cleanArtist(artist) {
        return artist.replace(/\s*-\s*topic\s*$/i, "").trim()
    }

    function cleanTitle(title) {
        return title.replace(/\s*[([][^)\]]*\b(official|video|audio|lyrics?|visualizer|hd|4k|remaster\w*)\b[^)\]]*[)\]]\s*/gi, "").trim()
    }

    // Online lookup always prefers TIMESTAMPED (synced) lyrics:
    //  1. /api/get — exact match on artist/title/album/duration. Synced → done.
    //  2. Otherwise /api/search with a few query variants; among the results
    //     that HAVE syncedLyrics pick the best by title/artist match, length
    //     (±15 s of the track) and — when step 1 returned plain lyrics —
    //     word overlap with that text (so we get the same song, timed).
    //  3. Only if no timed version exists anywhere: plain lyrics / not found.
    property string _plainFromGet: ""
    property var _searchQueue: []
    property var _candidates: []

    function _norm(t) {
        return (t || "").toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
            .replace(/\s*[([].*?[)\]]\s*/g, " ").replace(/\b(feat|ft)\.?\b.*$/, "")
            .replace(/[^a-z0-9]+/g, " ").trim()
    }
    function _words(t) {
        const set = {}
        for (const w of _norm(t).split(" ")) if (w.length > 2) set[w] = true
        return set
    }
    function _overlap(a, b) {
        const wa = _words(a), wb = _words(b)
        const ka = Object.keys(wa), kb = Object.keys(wb)
        if (ka.length === 0 || kb.length === 0) return 0
        let common = 0
        for (const k of ka) if (wb[k]) common++
        return common / Math.max(ka.length, kb.length)
    }

    function maybeFetchOnline() {
        if (!player || !trackKey) return
        if (localSyncedLines.length > 0) return
        if (_fetchedForKey === trackKey) return
        _fetchedForKey = trackKey
        _onlineState = "loading"
        _plainFromGet = ""
        _candidates = []

        const artist = cleanArtist(player.trackArtist)
        const title = cleanTitle(player.trackTitle)
        const firstArtist = artist.split(/\s*(?:,|&| x | and |feat\.?|ft\.?)\s*/i)[0]
        const bareTitle = title.replace(/\s*[([]?\b(feat|ft)\.?\b.*$/i, "").trim()
        // Distinct search variants, most specific first.
        const variants = []
        const add = (t, a) => { const k = t + "|" + a; if (t && !variants.some(v => v.k === k)) variants.push({ k: k, t: t, a: a }) }
        // "Song - Remastered 2011" / "Song - Live" → "Song"
        const dashTitle = bareTitle.replace(/\s+-\s+.*$/, "").trim()
        add(title, artist)
        add(bareTitle, firstArtist)
        add(dashTitle, firstArtist)
        add(dashTitle, "")
        _searchQueue = variants

        fetchProcess.running = false
        fetchProcess.command = [
            "curl", "-s", "--max-time", "8", "-G", "https://lrclib.net/api/get",
            "--data-urlencode", "artist_name=" + artist,
            "--data-urlencode", "track_name=" + title,
            "--data-urlencode", "album_name=" + player.trackAlbum,
            "--data-urlencode", "duration=" + Math.round(player.length)
        ]
        fetchProcess.running = true
    }

    function _nextSearch() {
        if (_searchQueue.length === 0) { _finishSearch(); return }
        const v = _searchQueue[0]
        _searchQueue = _searchQueue.slice(1)
        const cmd = ["curl", "-s", "--max-time", "8", "-G", "https://lrclib.net/api/search",
                     "--data-urlencode", "track_name=" + v.t]
        if (v.a) cmd.push("--data-urlencode", "artist_name=" + v.a)
        searchProcess.forKey = trackKey
        searchProcess.command = cmd
        searchProcess.running = true
    }

    function _scoreCandidate(r) {
        if (!r || !r.syncedLyrics || !player) return -1
        const len = player.length
        let score = 0
        if (len > 0 && r.duration) {
            const dd = Math.abs(r.duration - len)
            if (dd > 15) return -1
            score += 3 * (1 - dd / 15)
        }
        const t = _norm(player.trackTitle), rt = _norm(r.trackName)
        score += rt === t ? 3 : (rt.includes(t) || t.includes(rt)) ? 1.5 : 0
        const a = _norm(player.trackArtist), ra = _norm(r.artistName)
        score += ra === a ? 2 : (ra && a && (ra.includes(a.split(" ")[0]) || a.includes(ra.split(" ")[0]))) ? 1 : 0
        if (_plainFromGet) {
            const syncedText = r.syncedLyrics.replace(/\[[^\]]*\]/g, " ")
            score += 4 * _overlap(syncedText, _plainFromGet)
        }
        return score
    }

    function _finishSearch() {
        let best = null, bestScore = -1
        for (const r of _candidates) {
            const sc = _scoreCandidate(r)
            if (sc > bestScore) { best = r; bestScore = sc }
        }
        if (best && bestScore >= 2) {
            const lines = parseLrc(best.syncedLyrics)
            if (lines.length > 0) {
                onlineSyncedLines = lines
                _onlineState = "synced"
                return
            }
        }
        if (_plainFromGet) {
            onlinePlainLyrics = _plainFromGet
            _onlineState = "plain"
        } else {
            _onlineState = "notFound"
        }
    }

    Process {
        id: fetchProcess
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                let data = null
                try { data = JSON.parse(text) } catch (e) {}
                if (data && data.instrumental) { lyricsProvider._onlineState = "notFound"; return }
                if (data && data.syncedLyrics) {
                    const lines = lyricsProvider.parseLrc(data.syncedLyrics)
                    if (lines.length > 0) {
                        lyricsProvider.onlineSyncedLines = lines
                        lyricsProvider._onlineState = "synced"
                        return
                    }
                }
                // No timed lyrics from the exact match: remember the plain
                // text (used to pick the right timed version) and search.
                lyricsProvider._plainFromGet = data && data.plainLyrics ? data.plainLyrics : ""
                lyricsProvider._nextSearch()
            }
        }
    }

    Process {
        id: searchProcess
        property string forKey: ""
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (searchProcess.forKey !== lyricsProvider.trackKey) return   // track changed meanwhile
                try {
                    const list = JSON.parse(text)
                    if (Array.isArray(list)) lyricsProvider._candidates = lyricsProvider._candidates.concat(list)
                } catch (e) {}
                // Stop early once a strong timed candidate exists.
                if (lyricsProvider._candidates.some(r => lyricsProvider._scoreCandidate(r) >= 7))
                    lyricsProvider._searchQueue = []
                lyricsProvider._nextSearch()
            }
        }
    }

    function parseLrc(text) {
        const lines = []
        const tagRe = /\[(\d+):(\d+(?:\.\d+)?)\]/g
        for (const raw of text.split(/\r?\n/)) {
            let m, tags = [], lastIndex = 0
            while ((m = tagRe.exec(raw)) !== null) {
                tags.push(parseInt(m[1], 10) * 60 + parseFloat(m[2]))
                lastIndex = tagRe.lastIndex
            }
            if (tags.length === 0) continue
            const lyricText = raw.slice(lastIndex).trim()
            for (const t of tags) lines.push({ timeSeconds: t, text: lyricText })
        }
        lines.sort((a, b) => a.timeSeconds - b.timeSeconds)
        return lines
    }

    function currentLineIndex(posSeconds) {
        const lines = syncedLines
        let lo = 0, hi = lines.length - 1, ans = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (lines[mid].timeSeconds <= posSeconds) { ans = mid; lo = mid + 1 }
            else hi = mid - 1
        }
        return ans
    }
}
