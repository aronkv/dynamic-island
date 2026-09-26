import Quickshell.Io
import QtQuick

// One-purpose monitor: IP-based geolocation feeding a keyless current-weather
// API, with an optional manual-city override (settingsStore.weatherCity/
// weatherManualLocation) for when IP geolocation is inaccurate. Both base
// steps confirmed live against the real endpoints before wiring this up:
// ip-api.com/json returned a real Hungarian location for this machine, and
// api.open-meteo.com/v1/forecast?...&current_weather=true returned a real
// current_weather block for those coordinates. The manual-override path uses
// open-meteo's own free geocoding endpoint rather than adding a second API.
Item {
    id: weatherMonitor

    // Optional — set from DynamicIsland.qml. Null is handled (falls back to
    // pure IP geolocation, i.e. today's behavior).
    property var settingsStore: null

    readonly property real latitude: _lat
    readonly property real longitude: _lon
    readonly property string city: _city
    readonly property bool locationReady: _lat !== 0 || _lon !== 0
    // Set when a manually-entered city fails to geocode. Deliberately never
    // clears temperature/iconName/etc. — the Settings panel shows this as an
    // inline warning while the widget keeps displaying the last good reading
    // (confirmed useful in a reference project rather than blanking on one
    // bad entry).
    readonly property bool locationError: _locationError

    readonly property real temperature: _temperature
    readonly property int weatherCode: _weatherCode
    readonly property bool isDay: _isDay
    readonly property bool weatherReady: _weatherReady

    readonly property string conditionText: weatherMonitor._conditionFor(weatherCode)
    readonly property string iconName: weatherMonitor._iconFor(weatherCode, isDay)

    property real _lat: 0
    property real _lon: 0
    property string _city: ""
    property real _temperature: 0
    property int _weatherCode: -1
    property bool _isDay: true
    property bool _weatherReady: false
    property bool _locationError: false

    // WMO weather codes (open-meteo's current_weather.weathercode) mapped to
    // a human condition and an Adwaita symbolic icon name — confirmed to
    // actually exist on this system via `find /usr/share/icons/Adwaita
    // -iname "weather-*symbolic*"` before picking these names.
    function _conditionFor(code) {
        if (code === 0) return "Clear"
        if (code === 1 || code === 2) return "Partly Cloudy"
        if (code === 3) return "Overcast"
        if (code === 45 || code === 48) return "Fog"
        if (code >= 51 && code <= 57) return "Drizzle"
        if (code >= 61 && code <= 67) return "Rain"
        if (code >= 71 && code <= 77) return "Snow"
        if (code === 80 || code === 81 || code === 82) return "Rain Showers"
        if (code === 85 || code === 86) return "Snow Showers"
        if (code === 95) return "Thunderstorm"
        if (code === 96 || code === 99) return "Severe Thunderstorm"
        return "Unknown"
    }

    function _iconFor(code, isDay) {
        if (code === 0) return isDay ? "weather-clear-symbolic" : "weather-clear-night-symbolic"
        if (code === 1 || code === 2) return isDay ? "weather-few-clouds-symbolic" : "weather-few-clouds-night-symbolic"
        if (code === 3) return "weather-overcast-symbolic"
        if (code === 45 || code === 48) return "weather-fog-symbolic"
        if (code >= 51 && code <= 57) return "weather-showers-scattered-symbolic"
        if (code >= 61 && code <= 67) return "weather-showers-symbolic"
        if (code >= 71 && code <= 77) return "weather-snow-symbolic"
        if (code === 80 || code === 81 || code === 82) return "weather-showers-symbolic"
        if (code === 85 || code === 86) return "weather-snow-symbolic"
        if (code === 95 || code === 96 || code === 99) return "weather-storm-symbolic"
        return "weather-severe-alert-symbolic"
    }

    // Picks IP geolocation or the manual-city override, based on the
    // Settings panel's current choice. Called at startup, on the periodic
    // re-resolve timer, and whenever the override itself changes.
    function refreshLocation() {
        const manual = weatherMonitor.settingsStore && weatherMonitor.settingsStore.weatherManualLocation
            ? weatherMonitor.settingsStore.weatherCity.trim() : ""
        if (manual !== "") {
            geocodeProbe.command = ["curl", "-s", "--max-time", "5",
                "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(manual) + "&count=1"]
            geocodeProbe.running = true
        } else {
            weatherMonitor._locationError = false
            geoProbe.running = true
        }
    }

    Process {
        id: geoProbe
        command: ["curl", "-s", "--max-time", "5", "http://ip-api.com/json"]
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                try {
                    const data = JSON.parse(text)
                    if (data.status === "success") {
                        weatherMonitor._lat = data.lat
                        weatherMonitor._lon = data.lon
                        weatherMonitor._city = data.city || ""
                        weatherMonitor.fetchWeather()
                    }
                } catch (e) {
                    // Leave last-known location in place; next scheduled
                    // retry (a laptop's IP-based location barely changes,
                    // so a single failed lookup isn't urgent to recover).
                }
            }
        }
    }

    // Geocodes a manually-entered city (Settings panel override) via
    // open-meteo's own free geocoding endpoint. An unknown/empty result only
    // sets `locationError` for the Settings panel to flag — it never resets
    // the coordinates or the last-shown reading.
    Process {
        id: geocodeProbe
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                try {
                    const data = JSON.parse(text)
                    const hit = data.results && data.results.length > 0 ? data.results[0] : null
                    if (hit) {
                        weatherMonitor._lat = hit.latitude
                        weatherMonitor._lon = hit.longitude
                        weatherMonitor._city = hit.name || ""
                        weatherMonitor._locationError = false
                        weatherMonitor.fetchWeather()
                    } else {
                        weatherMonitor._locationError = true
                    }
                } catch (e) {
                    weatherMonitor._locationError = true
                }
            }
        }
    }

    Component.onCompleted: weatherMonitor.refreshLocation()

    Connections {
        target: weatherMonitor.settingsStore
        function onWeatherManualLocationChanged() { weatherMonitor.refreshLocation() }
        function onWeatherCityChanged() { weatherMonitor.refreshLocation() }
    }

    // Re-resolve location only every 3 hours — IP geolocation for a laptop
    // that isn't traveling essentially never changes, so polling this as
    // often as the weather itself would just be wasted requests.
    Timer {
        interval: 3 * 60 * 60 * 1000
        running: true
        repeat: true
        onTriggered: weatherMonitor.refreshLocation()
    }

    // Extended forecast (Rice Phase 3): current conditions + next 24 h +
    // 7 days in one request. `command` is assigned imperatively in
    // fetchWeather() — a declarative binding on _lat/_lon lags one change
    // behind (see CLAUDE.md), which could fetch the previous location.
    readonly property var current: _current          // raw open-meteo `current` block
    readonly property var hourly: _hourly            // [{time, temp, code, isDay, precip}] × 24
    readonly property var daily: _daily              // [{date, code, max, min, sunrise, sunset, uvMax, precipMax}] × 7
    property var _current: null
    // "manual" (city typed in Settings) or "ip" (approximate, from the
    // public IP — can be off by tens of km), plus when data last arrived.
    readonly property string locationSource: settingsStore && settingsStore.weatherManualLocation && settingsStore.weatherCity.trim() !== "" ? "manual" : "ip"
    property date lastUpdated: new Date(0)
    property var _hourly: []
    property var _daily: []

    function fetchWeather() {
        weatherProbe.command = ["curl", "-s", "--max-time", "8",
            "https://api.open-meteo.com/v1/forecast?latitude=" + weatherMonitor._lat
            + "&longitude=" + weatherMonitor._lon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,weather_code,is_day,uv_index,pressure_msl,visibility"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day&forecast_hours=24"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,precipitation_probability_max&forecast_days=7"
            + "&timezone=auto"]
        weatherProbe.running = true
    }

    Process {
        id: weatherProbe
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                try {
                    const data = JSON.parse(text)
                    const c = data.current
                    if (!c) return
                    weatherMonitor._current = c
                    weatherMonitor.lastUpdated = new Date()
                    weatherMonitor._temperature = c.temperature_2m
                    weatherMonitor._weatherCode = c.weather_code
                    weatherMonitor._isDay = c.is_day === 1
                    const h = data.hourly
                    const hours = []
                    if (h) for (let i = 0; i < h.time.length; i++)
                        hours.push({ time: h.time[i], temp: h.temperature_2m[i], code: h.weather_code[i],
                                     isDay: h.is_day[i] === 1, precip: h.precipitation_probability[i] })
                    weatherMonitor._hourly = hours
                    const d = data.daily
                    const days = []
                    if (d) for (let i = 0; i < d.time.length; i++)
                        days.push({ date: d.time[i], code: d.weather_code[i], max: d.temperature_2m_max[i],
                                    min: d.temperature_2m_min[i], sunrise: d.sunrise[i], sunset: d.sunset[i],
                                    uvMax: d.uv_index_max[i], precipMax: d.precipitation_probability_max[i] })
                    weatherMonitor._daily = days
                    weatherMonitor._weatherReady = true
                } catch (e) {
                    // Keep last-known reading; next poll retries.
                }
            }
        }
    }

    // 15 minutes — open-meteo's own current_weather block updates roughly
    // hourly anyway, this just keeps us reasonably fresh without hammering
    // a free keyless endpoint.
    Timer {
        interval: 15 * 60 * 1000
        running: true
        repeat: true
        onTriggered: if (weatherMonitor.locationReady) weatherMonitor.fetchWeather()
    }
}
