import Foundation

/// Live weather from Open-Meteo (free, no account or key). One small request every 30 minutes,
/// only while weather is switched on. The city you type in Settings is looked up once and cached.
final class WeatherManager: ObservableObject {
    @Published private(set) var temperature: Int?
    @Published private(set) var symbol = "cloud.fill"
    @Published private(set) var summary = ""

    private var timer: Timer?
    private var debounce: DispatchWorkItem?
    private var appliedKey = ""
    private var updated = Date.distantPast

    func start() { configChanged(force: true) }

    /// Call whenever settings change; only does work if weather on/off or the city actually changed.
    func configChanged(force: Bool = false) {
        let s = Settings.shared
        let city = s.weatherCity.trimmingCharacters(in: .whitespaces)
        let key = "\(s.weatherEnabled)|\(city)"
        if !force && key == appliedKey { return }
        appliedKey = key
        debounce?.cancel(); timer?.invalidate()
        guard s.weatherEnabled, !city.isEmpty else { temperature = nil; return }
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (force ? 0.5 : 1.5), execute: work)
    }

    func wakeRefresh() {
        guard Settings.shared.weatherEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.refresh() }
    }

    private func refresh() {
        let s = Settings.shared
        let city = s.weatherCity.trimmingCharacters(in: .whitespaces)
        guard s.weatherEnabled, !city.isEmpty else { return }
        let d = UserDefaults.standard
        if d.string(forKey: "weather.q") == city, d.object(forKey: "weather.lat") != nil {
            fetch(lat: d.double(forKey: "weather.lat"), lon: d.double(forKey: "weather.lon"))
        } else {
            geocode(city)
        }
    }

    private func geocode(_ city: String) {
        guard let enc = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(enc)&count=1&language=en&format=json") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let first = (obj["results"] as? [[String: Any]])?.first,
                  let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
                DispatchQueue.main.async { self?.scheduleNext(after: 300) }
                return
            }
            DispatchQueue.main.async {
                let d = UserDefaults.standard
                d.set(city, forKey: "weather.q"); d.set(lat, forKey: "weather.lat"); d.set(lon, forKey: "weather.lon")
                self?.fetch(lat: lat, lon: lon)
            }
        }.resume()
    }

    private func fetch(lat: Double, lon: Double) {
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,is_day&timezone=auto") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = obj["current"] as? [String: Any],
                  let temp = cur["temperature_2m"] as? Double else {
                DispatchQueue.main.async { self?.scheduleNext(after: 300) }
                return
            }
            let code = (cur["weather_code"] as? Int) ?? 0
            let isDay = ((cur["is_day"] as? Int) ?? 1) == 1
            DispatchQueue.main.async {
                guard let self else { return }
                let (sym, text) = Self.describe(code: code, isDay: isDay)
                self.temperature = Int(temp.rounded())
                self.symbol = sym; self.summary = text
                self.updated = Date()
                self.scheduleNext(after: 1800)
            }
        }.resume()
    }

    private func scheduleNext(after seconds: TimeInterval) {
        timer?.invalidate()
        guard Settings.shared.weatherEnabled else { return }
        let t = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.refresh() }
        t.tolerance = 30
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    static func describe(code: Int, isDay: Bool) -> (String, String) {
        switch code {
        case 0:  return (isDay ? "sun.max.fill" : "moon.stars.fill", "Clear")
        case 1:  return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Mostly clear")
        case 2:  return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Partly cloudy")
        case 3:  return ("cloud.fill", "Overcast")
        case 45, 48: return ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57: return ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67: return ("cloud.rain.fill", "Rain")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "Snow")
        case 80, 81, 82: return ("cloud.heavyrain.fill", "Showers")
        case 85, 86: return ("cloud.snow.fill", "Snow showers")
        case 95, 96, 99: return ("cloud.bolt.rain.fill", "Thunderstorm")
        default: return ("cloud.fill", "Cloudy")
        }
    }
}
