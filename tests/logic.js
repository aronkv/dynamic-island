// Checks for the date logic in CalcSmart.js and CalendarParse.js.
// Run: node tests/logic.js   (from the quickshell folder)
const fs = require("fs"), vm = require("vm"), assert = require("assert"), path = require("path")
function load(f) {
    const ctx = {}
    vm.createContext(ctx)
    vm.runInContext(fs.readFileSync(path.join(__dirname, "..", f), "utf8").replace(/^\.pragma library.*$/m, ""), ctx)
    return ctx
}
const C = load("CalcSmart.js"), P = load("CalendarParse.js")
const sun2pm = new Date(2026, 9, 18, 14, 0), sun8am = new Date(2026, 9, 18, 8, 0), sun9pm = new Date(2026, 9, 18, 21, 0)
const t = (q, now) => { const r = P.parse(q, now, now); return r.date + " " + r.time }
assert.equal(t("call at 7", sun2pm), "2026-10-18 19:00")      // morning over → tonight
assert.equal(t("call at 9", sun8am), "2026-10-18 09:00")      // still ahead → this morning
assert.equal(t("call at 7", sun9pm), "2026-10-19 07:00")      // both over → tomorrow morning
assert.equal(t("call at 1", sun2pm), "2026-10-19 13:00")      // tomorrow, 1 → afternoon
assert.equal(t("dentist fri at 3", sun2pm), "2026-10-23 15:00")
assert.equal(t("gym fri at 9", sun2pm), "2026-10-23 09:00")
assert.equal(t("meet at 19", sun2pm), "2026-10-18 19:00")
assert.equal(t("meet 7pm", sun2pm), "2026-10-18 19:00")
assert.equal(t("meet at 7:30", sun2pm), "2026-10-19 07:30")   // explicit minutes keep 24 h meaning
const s = q => { const r = C.smart(q, null, sun2pm); return r ? r.text + " | " + r.sub : null }
assert.equal(s("christmas"), "Fri, 25 Dec 2026 | in 68 days")
assert.equal(s("Friday"), "Fri, 23 Oct 2026 | in 5 days")
assert.equal(s("sunday"), "Sun, 25 Oct 2026 | in 7 days")
assert.equal(s("days until friday"), "5 days | until Fri, 23 Oct 2026")
assert.equal(s("days since monday"), "6 days | since Mon, 12 Oct 2026")
assert.equal(s("halloween").split(" | ")[0], "Sat, 31 Oct 2026")
assert.equal(s("fall"), null)
assert.equal(s("firefox"), null)
assert.equal(s("easter 2027"), "Sun, 28 Mar 2027 | in 161 days")
// Weekday counts, against a brute-force count.
const count = (from, to, wd) => { let n = 0; for (let d = new Date(from); d <= to; d.setDate(d.getDate() + 1)) if (d.getDay() === wd) n++; return n }
assert.equal(s("how many fridays until jun 15"), count(new Date(2026, 9, 19), new Date(2027, 5, 15), 5) + " Fridays | until Tue, 15 Jun 2027")
assert.equal(s("how many sundays til dec 25"), count(new Date(2026, 9, 19), new Date(2026, 11, 25), 0) + " Sundays | until Fri, 25 Dec 2026")
assert.equal(s("fridays until friday"), "1 Friday | until Fri, 23 Oct 2026")
assert.equal(s("mondays since sep 1"), count(new Date(2026, 8, 1), new Date(2026, 9, 17), 1) + " Mondays | since Tue, 1 Sep 2026")
assert.equal(s("saturdays til christmas"), "9 Saturdays | until Fri, 25 Dec 2026")
assert.equal(s("days til christmas"), "68 days | until Fri, 25 Dec 2026  ·  9 weeks 5 days")
console.log("all ok")
