// Terminal palette generator for the theme presets and the Dynamic theme
// (imported by ThemeProfiles.qml; pure JS so it can be tested with node).
function hexToRgb(h) { h = h.replace("#", ""); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16) / 255) }
function rgbToHex(r, g, b) { return "#" + [r, g, b].map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("") }
function rgbToHsl(r, g, b) {
    const max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2
    if (max === min) return [0, 0, l]
    const d = max - min, s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    let h = max === r ? (g - b) / d + (g < b ? 6 : 0) : max === g ? (b - r) / d + 2 : (r - g) / d + 4
    return [h * 60, s, l]
}
function hslToRgb(h, s, l) {
    h = ((h % 360) + 360) % 360 / 360
    if (s === 0) return [l, l, l]
    const q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
    const f = t => { t = (t + 1) % 1; return t < 1 / 6 ? p + (q - p) * 6 * t : t < 1 / 2 ? q : t < 2 / 3 ? p + (q - p) * (2 / 3 - t) * 6 : p }
    return [f(h + 1 / 3), f(h), f(h - 1 / 3)]
}
function lum(hex) { const c = hexToRgb(hex).map(v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)); return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2] }
function contrast(a, b) { const la = lum(a), lb = lum(b); return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05) }
function hueDist(a, b) { const d = Math.abs(a - b) % 360; return d > 180 ? 360 - d : d }
function pullHue(h, target, amt) { let d = ((target - h + 540) % 360) - 180; return h + d * amt }

// Monochrome 16-color palette from one accent (same structure as the
// hand-made T480 scheme: accent shades in the red/green/magenta… slots,
// greys elsewhere). Fixes over the old presets: bright 8–15 are real,
// visibly lighter pairs (they used to be copies of 0–7), bright black is a
// readable grey (fish/zsh autosuggestions, comments), and every colored
// slot keeps ≥ 3.5:1 contrast on the background.
function mixHex(a, b, t) { const A = hexToRgb(a), B = hexToRgb(b); return rgbToHex(...A.map((v, i) => v + (B[i] - v) * t)) }
function paletteFromAccent(accent, bg) {
    bg = bg || "#0a0a0a"
    const [ah, as, al] = rgbToHsl(...hexToRgb(accent))
    const s = Math.max(0.55, Math.min(0.85, as))
    const readable = (hex, min) => {
        let [h, ss, l] = rgbToHsl(...hexToRgb(hex))
        while (contrast(hex, bg) < min && l < 0.9) { l += 0.02; hex = rgbToHex(...hslToRgb(h, ss, l)) }
        return hex
    }
    const shade = l => rgbToHex(...hslToRgb(ah, s, l))
    const mid = readable(shade(0.52), 4.5)      // main accent (red slot)
    const deep = readable(shade(0.36), 3.5)     // darker accent (green slot)
    const light = readable(shade(0.66), 6)      // light accent (cyan slot)
    const tint = readable(mixHex(shade(0.6), "#a0a0a0", 0.55), 4.5) // accent-tinted grey (magenta slot)
    const normal = ["#1f1f1f", mid, deep, "#707070", "#8c8c8c", tint, light, "#c8c8c8"]
    const brighter = (hex, amt) => { const [h, ss, l] = rgbToHsl(...hexToRgb(hex)); return rgbToHex(...hslToRgb(h, Math.min(1, ss + 0.05), Math.min(0.92, l + amt))) }
    // Bright accents on fixed lightness steps above their normal partner,
    // so no two brights collapse into the same color.
    const lOf = hex => rgbToHsl(...hexToRgb(hex))[2]
    const bMid = shade(Math.min(0.8, lOf(mid) + 0.14))
    const bDeep = shade(Math.min(lOf(bMid) - 0.08, lOf(deep) + 0.12))
    const bLight = shade(Math.min(0.88, Math.max(lOf(light), lOf(bMid)) + 0.1))
    const bright = ["#6b6b6b", bMid, bDeep, "#9a9a9a", "#b0b0b0",
                    brighter(tint, 0.12), bLight, "#ffffff"]
    // Final pass: nudge any exact duplicate a little lighter so all 16
    // slots stay distinguishable.
    const colors = normal.concat(bright)
    for (let i = 0; i < colors.length; i++) {
        let guard = 0
        while (colors.indexOf(colors[i]) < i && guard++ < 10) {
            const [h, ss, l] = rgbToHsl(...hexToRgb(colors[i]))
            colors[i] = rgbToHex(...hslToRgb(h, ss, Math.min(0.95, l + 0.04)))
        }
    }
    return { background: bg, foreground: "#c8c8c8", cursor: light, colors: colors }
}
if (typeof module !== "undefined") module.exports = { paletteFromAccent, contrast, lum }
