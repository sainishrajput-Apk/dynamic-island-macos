import Foundation
import SwiftUI
import ServiceManagement

extension Notification.Name {
    static let resetPositionRequested = Notification.Name("DynamicIsland.resetPositionRequested")
}

enum AnimationIntensity: String, CaseIterable, Identifiable {
    case off, subtle, standard, lively
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var swiftUIAnimation: Animation? {
        switch self {
        case .off:      return nil
        case .subtle:   return .spring(response: 0.40, dampingFraction: 1.0)
        case .standard: return .spring(response: 0.45, dampingFraction: 0.78)
        case .lively:   return .spring(response: 0.50, dampingFraction: 0.64)
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case auto, dark, light
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum IslandStyle: String, CaseIterable, Identifiable {
    case solid, tinted, glass
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, graphite
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .graphite: return .gray
        }
    }
}

/// All user settings. Every change is written to UserDefaults immediately.
final class Settings: ObservableObject {
    static let shared = Settings()
    private static let d = UserDefaults.standard

    @Published var islandEnabled: Bool   { didSet { Self.d.set(islandEnabled, forKey: "islandEnabled") } }
    @Published var positionLocked: Bool  { didSet { Self.d.set(positionLocked, forKey: "positionLocked") } }
    @Published var animation: AnimationIntensity { didSet { Self.d.set(animation.rawValue, forKey: "animation") } }
    @Published var appearance: AppearanceMode { didSet { Self.d.set(appearance.rawValue, forKey: "appearance") } }
    @Published var style: IslandStyle    { didSet { Self.d.set(style.rawValue, forKey: "style") } }
    @Published var accent: AccentChoice  { didSet { Self.d.set(accent.rawValue, forKey: "accent") } }
    @Published var showDateTime: Bool    { didSet { Self.d.set(showDateTime, forKey: "showDateTime") } }
    @Published var greetingEnabled: Bool { didSet { Self.d.set(greetingEnabled, forKey: "greetingEnabled") } }
    @Published var musicEnabled: Bool    { didSet { Self.d.set(musicEnabled, forKey: "musicEnabled") } }
    @Published var showEqualizer: Bool   { didSet { Self.d.set(showEqualizer, forKey: "showEqualizer") } }
    @Published var chargingEnabled: Bool { didSet { Self.d.set(chargingEnabled, forKey: "chargingEnabled") } }
    @Published var lowBatteryAlerts: Bool { didSet { Self.d.set(lowBatteryAlerts, forKey: "lowBatteryAlerts") } }
    @Published var volumeHUDEnabled: Bool { didSet { Self.d.set(volumeHUDEnabled, forKey: "volumeHUDEnabled") } }
    @Published var weatherEnabled: Bool  { didSet { Self.d.set(weatherEnabled, forKey: "weatherEnabled") } }
    @Published var weatherCity: String   { didSet { Self.d.set(weatherCity, forKey: "weatherCity") } }
    @Published var breakEnabled: Bool    { didSet { Self.d.set(breakEnabled, forKey: "breakEnabled") } }
    @Published var breakIntervalMinutes: Int { didSet { Self.d.set(breakIntervalMinutes, forKey: "breakIntervalMinutes") } }
    @Published var launchAtLogin: Bool   { didSet { if !syncingLogin { applyLaunchAtLogin() } } }
    private var syncingLogin = false

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "islandEnabled": true, "positionLocked": false, "animation": "standard",
            "appearance": "dark", "style": "solid", "accent": "blue",
            "showDateTime": true, "greetingEnabled": true, "musicEnabled": true, "showEqualizer": true,
            "chargingEnabled": true, "lowBatteryAlerts": true, "volumeHUDEnabled": true,
            "weatherEnabled": true, "weatherCity": "Hyderabad", "breakEnabled": true, "breakIntervalMinutes": 60
        ])
        islandEnabled   = d.bool(forKey: "islandEnabled")
        positionLocked  = d.bool(forKey: "positionLocked")
        animation       = AnimationIntensity(rawValue: d.string(forKey: "animation") ?? "") ?? .standard
        appearance      = AppearanceMode(rawValue: d.string(forKey: "appearance") ?? "") ?? .dark
        style           = IslandStyle(rawValue: d.string(forKey: "style") ?? "") ?? .solid
        accent          = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .blue
        showDateTime    = d.bool(forKey: "showDateTime")
        greetingEnabled = d.bool(forKey: "greetingEnabled")
        musicEnabled    = d.bool(forKey: "musicEnabled")
        showEqualizer   = d.bool(forKey: "showEqualizer")
        chargingEnabled = d.bool(forKey: "chargingEnabled")
        lowBatteryAlerts = d.bool(forKey: "lowBatteryAlerts")
        volumeHUDEnabled = d.bool(forKey: "volumeHUDEnabled")
        weatherEnabled  = d.bool(forKey: "weatherEnabled")
        weatherCity     = d.string(forKey: "weatherCity") ?? "Hyderabad"
        breakEnabled    = d.bool(forKey: "breakEnabled")
        breakIntervalMinutes = max(15, d.integer(forKey: "breakIntervalMinutes"))
        launchAtLogin   = SMAppService.mainApp.status == .enabled
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("DynamicIsland: launch-at-login change failed: \(error)")
            syncingLogin = true
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
            syncingLogin = false
        }
    }

    func resetAll() {
        islandEnabled = true; positionLocked = false; animation = .standard
        appearance = .dark; style = .solid; accent = .blue
        showDateTime = true; greetingEnabled = true; musicEnabled = true; showEqualizer = true
        chargingEnabled = true; lowBatteryAlerts = true; volumeHUDEnabled = true
        weatherEnabled = true; weatherCity = "Hyderabad"; breakEnabled = true; breakIntervalMinutes = 60
        launchAtLogin = false
        PositionStore.clear()
        NotificationCenter.default.post(name: .resetPositionRequested, object: nil)
    }
}

struct SavedPosition { var displayID: Int; var fx: Double; var fy: Double }

enum PositionStore {
    static func load() -> SavedPosition? {
        let d = UserDefaults.standard
        guard d.object(forKey: "pos.fx") != nil else { return nil }
        return SavedPosition(displayID: d.integer(forKey: "pos.display"),
                             fx: d.double(forKey: "pos.fx"), fy: d.double(forKey: "pos.fy"))
    }
    static func save(_ p: SavedPosition) {
        let d = UserDefaults.standard
        d.set(p.displayID, forKey: "pos.display"); d.set(p.fx, forKey: "pos.fx"); d.set(p.fy, forKey: "pos.fy")
    }
    static func clear() {
        let d = UserDefaults.standard
        ["pos.display", "pos.fx", "pos.fy"].forEach { d.removeObject(forKey: $0) }
    }
}
