.pragma library

// Quick-add parser for calendar reminders:
//   "tomorrow 9:00 dentist", "dec 24 18:00 dinner", "friday 10am meeting",
//   "2026-10-01 call mom", "in 2 hours stretch", "9:30 standup",
//   "dentist tomorrow at 9". Date and time may appear anywhere; the rest is
// the title. Without a date: today (or tomorrow if the time has passed).
// Without a time: all-day (time ""). `selected` (Date) is the day picked in
// the grid, used when no date is typed.
// Returns { title, date: "YYYY-MM-DD", time: "HH:MM" | "" } or null.

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
const WEEKDAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

function pad(n) { return String(n).padStart(2, "0") }
function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }

function parse(input, now, selected) {
    let s = " " + input.trim().replace(/\s+/g, " ") + " "
    if (s.trim() === "") return null
    const today = dayStart(now)
    let date = null, time = null
    const take = (re, fn) => {
        const m = s.match(re)
        if (!m) return false
        if (fn(m) === false) return false
        s = s.replace(m[0], " ")
        return true
    }

    // Relative "in N minutes/hours/days".
    take(/\sin (\d+) ?(m|min|mins|minutes?|h|hr|hrs|hours?|d|days?|w|weeks?)\s/i, m => {
        const n = +m[1], u = m[2].toLowerCase()
        if (u[0] === "m") { const t = new Date(now.getTime() + n * 60000); date = dayStart(t); time = pad(t.getHours()) + ":" + pad(t.getMinutes()) }
        else if (u[0] === "h") { const t = new Date(now.getTime() + n * 3600000); date = dayStart(t); time = pad(t.getHours()) + ":" + pad(t.getMinutes()) }
        else if (u[0] === "d") date = addDays(today, n)
        else date = addDays(today, n * 7)
    })

    // Dates.
    if (!date) take(/\s(today|tonight)\s/i, m => { date = today; if (m[1].toLowerCase() === "tonight" && !time) time = "20:00" })
    if (!date) take(/\s(tomorrow|tmrw|tmr)\s/i, () => { date = addDays(today, 1) })
    if (!date) take(/\s(\d{4})[-./](\d{1,2})[-./](\d{1,2})\.?\s/, m => { date = new Date(+m[1], +m[2] - 1, +m[3]) })
    if (!date) take(/\s(\d{1,2})\.(\d{1,2})\.(?:(\d{4})\.?)?\s/, m => {
        // Hungarian order: month.day. (e.g. 10.01.) when a year is missing,
        // day.month.year when a year follows.
        if (m[3]) date = new Date(+m[3], +m[2] - 1, +m[1])
        else { date = new Date(today.getFullYear(), +m[1] - 1, +m[2]); if (date < today) date = new Date(today.getFullYear() + 1, +m[1] - 1, +m[2]) }
    })
    const MONTH_NAMES = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
    const monthIdx = w => {
        const t = w.toLowerCase()
        const i = MONTH_NAMES.indexOf(t)
        if (i >= 0) return i
        if (t === "sept") return 8
        return MONTHS.indexOf(t)
    }
    const yearless = (mo, d) => { let x = new Date(today.getFullYear(), mo, d); if (x < today) x = new Date(today.getFullYear() + 1, mo, d); return x }
    if (!date) take(/\s([a-z]{3,9})\.? (\d{1,2})(?:st|nd|rd|th)?(?:,? (\d{4}))?\s/i, m => {
        const mo = monthIdx(m[1]); if (mo < 0) return false
        date = m[3] ? new Date(+m[3], mo, +m[2]) : yearless(mo, +m[2])
    })
    if (!date) take(/\s(\d{1,2})(?:st|nd|rd|th)?\.? ([a-z]{3,9})\.?(?: (\d{4}))?\s/i, m => {
        const mo = monthIdx(m[2]); if (mo < 0) return false
        date = m[3] ? new Date(+m[3], mo, +m[1]) : yearless(mo, +m[1])
    })
    if (!date) take(/\s(?:on )?(?:next )?(sunday|sun|monday|mon|tuesday|tues|tue|wednesday|wed|thursday|thurs|thur|thu|friday|fri|saturday|sat)\.?\s/i, m => {
        const wd = WEEKDAYS.indexOf(m[1].slice(0, 3).toLowerCase())
        let diff = (wd - today.getDay() + 7) % 7
        if (diff === 0) diff = 7
        date = addDays(today, diff)
    })

    // Times: 9:00, 09.30 (only with a colon/dot + 2 digits), 9am, 9 pm, "at 9".
    if (!time) take(/\s(?:at |@)?(\d{1,2})[:.](\d{2}) ?(am|pm)?\s/i, m => {
        let h = +m[1]; const mi = +m[2]
        if (m[3]) { if (m[3].toLowerCase() === "pm" && h < 12) h += 12; if (m[3].toLowerCase() === "am" && h === 12) h = 0 }
        if (h > 23 || mi > 59) return false
        time = pad(h) + ":" + pad(mi)
    })
    if (!time) take(/\s(?:at |@)?(\d{1,2}) ?(am|pm)\s/i, m => {
        let h = +m[1]; if (h > 12) return false
        if (m[2].toLowerCase() === "pm" && h < 12) h += 12
        if (m[2].toLowerCase() === "am" && h === 12) h = 0
        time = pad(h) + ":00"
    })
    if (!time) take(/\s(?:at|@) ?(\d{1,2})\s/i, m => { const h = +m[1]; if (h > 23) return false; time = pad(h) + ":00" })

    const title = s.replace(/\s(at|on)\s*$/i, " ").replace(/^\s*(at|on)\s/i, " ").trim().replace(/\s+/g, " ")
    if (title === "") return null
    if (!date) {
        const base = selected ? dayStart(selected) : today
        date = base
        if (time && iso(base) === iso(today)) {
            const [h, mi] = time.split(":").map(Number)
            if (h * 60 + mi <= now.getHours() * 60 + now.getMinutes()) date = addDays(today, 1)
        }
    }
    return { title: title.charAt(0).toUpperCase() + title.slice(1), date: iso(date), time: time || "" }
}
