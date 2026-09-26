pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Live ECB exchange rates (frankfurter.dev, base EUR), fetched lazily the
// first time a currency query is typed and refreshed at most hourly.
// Shared by the calculator and the launcher's calc row.
Singleton {
    id: root
    property var rates: null        // { CODE: units per 1 EUR }, EUR included
    property string date: ""        // ECB reference date
    property bool loading: false
    property bool failed: false
    property real _fetchedAt: 0

    function ensure() {
        if (loading) return
        if (rates && Date.now() - _fetchedAt < 3600 * 1000) return
        if (failed && Date.now() - _fetchedAt < 60 * 1000) return
        loading = true
        fetch.running = true
    }

    Process {
        id: fetch
        command: ["curl", "-sf", "--max-time", "8", "https://api.frankfurter.dev/v1/latest?base=EUR"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                root._fetchedAt = Date.now()
                try {
                    const j = JSON.parse(text)
                    const r = Object.assign({ EUR: 1 }, j.rates)
                    root.rates = r
                    root.date = j.date || ""
                    root.failed = false
                } catch (e) {
                    root.failed = true
                }
            }
        }
        onExited: (code) => { if (code !== 0) { root.loading = false; root.failed = true; root._fetchedAt = Date.now() } }
    }
}
