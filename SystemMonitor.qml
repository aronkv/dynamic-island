import Quickshell.Io
import QtQuick

// System stats for the System panel (SUPER+M). Polls only while `active`
// (1 s): one fixed shell script (no interpolated data → safe as sh -c)
// dumps /proc/stat, /proc/meminfo, /proc/net/dev, the hwmon temps/fan and
// the default-route interface; CPU / network rates come from deltas.
// Top processes (ps) every 2 s, disk usage (df /) every 30 s.
// Keeps 60-sample histories for the sparklines.
Item {
    id: mon
    property bool active: false

    property real cpu: 0                 // 0..1 total
    property var cores: []               // 0..1 per core
    property real memUsed: 0             // bytes
    property real memTotal: 1
    property real swapUsed: 0
    property real swapTotal: 0
    property real cpuTemp: 0             // °C (coretemp package)
    property real ssdTemp: 0             // °C (nvme)
    property int fanRpm: 0
    property string iface: ""
    property real rxRate: 0              // bytes/s
    property real txRate: 0
    property real diskUsed: 0
    property real diskTotal: 1
    property var procs: []               // [{ name, cpu, mem }]

    property var cpuHist: []
    property var memHist: []
    property var rxHist: []
    property var txHist: []
    property var tempHist: []

    property var _prevCpu: null          // [total, idle] per line
    property var _prevNet: null          // { rx, tx, t }

    function _push(arr, v) { const a = arr.concat([v]); return a.length > 60 ? a.slice(a.length - 60) : a }

    Timer {
        interval: 1000
        running: mon.active
        repeat: true
        triggeredOnStart: true
        onTriggered: statProc.running = true
    }
    Timer {
        interval: 2000
        running: mon.active
        repeat: true
        triggeredOnStart: true
        onTriggered: psProc.running = true
    }
    Timer {
        interval: 30000
        running: mon.active
        repeat: true
        triggeredOnStart: true
        onTriggered: dfProc.running = true
    }

    Process {
        id: statProc
        command: ["sh", "-c",
            "echo '#STAT'; grep '^cpu' /proc/stat; echo '#MEM'; cat /proc/meminfo; echo '#NET'; cat /proc/net/dev; " +
            "echo '#IFACE'; ip route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i==\"dev\"){print $(i+1); exit}}'; " +
            "echo '#HW'; for d in /sys/class/hwmon/hwmon*; do n=$(cat $d/name 2>/dev/null); " +
            "t=$(cat $d/temp1_input 2>/dev/null); f=$(cat $d/fan1_input 2>/dev/null); echo \"$n ${t:--} ${f:--}\"; done"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: mon._parse(text)
        }
    }

    function _parse(text) {
        let section = ""
        const cpuLines = [], mem = {}, net = [], hw = []
        let iface = ""
        for (const line of text.split("\n")) {
            if (line.startsWith("#")) { section = line; continue }
            if (section === "#STAT" && line.startsWith("cpu")) cpuLines.push(line.trim().split(/\s+/))
            else if (section === "#MEM") { const m = line.match(/^(\w+):\s+(\d+)/); if (m) mem[m[1]] = parseInt(m[2]) * 1024 }
            else if (section === "#NET" && line.indexOf(":") !== -1) net.push(line)
            else if (section === "#IFACE" && line.trim() !== "") iface = line.trim()
            else if (section === "#HW" && line.trim() !== "") hw.push(line.trim().split(/\s+/))
        }

        // CPU: busy share since the last sample, per line (cpu, cpu0, cpu1…).
        const cur = cpuLines.map(f => {
            const v = f.slice(1).map(Number)
            const idle = v[3] + (v[4] || 0)
            return [v.reduce((a, b) => a + b, 0), idle]
        })
        if (mon._prevCpu && mon._prevCpu.length === cur.length) {
            const usage = cur.map((c, i) => {
                const dt = c[0] - mon._prevCpu[i][0], di = c[1] - mon._prevCpu[i][1]
                return dt > 0 ? Math.max(0, Math.min(1, 1 - di / dt)) : 0
            })
            mon.cpu = usage[0]
            mon.cores = usage.slice(1)
            mon.cpuHist = mon._push(mon.cpuHist, mon.cpu)
        }
        mon._prevCpu = cur

        if (mem.MemTotal) {
            mon.memTotal = mem.MemTotal
            mon.memUsed = mem.MemTotal - (mem.MemAvailable || 0)
            mon.swapTotal = mem.SwapTotal || 0
            mon.swapUsed = (mem.SwapTotal || 0) - (mem.SwapFree || 0)
            mon.memHist = mon._push(mon.memHist, mon.memUsed / mon.memTotal)
        }

        mon.iface = iface
        const row = net.find(l => l.trim().startsWith(iface + ":"))
        if (row) {
            const f = row.split(":")[1].trim().split(/\s+/).map(Number)
            const now = Date.now(), rx = f[0], tx = f[8]
            if (mon._prevNet && mon._prevNet.iface === iface) {
                const dt = (now - mon._prevNet.t) / 1000
                if (dt > 0) {
                    mon.rxRate = Math.max(0, (rx - mon._prevNet.rx) / dt)
                    mon.txRate = Math.max(0, (tx - mon._prevNet.tx) / dt)
                    mon.rxHist = mon._push(mon.rxHist, mon.rxRate)
                    mon.txHist = mon._push(mon.txHist, mon.txRate)
                }
            }
            mon._prevNet = { rx: rx, tx: tx, t: now, iface: iface }
        }

        for (const h of hw) {
            if (h[0] === "coretemp" && h[1] !== "-") mon.cpuTemp = parseInt(h[1]) / 1000
            else if (h[0] === "nvme" && h[1] !== "-") mon.ssdTemp = parseInt(h[1]) / 1000
            if (h[0] === "thinkpad" && h[2] !== "-") mon.fanRpm = parseInt(h[2])
        }
        mon.tempHist = mon._push(mon.tempHist, mon.cpuTemp)
    }

    // Current per-process CPU needs two samples (ps' %CPU is a lifetime
    // average): top -n 2, parse the second block.
    Process {
        id: psProc
        command: ["top", "-b", "-n", "2", "-d", "0.5", "-w", "200", "-o", "%CPU"]
        environment: ({ LC_ALL: "C" })   // "15.4", not the locale's "15,4"
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const blocks = text.split(/^top - /m)
                const last = blocks[blocks.length - 1].split("\n")
                const hdr = last.findIndex(l => /^\s*PID\s/.test(l))
                if (hdr < 0) return
                const out = []
                for (const line of last.slice(hdr + 1)) {
                    const f = line.trim().split(/\s+/)
                    if (f.length < 12) continue
                    const name = f.slice(11).join(" ")
                    if (name === "top") continue
                    out.push({ name: name, cpu: parseFloat(f[8]) || 0, mem: parseFloat(f[9]) || 0 })
                    if (out.length >= 5) break
                }
                mon.procs = out
            }
        }
    }

    Process {
        id: dfProc
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const l = text.trim().split("\n")[1]
                if (!l) return
                const f = l.trim().split(/\s+/).map(Number)
                mon.diskTotal = f[0]; mon.diskUsed = f[1]
            }
        }
    }

    function bytes(b) {
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i]
    }
}
