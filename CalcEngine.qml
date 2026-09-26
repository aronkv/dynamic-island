import QtQuick
import "CalcSmart.js" as Smart

// Safe expression evaluator shared by CalculatorPanel and LauncherPanel.
// Hand-written recursive-descent parser — never eval()/Function(): it only
// knows numbers, + - * / ^ %, parentheses, a fixed whitelist of function
// names and the constants pi / e / ans.
QtObject {
    id: engine
    property real ans: 0

    readonly property var functions: ({
        sqrt: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
        sin: x => Math.sin(x * Math.PI / 180), cos: x => Math.cos(x * Math.PI / 180),
        tan: x => Math.tan(x * Math.PI / 180),
        asin: x => Math.asin(x) * 180 / Math.PI, acos: x => Math.acos(x) * 180 / Math.PI,
        atan: x => Math.atan(x) * 180 / Math.PI,
        log: Math.log10, ln: Math.log
    })

    function tokenize(input, withX) {
        const tokens = []
        let i = 0
        while (i < input.length) {
            const c = input[i]
            if (c === " " || c === "\t") { i++; continue }
            if ("+-*/%()^".indexOf(c) !== -1) { tokens.push(c); i++; continue }
            // "x" between numbers means × — except in equations, where x is
            // the unknown.
            if (c === "×" || !withX && c === "x" && /[0-9) ]/.test(input[i - 1] || "") && /[0-9( ]/.test(input[i + 1] || "")) { tokens.push("*"); i++; continue }
            if (c === "÷" || c === ":") { tokens.push("/"); i++; continue }
            if (c === "−") { tokens.push("-"); i++; continue }
            if (c === ",") { tokens.push({ num: NaN, comma: true }); i++; continue }
            if (/[0-9.]/.test(c)) {
                let j = i
                let sawDot = false
                while (j < input.length && /[0-9.]/.test(input[j])) {
                    if (input[j] === ".") {
                        if (sawDot) throw new Error("Invalid number")
                        sawDot = true
                    }
                    j++
                }
                const numStr = input.slice(i, j)
                if (numStr === ".") throw new Error("Invalid number")
                tokens.push({ num: parseFloat(numStr) })
                i = j
                continue
            }
            if (/[a-zA-Z]/.test(c)) {
                let j = i
                while (j < input.length && /[a-zA-Z]/.test(input[j])) j++
                tokens.push({ name: input.slice(i, j).toLowerCase() })
                i = j
                continue
            }
            throw new Error("Unexpected character: " + c)
        }
        return tokens
    }

    function incomplete(message) {
        const e = new Error(message)
        e.incomplete = true
        throw e
    }

    //   expr    := term (('+'|'-') term)*
    //   term    := unary (('*'|'/'|'%') unary)*
    //   unary   := ('+'|'-') unary | power
    //   power   := postfix ('^' unary)?          (right-associative)
    //   postfix := atom ('%')*                   (percent, when no operand follows)
    //   atom    := NUMBER | NAME | NAME '(' expr ')' | '(' expr ')'
    function evaluate(input, xValue) {
        const withX = xValue !== undefined
        const tokens = engine._implicitMul(tokenize(input, withX))
        let pos = 0

        function peek(o) { const k = pos + (o || 0); return k < tokens.length ? tokens[k] : null }
        function next() { return tokens[pos++] }
        function startsOperand(t) {
            return t !== null && (t === "(" || t === "-" || t === "+" || (typeof t === "object" && ("num" in t || "name" in t)))
        }

        function parseAtom() {
            const t = peek()
            if (t === null) engine.incomplete("Unexpected end")
            if (typeof t === "object" && "num" in t && !t.comma) { next(); return t.num }
            if (typeof t === "object" && "name" in t) {
                next()
                if (t.name === "pi") return Math.PI
                if (t.name === "e") return Math.E
                if (t.name === "ans") return engine.ans
                if (withX && t.name === "x") return xValue
                const fn = engine.functions[t.name]
                if (!fn) {
                    // A partially typed function name is "incomplete", not an error.
                    if (Object.keys(engine.functions).some(k => k.startsWith(t.name)) || "ans".startsWith(t.name))
                        engine.incomplete("Partial name")
                    throw new Error("Unknown name: " + t.name)
                }
                if (peek() === null) engine.incomplete("Missing (")
                if (next() !== "(") throw new Error("Expected (")
                const v = parseExpr()
                if (peek() === null) engine.incomplete("Missing )")
                if (next() !== ")") throw new Error("Expected )")
                return fn(v)
            }
            if (t === "(") {
                next()
                const v = parseExpr()
                if (peek() === null) engine.incomplete("Missing )")
                if (next() !== ")") throw new Error("Expected )")
                return v
            }
            throw new Error("Unexpected token")
        }

        function parsePostfix() {
            let v = parseAtom()
            while (peek() === "%" && !startsOperand(peek(1))) { next(); v = v / 100 }
            return v
        }

        function parsePower() {
            const base = parsePostfix()
            if (peek() === "^") { next(); return Math.pow(base, parseUnary()) }
            return base
        }

        function parseUnary() {
            const t = peek()
            if (t === "-") { next(); return -parseUnary() }
            if (t === "+") { next(); return parseUnary() }
            return parsePower()
        }

        function parseTerm() {
            let v = parseUnary()
            while (peek() === "*" || peek() === "/" || peek() === "%") {
                const op = next()
                const rhs = parseUnary()
                if (op === "*") v = v * rhs
                else if (rhs === 0) throw new Error("Division by zero")
                else v = op === "/" ? v / rhs : v % rhs
            }
            return v
        }

        function parseExpr() {
            let v = parseTerm()
            while (peek() === "+" || peek() === "-") {
                const op = next()
                const rhs = parseTerm()
                v = op === "+" ? v + rhs : v - rhs
            }
            return v
        }

        if (tokens.length === 0) throw new Error("Empty")
        const result = parseExpr()
        if (pos !== tokens.length) throw new Error("Unexpected trailing input")
        if (!isFinite(result)) throw new Error("Not a finite number")
        return result
    }

    // Implicit multiplication: "2x", "3(x-1)", "(a)(b)", "2pi", "x(x+1)".
    // Inserted between a value-ending token (number, ")", or a non-function
    // name) and a value-starting one (number, "(", name) — never between a
    // function name and its "(".
    function _implicitMul(tokens) {
        const out = []
        const isFn = t => typeof t === "object" && "name" in t && engine.functions[t.name] !== undefined
        const endsValue = t => t === ")" || (typeof t === "object" && (("num" in t && !t.comma) || ("name" in t && !isFn(t))))
        const startsValue = t => t === "(" || (typeof t === "object" && (("num" in t && !t.comma) || "name" in t))
        for (let i = 0; i < tokens.length; i++) {
            if (i > 0 && endsValue(tokens[i - 1]) && startsValue(tokens[i])
                    && !(typeof tokens[i - 1] === "object" && "num" in tokens[i - 1] && typeof tokens[i] === "object" && "num" in tokens[i]))
                out.push("*")
            out.push(tokens[i])
        }
        return out
    }

    // Roots of f on [lo, hi]: sign changes refined by bisection, plus exact
    // zero hits; poles (sign flips through infinity, e.g. 1/x) rejected.
    function _findRoots(f, lo, hi, steps) {
        const roots = []
        const dx = (hi - lo) / steps
        let px = lo, pv = NaN
        try { pv = f(px) } catch (e) {}
        if (isFinite(pv) && Math.abs(pv) < 1e-12) roots.push(px)
        for (let k = 1; k <= steps && roots.length < 8; k++) {
            const x = lo + k * dx
            let v = NaN
            try { v = f(x) } catch (e) {}
            if (isFinite(v) && Math.abs(v) < 1e-12) roots.push(x)
            else if (isFinite(pv) && isFinite(v) && pv * v < 0) {
                let l = px, r = x, fl = pv
                for (let it = 0; it < 80; it++) {
                    const m = (l + r) / 2
                    let fm = NaN
                    try { fm = f(m) } catch (e) { break }
                    if (fl * fm <= 0) r = m
                    else { l = m; fl = fm }
                }
                const root = (l + r) / 2
                let fr = NaN
                try { fr = f(root) } catch (e) {}
                if (isFinite(fr) && Math.abs(fr) < 1e-6) roots.push(root)
            }
            px = x
            pv = v
        }
        return roots.map(r => Math.round(r * 1e9) / 1e9)
            .filter((r, i, arr) => arr.findIndex(q => Math.abs(q - r) < 1e-7) === i)
    }

    function _isTrig(input) { return /\b(sin|cos|tan)\s*\(/i.test(input) }

    // Equations / inequalities in x. Returns
    //   { kind: "equation"|"inequality", text, roots, f, range: [lo, hi],
    //     intervals: [[a, b], …] (inequality solution set, ±Infinity ends) }
    // Linear equations are solved exactly; everything else numerically on
    // [-1000, 1000] (trig: 0°–360°, degrees). Quadratic, cubic, quartic…
    // all go through the same scan. Throws (incomplete) while half-typed.
    function analyze(input) {
        const m = input.match(/<=|>=|≤|≥|<|>|=/g)
        if (!m || m.length !== 1) throw new Error("Use exactly one =, <, >, ≤ or ≥")
        const op = m[0] === "≤" ? "<=" : m[0] === "≥" ? ">=" : m[0]
        const sides = input.split(/<=|>=|≤|≥|<|>|=/)
        if (sides[0].trim() === "" || sides[1].trim() === "") engine.incomplete("Missing side")
        if (!/x/i.test(input)) throw new Error("No x to solve for")
        const f = x => engine.evaluate(sides[0], x) - engine.evaluate(sides[1], x)

        const trig = _isTrig(input)
        let f0 = NaN, f1 = NaN, f2 = NaN
        try { f0 = f(0); f1 = f(1); f2 = f(2) } catch (e) {
            if (e.incomplete || !/Division by zero|finite/.test(e.message)) throw e
        }

        const a = f1 - f0
        const linear = !trig && isFinite(f0) && isFinite(f1) && isFinite(f2)
            && Math.abs((f2 - f1) - a) < 1e-9 * Math.max(1, Math.abs(a))
        let roots
        const lo = trig ? 0 : -1000, hi = trig ? 360 : 1000
        if (linear) roots = Math.abs(a) < 1e-12 ? [] : [Math.round(-f0 / a * 1e9) / 1e9]
        else roots = _findRoots(f, lo, hi, trig ? 7200 : 20000)
        if (trig) roots = roots.filter(r => r < 360 - 1e-9)

        // Plot range: around the roots, or a default window.
        let range
        if (trig) range = [0, 360]
        else if (roots.length > 0) {
            const mn = Math.min(...roots), mx = Math.max(...roots)
            const pad = Math.max(2, (mx - mn) * 0.35)
            range = [mn - pad, mx + pad]
        } else range = [-10, 10]

        const suffix = trig ? "  (0°–360°)" : ""
        if (op === "=") {
            if (linear && Math.abs(a) < 1e-12)
                return { kind: "equation", text: Math.abs(f0) < 1e-12 ? "Any x (identity)" : "No solution", roots: [], f: f, range: range, intervals: [] }
            if (roots.length === 0) return { kind: "equation", text: "No real solution" + suffix, roots: [], f: f, range: range, intervals: [] }
            return { kind: "equation", text: roots.map(r => "x = " + engine.format(r)).join("   ") + suffix, roots: roots, f: f, range: range, intervals: [] }
        }

        // Inequality: test each gap between roots.
        const holds = x => {
            let v = NaN
            try { v = f(x) } catch (e) { return false }
            if (!isFinite(v)) return false
            return op === "<" ? v < 0 : op === ">" ? v > 0 : op === "<=" ? v <= 1e-12 : v >= -1e-12
        }
        const inclusive = op === "<=" || op === ">="
        const edges = [trig ? 0 : -Infinity].concat(roots, [trig ? 360 : Infinity])
        const intervals = []
        for (let i = 0; i + 1 < edges.length; i++) {
            const l = edges[i], r = edges[i + 1]
            const mid = !isFinite(l) && !isFinite(r) ? 0 : !isFinite(l) ? r - 1 : !isFinite(r) ? l + 1 : (l + r) / 2
            if (holds(mid)) {
                const last = intervals[intervals.length - 1]
                if (last && last[1] === l && inclusive) last[1] = r   // merge across an included root
                else intervals.push([l, r])
            }
        }
        const lt = inclusive ? " ≤ " : " < "
        const fmt = v => engine.format(v)
        let text
        if (intervals.length === 0) {
            text = inclusive && roots.length > 0 ? roots.map(r => "x = " + fmt(r)).join("  or  ") : "No solution"
        } else {
            text = intervals.map(([l, r]) => {
                const lInf = !isFinite(l) || (trig && l === 0), rInf = !isFinite(r) || (trig && r === 360)
                if (!isFinite(l) && !isFinite(r)) return "All real x"
                if (lInf && !trig) return "x" + lt + fmt(r)
                if (rInf && !trig) return "x" + (inclusive ? " ≥ " : " > ") + fmt(l)
                return fmt(l) + lt + "x" + lt + fmt(r)
            }).join("  or  ")
        }
        return { kind: "inequality", text: text + suffix, roots: roots, f: f, range: range, intervals: intervals }
    }

    // Backwards-compatible wrapper (equations only).
    function solve(input) { return analyze(input) }

    // Date / currency / unit queries (see CalcSmart.js). Returns null for
    // anything else, { pending: true } while exchange rates load, or
    // { text, sub, value, copy } / { error }. Reading `rates` here makes
    // bindings that call smart() re-evaluate once rates arrive.
    readonly property var rates: CurrencyRates.rates
    function smart(input) {
        const r = Smart.smart(input, engine.rates, new Date())
        if (r && (r.pending || r.kind === "currency")) CurrencyRates.ensure()
        if (r && r.pending && CurrencyRates.failed) return { error: "Couldn't load exchange rates" }
        return r
    }

    // Grouped thousands, trimmed floating-point noise.
    function format(v) {
        const r = Math.round(v * 1e10) / 1e10
        if (Math.abs(r) >= 1e15 || (r !== 0 && Math.abs(r) < 1e-6)) return r.toExponential(6).replace(/\.?0+e/, "e")
        const parts = String(r).split(".")
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
        return parts.join(".")
    }

}
