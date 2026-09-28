pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.common

// Weather, from Open-Meteo (no account, no key).  Use it anywhere as
// Weather.wxTemp, Weather.refreshWeather()... (import qs.services).
//
// The location and units come from Settings > Weather (Config); there's no
// location until one is set (a fresh install shouldn't guess).  It fetches
// every 15 minutes, and again when the location or units change.
//
// Over the network: the location's coordinates, to api.open-meteo.com (the
// forecast), and a place name you type, to geocoding-api.open-meteo.com
// (Settings > Weather's search).  Nothing else.
Singleton {
    id: w

    // ---- the location and units ----
    readonly property bool wxHasPlace: Config.cfg.wxLat !== undefined && isFinite(Number(Config.cfg.wxLat))
                                       && Config.cfg.wxLon !== undefined && isFinite(Number(Config.cfg.wxLon))
    readonly property real wxLat: wxHasPlace ? Number(Config.cfg.wxLat) : 0
    readonly property real wxLon: wxHasPlace ? Number(Config.cfg.wxLon) : 0
    readonly property string wxPlace: wxHasPlace ? (Config.cfg.wxPlace || "Your location") : "No location set"
    readonly property bool wxMetric: Config.cfg.wxUnits === "C"

    // ---- the weather now ----
    property string wxCond: ""
    property string wxTemp: ""
    property string wxFeel: ""
    property string wxHum: ""
    property string wxWind: ""
    // the next twelve hours ({ time, temp, cond, day, rain }, plain values),
    // today's high and low, and whether it's daytime where you are
    property var wxHours: []
    property string wxHi: ""
    property string wxLo: ""
    property bool wxDay: true
    property bool   wxOk: false

    function refreshWeather() { if (wxHasPlace) wxProc.running = true }
    // the location or units changed: fetch once the new values are in
    function refreshSoon() { wxRefreshLater.restart() }
    // ...which it notices itself: settings arriving at start-up (the
    // 15-minute timer's first go comes before they're read), a change in
    // Settings, or the file edited by hand
    onWxHasPlaceChanged: refreshSoon()
    onWxLatChanged: refreshSoon()
    onWxLonChanged: refreshSoon()
    onWxMetricChanged: refreshSoon()
    Timer {
        id: wxRefreshLater
        interval: 300
        onTriggered: w.refreshWeather()
    }
    Timer {
        interval: 900000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: w.refreshWeather()
    }

    // the same, as a Material Symbol, with night versions
    function wxSymbol(c, day) {
        const s = (c || "").toLowerCase()
        if (s.indexOf("thunder") !== -1) return "thunderstorm"
        if (s.indexOf("snow") !== -1 || s.indexOf("rime") !== -1) return "weather_snowy"
        if (s.indexOf("rain") !== -1 || s.indexOf("drizzle") !== -1 || s.indexOf("shower") !== -1) return "rainy"
        if (s.indexOf("fog") !== -1) return "foggy"
        if (s.indexOf("overcast") !== -1) return "cloud"
        if (s.indexOf("cloud") !== -1 || s.indexOf("mainly") !== -1)
            return day === false ? "partly_cloudy_night" : "partly_cloudy_day"
        if (s.indexOf("clear") !== -1) return day === false ? "clear_night" : "sunny"
        return "cloud"
    }

    // ---- place search for Settings > Weather, through Open-Meteo's
    //      geocoder; results are plain values ----
    property var wxResults: []
    property bool wxSearching: false
    function searchPlace(q) {
        q = q.trim()
        if (q === "") { wxResults = []; return }
        wxSearching = true
        geoProc.command = ["sh", "-c",
            'curl -s --max-time 10 -G "https://geocoding-api.open-meteo.com/v1/search" '
            + '--data-urlencode "name=$1" -d count=6 -d language=en -d format=json',
            "sh", q]
        geoProc.running = true
    }
    Process {
        id: geoProc
        stdout: StdioCollector {
            onStreamFinished: {
                w.wxSearching = false
                try {
                    const r = JSON.parse(text).results || []
                    w.wxResults = r.map(x => ({
                        name: x.name,
                        where: [x.admin1, x.country].filter(v => v).join(", "),
                        lat: x.latitude,
                        lon: x.longitude
                    }))
                } catch (e) {
                    w.wxResults = []
                }
            }
        }
    }
    function setPlace(r) {
        Config.update({ wxLat: r.lat, wxLon: r.lon,
                        wxPlace: r.name + (r.where ? ", " + r.where.split(", ")[0] : "") })
        wxResults = []
        wxRefreshLater.restart()
    }

    // ---- the forecast ----
    Process {
        id: wxProc
        command: ["sh", "-c",
            "curl -s --max-time 12 'https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + w.wxLat + "&longitude=" + w.wxLon
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
            + "wind_speed_10m,weather_code,is_day"
            + "&hourly=temperature_2m,weather_code,precipitation_probability,is_day&forecast_hours=13"
            + "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
            + (w.wxMetric ? "&temperature_unit=celsius&wind_speed_unit=kmh'"
                          : "&temperature_unit=fahrenheit&wind_speed_unit=mph'")]
        stdout: StdioCollector {
            readonly property var codes: ({
                0: "Clear", 1: "Mainly clear", 2: "Partly cloudy", 3: "Overcast",
                45: "Fog", 48: "Rime fog", 51: "Light drizzle", 53: "Drizzle",
                55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
                61: "Light rain", 63: "Rain", 65: "Heavy rain",
                66: "Freezing rain", 67: "Freezing rain", 71: "Light snow",
                73: "Snow", 75: "Heavy snow", 77: "Snow grains", 80: "Light showers",
                81: "Showers", 82: "Heavy showers", 85: "Snow showers",
                86: "Snow showers", 95: "Thunderstorm", 96: "Thunderstorm",
                99: "Thunderstorm"
            })
            onStreamFinished: {
                try {
                    const j = JSON.parse(text)
                    const c = j.current
                    const u = w.wxMetric ? "\u00b0C" : "\u00b0F"
                    w.wxDay = c.is_day !== 0
                    // the hours ahead, starting with the one we're in
                    const h = j.hourly || {}
                    const hours = []
                    for (let i = 0; i < (h.time || []).length && hours.length < 12; i++) {
                        const hr = parseInt(h.time[i].slice(11, 13))
                        const label = i === 0 ? "Now"
                            : Config.cfg.clock24h === true ? (hr < 10 ? "0" : "") + hr
                            : ((hr % 12) || 12) + (hr < 12 ? " AM" : " PM")
                        hours.push({ time: label, temp: Math.round(h.temperature_2m[i]) + "\u00b0",
                                     cond: codes[h.weather_code[i]] || "", day: h.is_day[i] !== 0,
                                     rain: h.precipitation_probability ? (h.precipitation_probability[i] || 0) : 0 })
                    }
                    w.wxHours = hours
                    const d = j.daily || {}
                    w.wxHi = d.temperature_2m_max ? Math.round(d.temperature_2m_max[0]) + "\u00b0" : ""
                    w.wxLo = d.temperature_2m_min ? Math.round(d.temperature_2m_min[0]) + "\u00b0" : ""
                    w.wxTemp = Math.round(c.temperature_2m) + u
                    w.wxFeel = Math.round(c.apparent_temperature) + u
                    w.wxHum  = c.relative_humidity_2m + "%"
                    w.wxWind = Math.round(c.wind_speed_10m) + (w.wxMetric ? " km/h" : " mph")
                    w.wxCond = codes[c.weather_code] || "Unknown"
                    w.wxOk = true
                } catch (e) {
                    w.wxOk = false
                }
            }
        }
    }
}
