import SwiftUI

enum IslandPage: String, CaseIterable, Identifiable {
    case home, music, timer, controls
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .home: return "clock"
        case .music: return "music.note"
        case .timer: return "timer"
        case .controls: return "slider.horizontal.3"
        }
    }
}

enum RingKind: Equatable { case alarm, timer, breakTime }
enum RingAction { case stop, snooze }

enum IslandMode: Equatable {
    case compact
    case panel
    case greeting(title: String, subtitle: String)
    case power(plugged: Bool)
    case hud(symbol: String, value: Double)
    case alert(title: String, subtitle: String, symbol: String)
    case ring(title: String, subtitle: String, symbol: String, kind: RingKind)

    var cornerRadius: CGFloat {
        switch self {
        case .compact: return 17
        case .panel: return 32
        case .power: return 26
        case .hud: return 26
        case .ring: return 34
        default: return 30
        }
    }
}

final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .compact
    @Published var page: IslandPage = .home
    @Published var timeText = ""
    @Published var dateText = ""
    @Published var systemDark = true

    let music = MusicManager()
    let battery = BatteryManager()
    let volume = VolumeManager()
    let timers = TimerManager()
    let system = SystemControls()
    let weather = WeatherManager()

    static let compactWidth: CGFloat = 116
    static let activityWidth: CGFloat = 232

    var musicCompactActive: Bool {
        Settings.shared.musicEnabled && music.isPlaying && music.track != nil
    }

    /// Anything "live" that the pill should track: music, a running timer/stopwatch, or an armed alarm.
    var hasActivity: Bool {
        musicCompactActive || timers.countdownRunning || timers.countdownPaused != nil
            || timers.stopwatchRunning || timers.alarmEnabled
    }

    func size(for mode: IslandMode) -> CGSize {
        switch mode {
        case .compact:  return CGSize(width: hasActivity ? Self.activityWidth : Self.compactWidth, height: 34)
        case .panel:    return CGSize(width: 400, height: 232)
        case .greeting: return CGSize(width: 320, height: 84)
        case .power:    return CGSize(width: 330, height: 64)
        case .hud:      return CGSize(width: 280, height: 56)
        case .alert:    return CGSize(width: 320, height: 76)
        case .ring:     return CGSize(width: 400, height: 98)
        }
    }
}
