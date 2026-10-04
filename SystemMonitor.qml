import Quickshell.Io
import QtQuick

// System stats for the System panel (SUPER+M). Polls only while `active`
// (1 s): one fixed shell script (no interpolated data → safe as sh -c)
// dumps /proc/stat, /proc/meminfo, /proc/net/dev, the hwmon temps/fan and
// the default-route interface; CPU / network rates come from deltas.
// The same script also reads CPU clocks, the i915 GPU (actual frequency +
// RC6 residency → busy share), /proc/diskstats, uptime/loadavg and the
// battery packs' power_now. Top processes (top) every 2 s, disk usage
// (df /) + the root disk's name every 30 s.
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
    property real cpuFreq: 0             // GHz, average of all cores
    property real gpuFreq: 0             // MHz (actual)
    property real gpuMaxFreq: 0
    property real gpuBusy: 0             // 0..1 (1 − RC6 share)
    property bool hasGpu: false
    property real diskRead: 0            // bytes/s
    property real diskWrite: 0
    property string rootDisk: ""         // e.g. "nvme0n1"
    property real uptime: 0              // seconds
    property var load: [0, 0, 0]
    property real power: 0               // W, sum over battery packs
    property string powerStatus: ""      // "Charging" / "Discharging" / "Full" / …

    property var cpuHist: []
    property var memHist: []
    property var rxHist: []
    property var txHist: []
    property var tempHist: []
    property var gpuHist: []
    property var readHist: []
    property var writeHist: []
    property var powerHist: []

    property var _prevCpu: null          // [total, idle] per line
    property var _prevNet: null          // { rx, tx, t }
    property var _prevGpu: null          // { rc6, t }
    property var _prevDisk: null         // { r, w, t, disk }

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
            "t=$(cat $d/temp1_input 2>/dev/null); f=$(cat $d/fan1_input 2>/dev/null); echo \"$n ${t:--} ${f:--}\"; done; " +
            "echo '#FREQ'; cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null; " +
            "echo '#GPU'; for g in /sys/class/drm/card*/gt/gt0; do [ -r $g/rc6_residency_ms ] && " +
            "echo $(cat $g/rps_act_freq_mhz) $(cat $g/rps_max_freq_mhz) $(cat $g/rc6_residency_ms) && break; done; " +
            "echo '#DISK'; cat /proc/diskstats; echo '#UP'; cat /proc/uptime /proc/loadavg; " +
            "echo '#BAT'; for b in /sys/class/power_supply/BAT*; do echo $(cat $b/power_now 2>/dev/null) $(cat $b/status 2>/dev/null); done"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: mon._parse(text)
        }
    }

    function _parse(text) {
        let section = ""
        const cpuLines = [], mem = {}, net = [], hw = [], freqs = [], disk = [], up = [], bat = []
        let gpu = null
        let iface = ""
        for (const line of text.split("\n")) {
            if (line.startsWith("#")) { section = line; continue }
            if (section === "#STAT" && line.startsWith("cpu")) cpuLines.push(line.trim().split(/\s+/))
            else if (section === "#MEM") { const m = line.match(/^(\w+):\s+(\d+)/); if (m) mem[m[1]] = parseInt(m[2]) * 1024 }
            else if (section === "#NET" && line.indexOf(":") !== -1) net.push(line)
            else if (section === "#IFACE" && line.trim() !== "") iface = line.trim()
            else if (section === "#HW" && line.trim() !== "") hw.push(line.trim().split(/\s+/))
            else if (section === "#FREQ" && line.trim() !== "") freqs.push(parseInt(line))
            else if (section === "#GPU" && line.trim() !== "") gpu = line.trim().split(/\s+/).map(Number)
            else if (section === "#DISK" && line.trim() !== "") disk.push(line.trim().split(/\s+/))
            else if (section === "#UP" && line.trim() !== "") up.push(line.trim().split(/\s+/))
            else if (section === "#BAT" && line.trim() !== "") bat.push(line.trim().split(/\s+/))
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

        if (freqs.length) mon.cpuFreq = freqs.reduce((a, b) => a + b, 0) / freqs.length / 1e6

        // GPU busy = share of the interval NOT spent in RC6 (power-gated).
        const now = Date.now()
        if (gpu && gpu.length >= 3) {
            mon.hasGpu = true
            mon.gpuFreq = gpu[0]
            mon.gpuMaxFreq = gpu[1]
            if (mon._prevGpu) {
                const dt = now - mon._prevGpu.t
                if (dt > 0) mon.gpuBusy = Math.max(0, Math.min(1, 1 - (gpu[2] - mon._prevGpu.rc6) / dt))
                mon.gpuHist = mon._push(mon.gpuHist, mon.gpuBusy)
            }
            mon._prevGpu = { rc6: gpu[2], t: now }
        }

        // Root disk throughput: sectors read (f[5]) / written (f[9]), 512 B.
        const d = disk.find(f => f[2] === mon.rootDisk)
        if (d) {
            const r = Number(d[5]) * 512, w = Number(d[9]) * 512
            if (mon._prevDisk && mon._prevDisk.disk === mon.rootDisk) {
                const dt = (now - mon._prevDisk.t) / 1000
                if (dt > 0) {
                    mon.diskRead = Math.max(0, (r - mon._prevDisk.r) / dt)
                    mon.diskWrite = Math.max(0, (w - mon._prevDisk.w) / dt)
                    mon.readHist = mon._push(mon.readHist, mon.diskRead)
                    mon.writeHist = mon._push(mon.writeHist, mon.diskWrite)
                }
            }
            mon._prevDisk = { r: r, w: w, t: now, disk: mon.rootDisk }
        }

        if (up.length >= 2) {
            mon.uptime = parseFloat(up[0][0]) || 0
            mon.load = [parseFloat(up[1][0]) || 0, parseFloat(up[1][1]) || 0, parseFloat(up[1][2]) || 0]
        }

        // power_now is µW; summed over both packs (T480 has two).
        if (bat.length) {
            mon.power = bat.reduce((a, b) => a + (parseInt(b[0]) || 0), 0) / 1e6
            const st = bat.map(b => b[1] || "")
            mon.powerStatus = st.indexOf("Charging") !== -1 ? "Charging" : st.indexOf("Discharging") !== -1 ? "Discharging" : (st[0] || "")
            mon.powerHist = mon._push(mon.powerHist, mon.power)
        }
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
        // Also resolves the root filesystem's whole disk (nvme0n1p6 →
        // nvme0n1) for the throughput readout.
        command: ["sh", "-c", "df -B1 --output=size,used /; echo '#ROOT'; lsblk -no PKNAME \"$(findmnt -no SOURCE / | sed 's/\\[.*//')\""]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                const parts = text.split("#ROOT")
                const l = parts[0].trim().split("\n")[1]
                if (l) {
                    const f = l.trim().split(/\s+/).map(Number)
                    mon.diskTotal = f[0]; mon.diskUsed = f[1]
                }
                const root = (parts[1] || "").trim().split("\n")[0]
                if (root) mon.rootDisk = root.trim()
            }
        }
    }

    function duration(secs) {
        const d = Math.floor(secs / 86400), h = Math.floor(secs % 86400 / 3600), m = Math.floor(secs % 3600 / 60)
        return (d > 0 ? d + "d " : "") + (d > 0 || h > 0 ? h + "h " : "") + m + "m"
    }

    function bytes(b) {
        const u = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (b >= 100 || i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i]
    }
}
