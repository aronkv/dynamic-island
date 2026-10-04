import QtQuick

// Dominant vivid color of an album cover. The image is drawn tiny (16×16)
// into a Canvas and read back; each pixel is weighted by saturation ×
// brightness so the result is the cover's "accent", not a muddy average.
// The color is then lifted to a minimum brightness so it reads on black.
// The Canvas must stay rendered to paint (a Canvas that isn't visible never
// gets onPaint), so it sits at 1% opacity, 16px, out of the way.
// A cover that is already in the Canvas image cache never re-fires
// imageLoaded (going back a track), so sourceChanged paints directly in that
// case, and every computed color is cached per URL so repeats are instant.
Canvas {
    id: root
    property url source: ""
    property color fallback: "#ffffff"
    readonly property color color: _color
    property color _color: fallback
    property var _cache: ({})

    width: 16
    height: 16
    opacity: 0.01
    renderStrategy: Canvas.Immediate

    onSourceChanged: {
        const src = source.toString()
        if (src === "") { _color = fallback; return }
        if (_cache[src] !== undefined) { _color = _cache[src]; return }
        if (isImageLoaded(source)) requestPaint()
        else loadImage(source)
    }
    onImageLoaded: requestPaint()
    // Canvas may not be ready yet when the first source arrives.
    onAvailableChanged: if (available && source.toString() !== "") {
        if (isImageLoaded(source)) requestPaint(); else loadImage(source)
    }

    onPaint: {
        const src = source.toString()
        if (src === "" || !isImageLoaded(source)) return
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.drawImage(source, 0, 0, width, height)
        const data = ctx.getImageData(0, 0, width, height).data
        let r = 0, g = 0, b = 0, wsum = 0
        let ar = 0, ag = 0, ab = 0
        const n = data.length / 4
        for (let i = 0; i < data.length; i += 4) {
            const R = data[i] / 255, G = data[i + 1] / 255, B = data[i + 2] / 255
            ar += R; ag += G; ab += B
            const max = Math.max(R, G, B), min = Math.min(R, G, B)
            const sat = max === 0 ? 0 : (max - min) / max
            const w = Math.pow(sat, 2) * max + 0.001
            r += R * w; g += G * w; b += B * w; wsum += w
        }
        let cr = r / wsum, cg = g / wsum, cb = b / wsum
        // Near-greyscale cover: use the plain average instead.
        if (wsum < n * 0.02) { cr = ar / n; cg = ag / n; cb = ab / n }
        // Lift dark colors so they stay visible on black.
        const lum = 0.2126 * cr + 0.7152 * cg + 0.0722 * cb
        const target = 0.5
        if (lum < target) {
            const k = target / Math.max(0.04, lum)
            cr = Math.min(1, cr * k); cg = Math.min(1, cg * k); cb = Math.min(1, cb * k)
        }
        const c = Qt.rgba(cr, cg, cb, 1)
        _cache[src] = c
        _color = c
    }
}
