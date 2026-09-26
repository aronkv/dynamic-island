.pragma library

// "Smart" calculator queries, tried before plain math:
//   dates     — days until christmas / easter / 2026-12-31 / 24 dec,
//               days since …, today + 30 days, date in 2 weeks
//   currency  — 100 usd, 100 usd to eur, 5000 huf in eur, €20, $15
//   units     — 5 km to miles, 180 cm in ft, 30 c to f, 2 gb to mb
// Pure functions (no QML), so the same file is unit-tested with node.
// Every parser returns null when the input isn't its kind, or
//   { kind, text, sub, value, copy } where `text` is the big result,
//   `sub` an optional detail line and `copy` what the copy action copies.

// ── Formatting ──────────────────────────────────────────────────────────
function group(intPart) { return intPart.replace(/\B(?=(\d{3})+(?!\d))/g, " ") }

function fmtNum(v, maxDecimals) {
    if (!isFinite(v)) return String(v)
    const d = maxDecimals === undefined ? 4 : maxDecimals
    if (v !== 0 && Math.abs(v) < Math.pow(10, -d)) return v.toPrecision(3)
    let s = v.toFixed(d)
    if (s.indexOf(".") !== -1) s = s.replace(/0+$/, "").replace(/\.$/, "")
    if (s === "-0") s = "0"
    const neg = s[0] === "-"
    if (neg) s = s.slice(1)
    const parts = s.split(".")
    return (neg ? "−" : "") + group(parts[0]) + (parts.length > 1 ? "." + parts[1] : "")
}

function parseAmount(str) {
    // "1 234,5" / "1,234.5" / "12.5" / "1.5k"
    let s = str.replace(/\s+/g, "")
    let mult = 1
    const k = s.match(/^(.*?)([km])$/i)
    if (k && /\d$/.test(k[1])) { s = k[1]; mult = k[2].toLowerCase() === "k" ? 1e3 : 1e6 }
    if (/^\d{1,3}(,\d{3})+(\.\d+)?$/.test(s)) s = s.replace(/,/g, "")
    else s = s.replace(",", ".")
    if (!/^\d*\.?\d+$/.test(s)) return NaN
    return parseFloat(s) * mult
}

// ── Dates ───────────────────────────────────────────────────────────────
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

function dayStart(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
function daysBetween(a, b) { return Math.round((dayStart(b) - dayStart(a)) / 86400000) }
function fmtDate(d) {
    return WEEKDAYS[d.getDay()] + ", " + d.getDate() + " " +
        MONTHS[d.getMonth()].charAt(0).toUpperCase() + MONTHS[d.getMonth()].slice(1) + " " + d.getFullYear()
}

// Anonymous Gregorian algorithm (Meeus/Jones/Butcher).
function easter(year) {
    const a = year % 19, b = Math.floor(year / 100), c = year % 100
    const d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25)
    const g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30
    const i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
    const m = Math.floor((a + 11 * h + 22 * l) / 451)
    const month = Math.floor((h + l - 7 * m + 114) / 31), day = ((h + l - 7 * m + 114) % 31) + 1
    return new Date(year, month - 1, day)
}

// Named days: function(year) → Date. "Next occurrence" logic is shared.
const NAMED_DAYS = {
    "christmas": y => new Date(y, 11, 25), "xmas": y => new Date(y, 11, 25),
    "christmas eve": y => new Date(y, 11, 24),
    "easter": easter,
    "new year": y => new Date(y, 0, 1), "new years": y => new Date(y, 0, 1),
    "new year's": y => new Date(y, 0, 1), "new year's eve": y => new Date(y, 11, 31),
    "new years eve": y => new Date(y, 11, 31), "nye": y => new Date(y, 11, 31),
    "halloween": y => new Date(y, 9, 31),
    "valentine": y => new Date(y, 1, 14), "valentines": y => new Date(y, 1, 14),
    "valentine's day": y => new Date(y, 1, 14), "valentines day": y => new Date(y, 1, 14),
    "summer": y => new Date(y, 5, 21), "winter": y => new Date(y, 11, 21),
    "spring": y => new Date(y, 2, 20), "autumn": y => new Date(y, 8, 22), "fall": y => new Date(y, 8, 22)
}

// Parses a date phrase. `future`: for yearless dates pick the next
// occurrence (true) or the most recent one (false).
function parseDate(str, now, future) {
    const s = str.trim().toLowerCase().replace(/^the\s+/, "").replace(/[?!.]+$/, "")
    const today = dayStart(now)
    if (s === "today") return today
    if (s === "tomorrow") return new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1)
    if (s === "yesterday") return new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)

    const pick = (fn) => {
        const y = today.getFullYear()
        if (future) { const d = fn(y); return d >= today ? d : fn(y + 1) }
        const d = fn(y); return d <= today ? d : fn(y - 1)
    }
    const named = NAMED_DAYS[s.replace(/\s+day$/, "") in NAMED_DAYS ? s.replace(/\s+day$/, "") : s]
    if (named) return pick(named)

    let m = s.match(/^(\d{4})[-./](\d{1,2})[-./](\d{1,2})\.?$/)                  // 2026-12-31, 2026.12.31.
    if (m) return new Date(+m[1], +m[2] - 1, +m[3])
    m = s.match(/^(\d{1,2})[./](\d{1,2})[./](\d{4})$/)                            // 31.12.2026
    if (m) return new Date(+m[3], +m[2] - 1, +m[1])
    const mon = t => MONTHS.indexOf(t.slice(0, 3))
    m = s.match(/^([a-z]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?$/)      // dec 25, december 25 2026
    if (m && mon(m[1]) >= 0) {
        if (m[3]) return new Date(+m[3], mon(m[1]), +m[2])
        return pick(y => new Date(y, mon(m[1]), +m[2]))
    }
    m = s.match(/^(\d{1,2})(?:st|nd|rd|th)?\.?\s+([a-z]+)\.?(?:\s+(\d{4}))?$/)     // 25 dec, 25th december 2026
    if (m && mon(m[2]) >= 0) {
        if (m[3]) return new Date(+m[3], mon(m[2]), +m[1])
        return pick(y => new Date(y, mon(m[2]), +m[1]))
    }
    return null
}

const SPAN_UNITS = { day: 1, days: 1, d: 1, week: 7, weeks: 7, w: 7, month: "M", months: "M", year: "Y", years: "Y", y: "Y" }

function addSpan(date, n, unit) {
    const u = SPAN_UNITS[unit]
    if (u === "M") return new Date(date.getFullYear(), date.getMonth() + n, date.getDate())
    if (u === "Y") return new Date(date.getFullYear() + n, date.getMonth(), date.getDate())
    return new Date(date.getFullYear(), date.getMonth(), date.getDate() + n * u)
}

function plural(n, w) { return n + " " + w + (Math.abs(n) === 1 ? "" : "s") }

function parseDateQuery(input, now) {
    const s = input.trim().toLowerCase().replace(/^how many\s+/, "").replace(/\s+are\s+there|\s+is\s+it|\s+left/g, "")
    let m = s.match(/^(days?|weeks?)\s+(until|till|til|to|before|since|from|after)\s+(.+)$/)
    if (!m) {
        m = s.match(/^(until|till|since)\s+(.+)$/)
        if (m) m = [m[0], "days", m[1], m[2]]
    }
    if (m) {
        const since = m[2] === "since" || m[2] === "after" || m[2] === "from"
        const target = parseDate(m[3], now, !since)
        if (!target) return null
        const days = since ? daysBetween(target, now) : daysBetween(now, target)
        const inWeeks = m[1].indexOf("week") === 0
        let text
        if (days === 0) text = "Today"
        else if (inWeeks) text = plural(Math.round(days / 7 * 10) / 10, "week")
        else text = plural(days, "day")
        const label = since ? "since " : "until "
        let sub = label + fmtDate(target)
        if (!inWeeks && Math.abs(days) >= 14) sub += "  ·  " + plural(Math.floor(Math.abs(days) / 7), "week") + (Math.abs(days) % 7 ? " " + plural(Math.abs(days) % 7, "day") : "")
        return { kind: "date", text: text, sub: sub, value: days, copy: String(days) }
    }
    // today + 30 days, now - 2 weeks, date in 3 months, 30 days from now
    m = s.match(/^(today|now|tomorrow|yesterday|date)\s*([+-])\s*(\d+)\s*([a-z]+)$/)
    let base, n, unit
    if (m && SPAN_UNITS[m[4]] !== undefined) { base = m[1]; n = (m[2] === "-" ? -1 : 1) * +m[3]; unit = m[4] }
    else {
        m = s.match(/^(?:date\s+)?in\s+(\d+)\s*([a-z]+)$/) || s.match(/^(\d+)\s*([a-z]+)\s+from\s+(?:now|today)$/)
        if (m && SPAN_UNITS[m[2]] !== undefined) { base = "today"; n = +m[1]; unit = m[2] }
        else {
            m = s.match(/^(\d+)\s*([a-z]+)\s+ago$/)
            if (m && SPAN_UNITS[m[2]] !== undefined) { base = "today"; n = -m[1]; unit = m[2] }
        }
    }
    if (base !== undefined) {
        const from = parseDate(base === "now" || base === "date" ? "today" : base, now, true)
        const d = addSpan(from, n, unit)
        const diff = daysBetween(now, d)
        return { kind: "date", text: fmtDate(d), sub: diff === 0 ? "today" : (diff > 0 ? "in " : "") + plural(Math.abs(diff), "day") + (diff < 0 ? " ago" : ""), value: diff, copy: d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0") }
    }
    // "what day is christmas", "easter 2027"
    m = s.match(/^(?:what day is|when is)\s+(.+)$/) || s.match(/^(easter|christmas|xmas)\s+(\d{4})$/)
    if (m) {
        let d = null
        if (m[2]) d = NAMED_DAYS[m[1]](+m[2])
        else d = parseDate(m[1], now, true)
        if (!d) return null
        const diff = daysBetween(now, d)
        return { kind: "date", text: fmtDate(d), sub: diff === 0 ? "today" : diff > 0 ? "in " + plural(diff, "day") : plural(-diff, "day") + " ago", value: diff, copy: fmtDate(d) }
    }
    return null
}

// ── Currency ────────────────────────────────────────────────────────────
const CURRENCY_ALIASES = {
    "$": "USD", "usd": "USD", "dollar": "USD", "dollars": "USD", "us$": "USD",
    "€": "EUR", "eur": "EUR", "euro": "EUR", "euros": "EUR",
    "huf": "HUF", "ft": "HUF", "forint": "HUF", "forints": "HUF",
    "£": "GBP", "gbp": "GBP", "¥": "JPY", "jpy": "JPY", "yen": "JPY",
    "chf": "CHF", "franc": "CHF", "francs": "CHF", "czk": "CZK", "kč": "CZK", "pln": "PLN", "zł": "PLN", "zloty": "PLN",
    "ron": "RON", "lei": "RON", "sek": "SEK", "nok": "NOK", "dkk": "DKK", "cad": "CAD", "aud": "AUD",
    "cny": "CNY", "yuan": "CNY", "try": "TRY", "lira": "TRY", "inr": "INR", "rupee": "INR", "rupees": "INR",
    "krw": "KRW", "won": "KRW", "brl": "BRL", "mxn": "MXN", "nzd": "NZD", "sgd": "SGD", "hkd": "HKD",
    "zar": "ZAR", "ils": "ILS", "isk": "ISK", "bgn": "BGN", "thb": "THB", "idr": "IDR", "php": "PHP", "myr": "MYR"
}
const SYMBOL = { USD: "$", EUR: "€", GBP: "£", JPY: "¥" }
const NO_DECIMALS = { HUF: true, JPY: true, KRW: true, ISK: true, IDR: true }
// Shown together when no target currency is given (minus the source).
const DEFAULT_TARGETS = ["HUF", "EUR", "USD"]

function currencyCode(tok, rates) {
    if (!tok) return null
    const t = tok.toLowerCase()
    if (CURRENCY_ALIASES[t]) return CURRENCY_ALIASES[t]
    if (/^[a-z]{3}$/.test(t) && rates && rates[t.toUpperCase()] !== undefined) return t.toUpperCase()
    return null
}

function fmtMoney(v, code) {
    let n = fmtNum(v, NO_DECIMALS[code] ? 0 : 2)
    if (!NO_DECIMALS[code]) {
        const dot = n.indexOf(".")
        n = dot === -1 ? n + ".00" : n + "0".repeat(Math.max(0, 3 - (n.length - dot)))
    }
    if (code === "HUF") return n + " Ft"
    return SYMBOL[code] ? (v < 0 ? "−" + SYMBOL[code] + n.slice(1) : SYMBOL[code] + n) : n + " " + code
}

// Returns null (not a currency query), { pending: true } (looks like one
// but rates aren't loaded yet), or a result.
function parseCurrency(input, rates) {
    const s = input.trim().replace(/\s+/g, " ")
    const num = "(\\d[\\d\\s,.]*[km]?)"
    const cur = "([$€£¥]|[a-zA-Zčł$]{1,8})"
    let m = s.match(new RegExp("^([$€£¥])\\s?" + num + "(?:\\s+(?:to|in|into|as|->|=)\\s+" + cur + ")?$", "i"))
    let amount, from, to = null
    if (m) { from = m[1]; amount = m[2]; to = m[3] || null }
    else {
        m = s.match(new RegExp("^" + num + "\\s?" + cur + "(?:\\s+(?:to|in|into|as|->|=)\\s+" + cur + ")?$", "i"))
        if (!m) return null
        amount = m[1]; from = m[2]; to = m[3] || null
    }
    const fromCode = currencyCode(from, rates)
    if (!fromCode) return null
    let toCode = null
    if (to) { toCode = currencyCode(to, rates); if (!toCode) return null }
    const value = parseAmount(amount)
    if (!isFinite(value)) return null
    if (!rates) return { pending: true }
    if (rates[fromCode] === undefined || (toCode && rates[toCode] === undefined)) return { kind: "currency", error: "No rate for " + (rates[fromCode] === undefined ? fromCode : toCode) }
    const conv = code => value / rates[fromCode] * rates[code]
    const targets = toCode ? [toCode] : DEFAULT_TARGETS.filter(c => c !== fromCode)
    const main = targets[0]
    const others = toCode ? DEFAULT_TARGETS.filter(c => c !== fromCode && c !== toCode) : targets.slice(1)
    const sub = fmtMoney(value, fromCode) + "  =  " + others.map(c => fmtMoney(conv(c), c)).concat(toCode ? [] : []).join("  ·  ")
    const mainValue = conv(main)
    return {
        kind: "currency", text: fmtMoney(mainValue, main),
        sub: others.length > 0 ? sub : "1 " + fromCode + " = " + fmtNum(rates[main] / rates[fromCode], 4) + " " + main,
        value: mainValue, copy: String(Math.round(mainValue * (NO_DECIMALS[main] ? 1 : 100)) / (NO_DECIMALS[main] ? 1 : 100))
    }
}

// ── Units ───────────────────────────────────────────────────────────────
// [dimension, factor to base unit, display name]
const UNITS = {}
function def(dim, factor, name, aliases) { aliases.forEach(a => UNITS[a] = { dim: dim, f: factor, name: name }) }
def("length", 0.001, "mm", ["mm", "millimeter", "millimeters", "millimetre", "millimetres"])
def("length", 0.01, "cm", ["cm", "centimeter", "centimeters", "centimetre", "centimetres"])
def("length", 1, "m", ["m", "meter", "meters", "metre", "metres"])
def("length", 1000, "km", ["km", "kilometer", "kilometers", "kilometre", "kilometres", "kms"])
def("length", 0.0254, "in", ["in", "inch", "inches", "\""])
def("length", 0.3048, "ft", ["ft", "foot", "feet", "'"])
def("length", 0.9144, "yd", ["yd", "yard", "yards"])
def("length", 1609.344, "mi", ["mi", "mile", "miles"])
def("length", 1852, "nmi", ["nmi", "nautical mile", "nautical miles"])
def("mass", 1e-6, "mg", ["mg", "milligram", "milligrams"])
def("mass", 0.001, "g", ["g", "gram", "grams", "gr"])
def("mass", 1, "kg", ["kg", "kilo", "kilos", "kilogram", "kilograms"])
def("mass", 1000, "t", ["t", "ton", "tons", "tonne", "tonnes"])
def("mass", 0.028349523125, "oz", ["oz", "ounce", "ounces"])
def("mass", 0.45359237, "lb", ["lb", "lbs", "pound", "pounds"])
def("mass", 6.35029318, "st", ["st", "stone", "stones"])
def("volume", 0.001, "ml", ["ml", "milliliter", "milliliters", "millilitre", "millilitres"])
def("volume", 0.01, "cl", ["cl"])
def("volume", 0.1, "dl", ["dl"])
def("volume", 1, "l", ["l", "liter", "liters", "litre", "litres"])
def("volume", 3.785411784, "gal", ["gal", "gallon", "gallons"])
def("volume", 0.946352946, "qt", ["qt", "quart", "quarts"])
def("volume", 0.473176473, "pt", ["pt", "pint", "pints"])
def("volume", 0.2365882365, "cups", ["cup", "cups"])
def("volume", 0.0295735295625, "fl oz", ["floz", "fl oz", "fluid ounce", "fluid ounces"])
def("volume", 0.01478676478125, "tbsp", ["tbsp", "tablespoon", "tablespoons"])
def("volume", 0.00492892159375, "tsp", ["tsp", "teaspoon", "teaspoons"])
def("area", 1, "m²", ["m2", "m²", "sqm", "square meter", "square meters"])
def("area", 1e6, "km²", ["km2", "km²", "square kilometer", "square kilometers"])
def("area", 1e4, "ha", ["ha", "hectare", "hectares"])
def("area", 4046.8564224, "acres", ["acre", "acres"])
def("area", 0.09290304, "ft²", ["ft2", "ft²", "sqft", "square foot", "square feet"])
def("speed", 1, "m/s", ["m/s", "mps"])
def("speed", 1 / 3.6, "km/h", ["km/h", "kmh", "kph", "kmph"])
def("speed", 0.44704, "mph", ["mph"])
def("speed", 0.514444, "kn", ["kn", "knot", "knots"])
def("data", 1, "B", ["b", "byte", "bytes"])
def("data", 1e3, "KB", ["kb", "kilobyte", "kilobytes"])
def("data", 1e6, "MB", ["mb", "megabyte", "megabytes"])
def("data", 1e9, "GB", ["gb", "gigabyte", "gigabytes"])
def("data", 1e12, "TB", ["tb", "terabyte", "terabytes"])
def("data", 1024, "KiB", ["kib"])
def("data", 1048576, "MiB", ["mib"])
def("data", 1073741824, "GiB", ["gib"])
def("data", 1099511627776, "TiB", ["tib"])
def("time", 0.001, "ms", ["ms", "millisecond", "milliseconds"])
def("time", 1, "s", ["s", "sec", "secs", "second", "seconds"])
def("time", 60, "min", ["min", "mins", "minute", "minutes"])
def("time", 3600, "h", ["h", "hr", "hrs", "hour", "hours"])
def("time", 86400, "days", ["day", "days"])
def("time", 604800, "weeks", ["week", "weeks"])
def("time", 31557600, "years", ["year", "years", "yr", "yrs"])
def("energy", 1, "J", ["j", "joule", "joules"])
def("energy", 1000, "kJ", ["kj"])
def("energy", 4184, "kcal", ["kcal", "calorie", "calories", "cal"])
def("energy", 3600000, "kWh", ["kwh"])
def("power", 1, "W", ["w", "watt", "watts"])
def("power", 1000, "kW", ["kw", "kilowatt", "kilowatts"])
def("power", 745.699872, "hp", ["hp", "horsepower"])
const TEMPS = {
    "c": "C", "°c": "C", "celsius": "C", "f": "F", "°f": "F", "fahrenheit": "F", "k": "K", "kelvin": "K"
}
function toKelvin(v, u) { return u === "C" ? v + 273.15 : u === "F" ? (v - 32) * 5 / 9 + 273.15 : v }
function fromKelvin(k, u) { return u === "C" ? k - 273.15 : u === "F" ? (k - 273.15) * 9 / 5 + 32 : k }

function parseUnits(input) {
    const s = input.trim().toLowerCase().replace(/\s+/g, " ")
    const m = s.match(/^(-?\d[\d\s,.]*)\s?(°?[a-z²"'/ ]+?)\s+(?:to|in|into|as|->|=)\s+(°?[a-z²"'/ ]+?)$/)
    if (!m) return null
    const neg = m[1].trim()[0] === "-"
    const value = (neg ? -1 : 1) * parseAmount(m[1].replace("-", ""))
    if (!isFinite(value)) return null
    const a = m[2].trim(), b = m[3].trim()
    if (TEMPS[a] && TEMPS[b]) {
        const r = fromKelvin(toKelvin(value, TEMPS[a]), TEMPS[b])
        const unit = TEMPS[b] === "K" ? " K" : "°" + TEMPS[b]
        return { kind: "unit", text: fmtNum(r, 2) + unit, sub: fmtNum(value, 4) + (TEMPS[a] === "K" ? " K" : "°" + TEMPS[a]), value: r, copy: String(Math.round(r * 100) / 100) }
    }
    const ua = UNITS[a], ub = UNITS[b]
    if (!ua || !ub) return null
    if (ua.dim !== ub.dim) return { kind: "unit", error: "Can't convert " + ua.dim + " to " + ub.dim }
    const r = value * ua.f / ub.f
    const PLURALS = { cups: "cup", days: "day", weeks: "week", years: "year", acres: "acre" }
    const nm = (n, v) => v === 1 && PLURALS[n] ? PLURALS[n] : n
    const dec = Math.abs(r) >= 100 ? 2 : Math.abs(r) >= 1 ? 4 : 6
    return { kind: "unit", text: fmtNum(r, dec) + " " + nm(ub.name, r), sub: fmtNum(value, 6) + " " + nm(ua.name, value) + " = " + fmtNum(r, 8) + " " + nm(ub.name, r), value: r, copy: String(Math.round(r * 1e8) / 1e8) }
}

// Entry point. `rates`: { CODE: per-EUR rate } or null while loading.
function smart(input, rates, now) {
    if (!input || !/\d|until|till|since|when is|what day/i.test(input)) return null
    return parseDateQuery(input, now || new Date()) || parseCurrency(input, rates) || parseUnits(input)
}

// True when the input looks like it needs currency rates.
function wantsRates(input) {
    return /[$€£¥]|\b(usd|eur|huf|ft|gbp|chf|jpy|czk|pln|ron|dollars?|euros?|forints?|[a-z]{3})\b/i.test(input)
}
