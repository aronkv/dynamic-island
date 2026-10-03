import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes

// iOS Weather style: hero temperature, 24 h strip with a temperature curve,
// 7-day list with range bars, and a grid of detail tiles (feels like,
// humidity, wind with direction, UV, sunrise/sunset arc, pressure).
ColumnLayout {
    id: panel
    property var monitor: null
    signal settingsRequested()
    signal closeRequested()
    spacing: 12

    readonly property bool ready: monitor !== null && monitor.weatherReady && monitor.current !== null
    readonly property var cur: ready ? monitor.current : ({})
    readonly property var today: ready && monitor.daily.length > 0 ? monitor.daily[0] : null

    function iconFor(code, isDay) { return monitor ? monitor._iconFor(code, isDay) : "" }
    function dayName(dateStr, i) {
        if (i === 0) return "Today"
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][new Date(dateStr + "T12:00").getDay()]
    }
    function hhmm(isoStr) { return isoStr ? isoStr.slice(11, 16) : "" }
    function compass(deg) {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(((deg % 360) + 360) % 360 / 45) % 8]
    }
    function uvLabel(uv) {
        if (uv < 3) return "Low"
        if (uv < 6) return "Moderate"
        if (uv < 8) return "High"
        if (uv < 11) return "Very High"
        return "Extreme"
    }

    component WeatherIcon: Item {
        id: wi
        property string icon: ""
        property color tint: "#ffffff"
        implicitWidth: 20
        implicitHeight: 20

        IconImage {
            id: iconImg
            anchors.fill: parent
            source: wi.icon ? "image://icon/" + wi.icon : ""
            visible: false
            layer.enabled: true
            smooth: true
            mipmap: true
        }
        Rectangle {
            id: flatFill
            anchors.fill: parent
            color: wi.tint
            visible: false
        }
        MultiEffect {
            anchors.fill: iconImg
            source: flatFill
            maskEnabled: true
            maskSource: iconImg
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.0
            maskThresholdMax: 1.0
            maskSpreadAtMax: 0.0
        }
    }

    component SectionLabel: Text {
        color: "#ffffff"
        opacity: 0.45
        font.pixelSize: 10
        font.weight: 600
        font.letterSpacing: 0.6
        font.family: Theme.fontText
    }

    component Tile: Rectangle {
        id: tile
        property string label: ""
        property string value: ""
        property string detail: ""
        default property alias extra: extraSlot.data
        Layout.fillWidth: true
        implicitHeight: 74
        radius: Theme.radiusMedium
        color: Qt.rgba(1, 1, 1, 0.06)

        Column {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 3

            SectionLabel { text: tile.label }
            Text {
                text: tile.value
                color: "#ffffff"
                font.pixelSize: 18
                font.weight: 600
                font.family: Theme.font
            }
            Text {
                text: tile.detail
                visible: text !== ""
                color: "#ffffff"
                opacity: 0.55
                font.pixelSize: 10
                font.family: Theme.fontText
            }
        }

        Item {
            id: extraSlot
            anchors.fill: parent
        }
    }

    PanelHeader {
        Layout.fillWidth: true
        icon: panel.monitor && panel.ready ? panel.monitor.iconName : "weather-few-clouds-symbolic"
        title: "Weather"
        subtitle: "Open-Meteo forecast"
        onSettingsRequested: panel.settingsRequested()
        onCloseRequested: panel.closeRequested()
    }

    Text {
        Layout.fillWidth: true
        visible: !panel.ready
        text: panel.monitor && !panel.monitor.locationReady ? "Detecting location…" : "Fetching weather…"
        color: "#ffffff"
        opacity: 0.4
        font.pixelSize: 12
        font.family: Theme.fontText
    }

    Flickable {
        id: scroller
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: panel.ready
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        // Soft top/bottom fade instead of a hard clip edge.
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: scrollFadeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ColumnLayout {
            id: body
            width: scroller.width
            spacing: 14

            // ── Hero (iOS style: big place name, huge temperature) ──
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: body.width
                spacing: 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: panel.monitor && panel.monitor.city ? panel.monitor.city : "—"
                    color: "#ffffff"
                    font.pixelSize: 26
                    font.weight: 600
                    font.family: Theme.font
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: (panel.monitor && panel.monitor.locationSource === "manual" ? "Set location"
                              : panel.monitor && panel.monitor.locationSource === "wifi" ? "Wi-Fi location" : "Approximate location (IP)")
                        + (panel.monitor && panel.monitor.lastUpdated.getTime() > 0
                           ? " · updated " + Qt.formatTime(panel.monitor.lastUpdated, "HH:mm") : "")
                    color: "#ffffff"
                    opacity: 0.4
                    font.pixelSize: 10
                    font.family: Theme.fontText
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    spacing: 10

                    WeatherIcon {
                        implicitWidth: 34
                        implicitHeight: 34
                        icon: panel.monitor ? panel.monitor.iconName : ""
                    }
                    Text {
                        text: panel.ready ? Math.round(panel.cur.temperature_2m) + "°" : ""
                        color: "#ffffff"
                        font.pixelSize: 52
                        font.weight: 200
                        font.family: Theme.font
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: (panel.monitor ? panel.monitor.conditionText : "")
                        + (panel.today ? "   H:" + Math.round(panel.today.max) + "°  L:" + Math.round(panel.today.min) + "°" : "")
                    color: "#ffffff"
                    opacity: 0.75
                    font.pixelSize: 13
                    font.weight: 500
                    font.family: Theme.fontText
                }
            }

            // ── Hourly strip + temperature curve ──────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 118
                radius: Theme.radiusMedium
                color: Qt.rgba(1, 1, 1, 0.06)

                SectionLabel {
                    x: 10
                    y: 8
                    text: "NEXT 24 HOURS"
                }

                Flickable {
                    id: hourFlick
                    anchors.fill: parent
                    anchors.topMargin: 24
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    clip: true
                    contentWidth: hourRow.width
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds

                    readonly property int cellW: 44
                    readonly property var hours: panel.ready ? panel.monitor.hourly : []
                    readonly property real tMin: hours.length ? Math.min.apply(null, hours.map(h => h.temp)) : 0
                    readonly property real tMax: hours.length ? Math.max.apply(null, hours.map(h => h.temp)) : 1

                    // Smooth temperature curve behind the hour cells (a Shape
                    // with a generated SVG path — a Canvas here never got its
                    // onPaint while inside the hidden panel).
                    Shape {
                        width: hourRow.width
                        height: hourFlick.height
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            strokeWidth: 2
                            strokeColor: Qt.rgba(1, 0.84, 0.04, 0.8)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            PathSvg {
                                path: {
                                    const hs = hourFlick.hours
                                    if (hs.length < 2) return ""
                                    const span = Math.max(1, hourFlick.tMax - hourFlick.tMin)
                                    const pts = hs.map((h, i) => [i * hourFlick.cellW + hourFlick.cellW / 2,
                                                                  56 - (h.temp - hourFlick.tMin) / span * 18])
                                    let d = "M " + pts[0][0] + " " + pts[0][1]
                                    for (let i = 1; i < pts.length; i++) {
                                        const mx = (pts[i - 1][0] + pts[i][0]) / 2
                                        d += " C " + mx + " " + pts[i - 1][1] + " " + mx + " " + pts[i][1] + " " + pts[i][0] + " " + pts[i][1]
                                    }
                                    return d
                                }
                            }
                        }
                    }

                    Row {
                        id: hourRow
                        Repeater {
                            model: hourFlick.hours

                            Item {
                                required property var modelData
                                required property int index
                                width: hourFlick.cellW
                                height: hourFlick.height

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 0
                                    text: index === 0 ? "Now" : modelData.time.slice(11, 13)
                                    color: "#ffffff"
                                    opacity: index === 0 ? 1 : 0.7
                                    font.pixelSize: 11
                                    font.weight: index === 0 ? 700 : 500
                                    font.family: Theme.fontText
                                }
                                WeatherIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 18
                                    implicitWidth: 16
                                    implicitHeight: 16
                                    icon: panel.iconFor(modelData.code, modelData.isDay)
                                }
                                // Dot on the curve.
                                Rectangle {
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: "#ffffff"
                                    x: parent.width / 2 - 2.5
                                    y: 56 - (modelData.temp - hourFlick.tMin) / Math.max(1, hourFlick.tMax - hourFlick.tMin) * 18 - 2.5
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 64
                                    text: Math.round(modelData.temp) + "°"
                                    color: "#ffffff"
                                    font.pixelSize: 12
                                    font.weight: 600
                                    font.family: Theme.fontText
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 79
                                    visible: modelData.precip >= 20
                                    text: modelData.precip + "%"
                                    color: "#64d2ff"
                                    font.pixelSize: 9
                                    font.weight: 600
                                    font.family: Theme.fontText
                                }
                            }
                        }
                    }
                }
            }

            // ── 7-day forecast with range bars ────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: dayCol.implicitHeight + 32
                radius: Theme.radiusMedium
                color: Qt.rgba(1, 1, 1, 0.06)

                readonly property var days: panel.ready ? panel.monitor.daily : []
                readonly property real weekMin: days.length ? Math.min.apply(null, days.map(d => d.min)) : 0
                readonly property real weekMax: days.length ? Math.max.apply(null, days.map(d => d.max)) : 1

                SectionLabel {
                    x: 10
                    y: 8
                    text: "7-DAY FORECAST"
                }

                Column {
                    id: dayCol
                    x: 10
                    y: 26
                    width: parent.width - 20
                    spacing: 0

                    Repeater {
                        model: parent.parent.days

                        Item {
                            id: dayRow
                            required property var modelData
                            required property int index
                            readonly property var week: dayCol.parent
                            width: dayCol.width
                            height: 28

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 52
                                text: panel.dayName(modelData.date, index)
                                color: "#ffffff"
                                font.pixelSize: 13
                                font.weight: 600
                                font.family: Theme.fontText
                            }
                            WeatherIcon {
                                x: 56
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: 16
                                implicitHeight: 16
                                icon: panel.iconFor(modelData.code, true)
                            }
                            Text {
                                x: 78
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.precipMax >= 20
                                text: modelData.precipMax + "%"
                                color: "#64d2ff"
                                font.pixelSize: 10
                                font.weight: 600
                                font.family: Theme.fontText
                            }
                            Text {
                                id: minText
                                anchors.right: bar.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(modelData.min) + "°"
                                color: "#ffffff"
                                opacity: 0.55
                                font.pixelSize: 13
                                font.family: Theme.fontText
                            }
                            // Week-relative range bar, iOS style.
                            Rectangle {
                                id: bar
                                anchors.right: maxText.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.38
                                height: 4
                                radius: 2
                                color: Qt.rgba(1, 1, 1, 0.12)

                                readonly property real span: Math.max(1, dayRow.week.weekMax - dayRow.week.weekMin)
                                Rectangle {
                                    x: (dayRow.modelData.min - dayRow.week.weekMin) / bar.span * bar.width
                                    width: Math.max(4, (dayRow.modelData.max - dayRow.modelData.min) / bar.span * bar.width)
                                    height: parent.height
                                    radius: 2
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0; color: "#64d2ff" }
                                        GradientStop { position: 1; color: "#ffd60a" }
                                    }
                                }
                                // "Now" marker on today's bar.
                                Rectangle {
                                    visible: dayRow.index === 0
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: "#ffffff"
                                    border.color: "#000000"
                                    border.width: 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: (panel.cur.temperature_2m - dayRow.week.weekMin) / bar.span * bar.width - 3
                                }
                            }
                            Text {
                                id: maxText
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(modelData.max) + "°"
                                color: "#ffffff"
                                font.pixelSize: 13
                                font.weight: 600
                                font.family: Theme.fontText
                            }
                        }
                    }
                }
            }

            // ── Detail tiles ──────────────────────────────────────────
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                rowSpacing: 8
                columnSpacing: 8

                Tile {
                    label: "FEELS LIKE"
                    value: panel.ready ? Math.round(panel.cur.apparent_temperature) + "°" : ""
                    detail: panel.ready ? (panel.cur.apparent_temperature < panel.cur.temperature_2m - 1 ? "Wind makes it cooler"
                        : panel.cur.apparent_temperature > panel.cur.temperature_2m + 1 ? "Humidity makes it warmer" : "Similar to actual") : ""
                }

                Tile {
                    label: "HUMIDITY"
                    value: panel.ready ? panel.cur.relative_humidity_2m + "%" : ""
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 10
                        height: 4
                        radius: 2
                        color: Qt.rgba(1, 1, 1, 0.12)
                        Rectangle {
                            width: parent.width * (panel.ready ? panel.cur.relative_humidity_2m / 100 : 0)
                            height: parent.height
                            radius: 2
                            color: "#64d2ff"
                        }
                    }
                }

                Tile {
                    label: "WIND"
                    value: panel.ready ? Math.round(panel.cur.wind_speed_10m) + " km/h" : ""
                    detail: panel.ready ? "from " + panel.compass(panel.cur.wind_direction_10m) : ""
                    // Compass needle pointing where the wind blows to.
                    Item {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        width: 24
                        height: 24
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: "transparent"
                            border.color: Qt.rgba(1, 1, 1, 0.25)
                            border.width: 1
                        }
                        Text {
                            anchors.centerIn: parent
                            rotation: panel.ready ? panel.cur.wind_direction_10m + 180 : 0
                            text: "↑"
                            color: "#ffffff"
                            font.pixelSize: 13
                            font.weight: 700
                        }
                    }
                }

                Tile {
                    label: "UV INDEX"
                    value: panel.ready ? String(Math.round(panel.cur.uv_index)) : ""
                    detail: panel.ready ? panel.uvLabel(panel.cur.uv_index) + (panel.today ? " · max " + Math.round(panel.today.uvMax) : "") : ""
                }

                // Sun arc: position of the sun between sunrise and sunset.
                Tile {
                    id: sunTile
                    label: panel.ready && panel.cur.is_day === 1 ? "SUNSET" : "SUNRISE"
                    value: panel.today ? (panel.cur.is_day === 1 ? panel.hhmm(panel.today.sunset)
                        : panel.hhmm(panel.monitor.daily.length > 1 && new Date() > new Date(panel.today.sunset) ? panel.monitor.daily[1].sunrise : panel.today.sunrise)) : ""
                    // Date() isn't reactive — tick once a minute while shown.
                    property real nowMs: Date.now()
                    Timer { interval: 60000; repeat: true; running: sunTile.visible; onTriggered: sunTile.nowMs = Date.now() }
                    onVisibleChanged: if (visible) nowMs = Date.now()
                    onProgressChanged: sunArc.requestPaint()
                    readonly property real progress: {
                        if (!panel.today) return 0
                        const now = nowMs
                        const a = new Date(panel.today.sunrise).getTime()
                        const b = new Date(panel.today.sunset).getTime()
                        return Math.max(0, Math.min(1, (now - a) / (b - a)))
                    }
                    Canvas {
                        id: sunArc
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 8
                        height: 20
                        onWidthChanged: requestPaint()
                        onAvailableChanged: requestPaint()
                        onVisibleChanged: if (visible) requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const w = width, h = height
                            ctx.strokeStyle = "rgba(255,255,255,0.25)"
                            ctx.lineWidth = 1.5
                            ctx.beginPath()
                            ctx.moveTo(0, h)
                            ctx.quadraticCurveTo(w / 2, -h + 4, w, h)
                            ctx.stroke()
                            const t = sunTile.progress
                            const x = (1 - t) * (1 - t) * 0 + 2 * (1 - t) * t * (w / 2) + t * t * w
                            const y = (1 - t) * (1 - t) * h + 2 * (1 - t) * t * (-h + 4) + t * t * h
                            ctx.fillStyle = "#ffd60a"
                            ctx.beginPath()
                            ctx.arc(x, y, 3.5, 0, Math.PI * 2)
                            ctx.fill()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                Tile {
                    label: "PRESSURE"
                    value: panel.ready ? Math.round(panel.cur.pressure_msl) + "" : ""
                    detail: "hPa"
                }
            }
        }
    }

    Item {
        id: scrollFadeMask
        width: scroller.width
        height: scroller.height
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: scroller.contentY > 2 ? "transparent" : "white" }
                GradientStop { position: 0.05; color: "white" }
                GradientStop { position: 0.9; color: "white" }
                GradientStop { position: 1.0; color: scroller.contentY < scroller.contentHeight - scroller.height - 2 ? "transparent" : "white" }
            }
        }
    }
}
