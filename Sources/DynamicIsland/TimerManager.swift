import Foundation

/// Countdown (Pomodoro), stopwatch and daily alarm. All based on absolute dates, and the only
/// scheduled work is one-shot timers — nothing ticks in the background.
final class TimerManager: ObservableObject {
    @Published private(set) var countdownTotal: TimeInterval = 25 * 60
    @Published private(set) var countdownEnd: Date?
    @Published private(set) var countdownPaused: TimeInterval?
    @Published private(set) var stopwatchStart: Date?
    @Published private(set) var stopwatchBase: TimeInterval = 0
    @Published private(set) var alarmEnabled: Bool
    @Published private(set) var alarmHour: Int
    @Published private(set) var alarmMinute: Int

    var onCountdownDone: (() -> Void)?
    var onAlarm: ((String) -> Void)?
    private var countdownTimer: Timer?
    private var alarmTimer: Timer?
    private var alarmNext: Date?

    init() {
        let d = UserDefaults.standard
        alarmEnabled = d.bool(forKey: "alarm.enabled")
        alarmHour = d.object(forKey: "alarm.hour") as? Int ?? 7
        alarmMinute = d.object(forKey: "alarm.minute") as? Int ?? 0
    }

    func start() { scheduleAlarm() }

    // MARK: Countdown
    var countdownRunning: Bool { countdownEnd != nil }

    func countdownRemaining(at date: Date) -> TimeInterval {
        if let e = countdownEnd { return max(0, e.timeIntervalSince(date)) }
        return countdownPaused ?? countdownTotal
    }
    func setDuration(minutes: Int) {
        guard !countdownRunning else { return }
        countdownTotal = TimeInterval(minutes * 60); countdownPaused = nil
    }
    func setTotal(seconds: Int) {
        guard !countdownRunning else { return }
        countdownTotal = TimeInterval(max(0, seconds)); countdownPaused = nil
    }
    func startCountdown() {
        guard countdownPaused != nil || countdownTotal > 0 else { return }
        let rem = countdownPaused ?? countdownTotal
        countdownEnd = Date().addingTimeInterval(rem); countdownPaused = nil
        scheduleCountdown()
    }
    func pauseCountdown() {
        guard let e = countdownEnd else { return }
        countdownPaused = max(0, e.timeIntervalSinceNow); countdownEnd = nil
        countdownTimer?.invalidate()
    }
    func resetCountdown() {
        countdownTimer?.invalidate(); countdownEnd = nil; countdownPaused = nil
    }
    private func scheduleCountdown() {
        countdownTimer?.invalidate()
        guard let e = countdownEnd else { return }
        let t = Timer(fire: e, interval: 0, repeats: false) { [weak self] _ in self?.finishCountdown() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }
    private func finishCountdown() {
        countdownTimer?.invalidate(); countdownEnd = nil; countdownPaused = nil
        onCountdownDone?()
    }

    // MARK: Stopwatch
    var stopwatchRunning: Bool { stopwatchStart != nil }
    func stopwatchElapsed(at date: Date) -> TimeInterval {
        stopwatchBase + (stopwatchStart.map { date.timeIntervalSince($0) } ?? 0)
    }
    func toggleStopwatch() {
        if let s = stopwatchStart { stopwatchBase += Date().timeIntervalSince(s); stopwatchStart = nil }
        else { stopwatchStart = Date() }
    }
    func resetStopwatch() { stopwatchStart = nil; stopwatchBase = 0 }

    // MARK: Alarm (daily)
    func setAlarm(hour: Int, minute: Int, enabled: Bool) {
        alarmHour = hour; alarmMinute = minute; alarmEnabled = enabled
        let d = UserDefaults.standard
        d.set(enabled, forKey: "alarm.enabled"); d.set(hour, forKey: "alarm.hour"); d.set(minute, forKey: "alarm.minute")
        scheduleAlarm()
    }
    private func scheduleAlarm() {
        alarmTimer?.invalidate(); alarmNext = nil
        guard alarmEnabled,
              let next = Calendar.current.nextDate(after: Date(),
                    matching: DateComponents(hour: alarmHour, minute: alarmMinute, second: 0),
                    matchingPolicy: .nextTime) else { return }
        alarmNext = next
        let t = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in self?.fireAlarm() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        alarmTimer = t
    }
    var alarmLabel: String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        let d = Calendar.current.date(bySettingHour: alarmHour, minute: alarmMinute, second: 0, of: Date()) ?? Date()
        return f.string(from: d)
    }

    func snoozeAlarm(minutes: Int) {
        alarmTimer?.invalidate()
        let fire = Date().addingTimeInterval(TimeInterval(minutes * 60))
        alarmNext = fire
        let t = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in self?.fireAlarm() }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        alarmTimer = t
    }

    private func fireAlarm() {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        onAlarm?(f.string(from: alarmNext ?? Date()))
        scheduleAlarm()
    }

    /// Run timers don't advance while the Mac sleeps, so re-check everything after wake.
    func rescheduleAfterWake() {
        if let e = countdownEnd {
            if e <= Date() { finishCountdown() } else { scheduleCountdown() }
        }
        if alarmEnabled, let n = alarmNext {
            if n <= Date() {
                if Date().timeIntervalSince(n) < 600 { fireAlarm() } else { scheduleAlarm() }
            } else { scheduleAlarm() }
        }
    }
}
