import AppKit
import SwiftUI
import Combine

/// Owns the panel and routes every event (wake, music, battery, volume, timers, breaks) to the island.
/// Event-driven throughout: the only recurring timer is the once-per-minute clock tick.
final class IslandController {
    let settings = Settings.shared
    let model = IslandModel()
    private let panel = IslandPanel()
    private let catcher = ClickCatcher()
    private let breakMonitor = BreakMonitor()
    private var anchor = NSPoint.zero            // top-center point of the island, screen coordinates
    private var clockTimer: Timer?
    private var collapseWork: DispatchWorkItem?
    private var resizeWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    private var timeFormatter = DateFormatter()
    private var dateFormatter = DateFormatter()
    private var pendingGreetingSince: Date?
    private var lastGreeting = Date.distantPast
    private var outsideClickMonitor: Any?
    private var lastActivity = false
    private var ringSound: NSSound?
    private var ringStopWork: DispatchWorkItem?

    // MARK: Start-up

    func start() {
        makeFormatters(); refreshClock(); scheduleClock()
        anchor = loadAnchor()
        model.systemDark = Self.systemIsDark()

        let hosting = IslandHostingView(rootView: IslandView(
            model: model, music: model.music, timers: model.timers, battery: model.battery, settings: settings,
            onTap: { [weak self] in self?.handleTap() },
            onCollapse: { [weak self] in self?.collapse() },
            onRing: { [weak self] kind, action in self?.handleRing(kind, action) }))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.isDragAllowed = { [weak self] in !(self?.settings.positionLocked ?? true) }
        panel.canStartDrag = { [weak self] p in
            guard let self else { return true }
            // While the panel is open, only its top strip drags the island (so sliders and wheels work).
            return self.model.mode == .panel ? p.y > self.panel.frame.maxY - 20 : true
        }
        catcher.onClick = { [weak self] in self?.collapse() }
        panel.onDragBegan = { [weak self] in self?.collapseWork?.cancel() }
        panel.onDragEnd = { [weak self] in self?.dragEnded() }

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)
        model.timers.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.activitiesChanged() }
            .store(in: &cancellables)
        model.music.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.activitiesChanged() }
            .store(in: &cancellables)

        connectFeatures()
        observeSystemEvents()
        lastActivity = model.hasActivity
        applyVisibility()
    }

    private func connectFeatures() {
        model.music.start()

        model.battery.onPluggedIn = { [weak self] in
            guard let self, self.settings.chargingEnabled else { return }
            self.showTransient(.power(plugged: true), hold: 5.5)
            // macOS needs a few seconds to settle its time-to-full estimate; re-read it.
            for delay in [2.0, 8.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self.model.battery.refresh() }
            }
        }
        model.battery.onUnplugged = { [weak self] in
            guard let self, self.settings.chargingEnabled else { return }
            self.showTransient(.power(plugged: false), hold: 4.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.model.battery.refresh() }
        }
        model.battery.onLowBattery = { [weak self] pct in
            guard let self, self.settings.lowBatteryAlerts else { return }
            self.showAlert(title: "Low Battery", subtitle: "\(pct)% remaining — plug in soon", symbol: "battery.25", hold: 6)
        }
        model.battery.start()

        model.volume.onExternalChange = { [weak self] in self?.volumeChanged() }
        model.volume.start()

        model.timers.onCountdownDone = { [weak self] in
            self?.startRing(title: "Timer", subtitle: "Time's up", symbol: "timer", kind: .timer)
        }
        model.timers.onAlarm = { [weak self] time in
            self?.startRing(title: "Alarm", subtitle: time, symbol: "alarm.fill", kind: .alarm)
        }
        model.timers.start()

        breakMonitor.onDue = { [weak self] in self?.showBreak() }
        model.weather.start()
    }

    private func observeSystemEvents() {
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter
        let dnc = DistributedNotificationCenter.default()

        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.anchor = self.loadAnchor()
            self.layoutPanel(size: self.panel.isVisible ? self.panel.frame.size : self.model.size(for: self.model.mode))
        }
        nc.addObserver(forName: .resetPositionRequested, object: nil, queue: .main) { [weak self] _ in self?.resetPosition() }
        for name in [Notification.Name.NSSystemClockDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshClock(); self?.scheduleClock() }
        }
        nc.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.makeFormatters(); self?.refreshClock()
        }

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.clockTimer?.invalidate(); self?.clockTimer = nil
                self?.breakMonitor.reset()
            }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.handleWake() }
        }
        dnc.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.handleUnlock()
        }
        dnc.addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.model.systemDark = Self.systemIsDark() }
        }
    }

    private static func systemIsDark() -> Bool {
        let domain = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)
        return (domain?["AppleInterfaceStyle"] as? String) == "Dark"
    }

    // MARK: Settings reactions

    private func settingsChanged() {
        if !settings.musicEnabled && model.music.track != nil { model.music.clear() }
        model.weather.configChanged()
        activitiesChanged()
        applyVisibility()
    }

    private var shouldBeVisible: Bool {
        settings.islandEnabled && (settings.showDateTime || model.mode != .compact || model.hasActivity)
    }

    private func applyVisibility() {
        if shouldBeVisible {
            if !panel.isVisible { layoutPanel(size: model.size(for: model.mode)); panel.orderFrontRegardless() }
        } else if model.mode == .compact {
            panel.orderOut(nil)
        }
    }

    // MARK: Transitions

    private func resize(from old: CGSize, to new: CGSize) {
        resizeWork?.cancel()
        layoutPanel(size: CGSize(width: max(old.width, new.width), height: max(old.height, new.height)))
        if settings.islandEnabled { panel.orderFrontRegardless() }
        let work = DispatchWorkItem { [weak self] in self?.finishTransition() }
        resizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func transition(to new: IslandMode) {
        resize(from: model.size(for: model.mode), to: model.size(for: new))
        model.mode = new                                   // IslandView animates this change
        if new == .panel { installOutsideClickMonitor(); showCatcher() }
        else { removeOutsideClickMonitor(); hideCatcher() }
    }

    private func finishTransition() {
        guard !panel.isDragging else { return }
        layoutPanel(size: model.size(for: model.mode))
        if !shouldBeVisible { panel.orderOut(nil) }
    }

    private func scheduleCollapse(after seconds: TimeInterval) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.panel.isDragging else { return }
            self.transition(to: .compact)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func collapse() {
        stopRingSound()
        collapseWork?.cancel()
        transition(to: .compact)
    }

    private func openPanel(page: IslandPage) {
        collapseWork?.cancel()
        model.page = page
        transition(to: .panel)
    }

    private func handleTap() {
        switch model.mode {
        case .compact:
            let t = model.timers
            if t.countdownRunning || t.countdownPaused != nil || t.stopwatchRunning { openPanel(page: .timer) }
            else if model.musicCompactActive { openPanel(page: .music) }
            else { openPanel(page: .home) }
        case .panel, .ring: break
        default: collapse()
        }
    }

    private var ringIsShowing: Bool {
        if case .ring(_, _, _, _) = model.mode { return true }
        return false
    }

    /// A short, non-critical overlay. Never interrupts an open panel or a ringing alarm.
    private func showTransient(_ mode: IslandMode, hold: TimeInterval) {
        guard settings.islandEnabled, model.mode != .panel, !ringIsShowing else { return }
        if case .hud(_, _) = model.mode, case .hud(_, _) = mode { model.mode = mode }   // just update the bar
        else { transition(to: mode) }
        scheduleCollapse(after: hold)
    }

    private func showAlert(title: String, subtitle: String, symbol: String, hold: TimeInterval) {
        NSSound(named: NSSound.Name("Glass"))?.play()
        guard settings.islandEnabled, !ringIsShowing else { return }
        collapseWork?.cancel()
        transition(to: .alert(title: title, subtitle: subtitle, symbol: symbol))
        scheduleCollapse(after: hold)
    }

    // MARK: Alarm / timer / break — stays up with a sound until you act on it

    private func startRing(title: String, subtitle: String, symbol: String, kind: RingKind) {
        stopRingSound()
        if let s = NSSound(named: NSSound.Name(kind == .breakTime ? "Ping" : "Glass")) {
            s.loops = (kind != .breakTime)
            s.play()
            ringSound = s
        }
        let stop = DispatchWorkItem { [weak self] in self?.stopRingSound() }
        ringStopWork = stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 90, execute: stop)

        guard settings.islandEnabled else { return }
        collapseWork?.cancel()
        transition(to: .ring(title: title, subtitle: subtitle, symbol: symbol, kind: kind))
        scheduleCollapse(after: kind == .breakTime ? 60 : 120)
    }

    private func stopRingSound() {
        ringSound?.stop(); ringSound = nil
        ringStopWork?.cancel(); ringStopWork = nil
    }

    private func handleRing(_ kind: RingKind, _ action: RingAction) {
        switch (kind, action) {
        case (.alarm, .snooze): model.timers.snoozeAlarm(minutes: 9)
        case (.breakTime, .snooze): breakMonitor.snooze(minutes: 10)
        default: break
        }
        collapse()
    }

    private func showBreak() {
        let m = settings.breakIntervalMinutes
        let span = m % 60 == 0 ? "\(m / 60) hour\(m / 60 == 1 ? "" : "s")" : "\(m) minutes"
        startRing(title: "Time for a break",
                  subtitle: "You've been on your Mac for \(span). Stretch and rest your eyes.",
                  symbol: "figure.walk", kind: .breakTime)
    }

    // MARK: Outside-click closing

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.collapse()      // global monitors only see clicks in OTHER apps, i.e. outside the island
        }
    }
    private func removeOutsideClickMonitor() {
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m); outsideClickMonitor = nil }
    }

    private func updateCatcherFrame() {
        let f = panel.frame
        catcher.setFrame(NSRect(x: f.minX - 160, y: f.minY - 160, width: f.width + 320, height: f.height + 160), display: false)
    }
    private func showCatcher() {
        updateCatcherFrame()
        catcher.orderFrontRegardless()
        catcher.order(.below, relativeTo: panel.windowNumber)
    }
    private func hideCatcher() { catcher.orderOut(nil) }

    // MARK: Feature events

    /// Music, timers, stopwatch or alarm started/stopped: grow or shrink the compact pill.
    private func activitiesChanged() {
        let now = model.hasActivity
        guard now != lastActivity else { return }
        let was = lastActivity
        lastActivity = now
        applyVisibility()
        if model.mode == .compact {
            resize(from: CGSize(width: was ? IslandModel.activityWidth : IslandModel.compactWidth, height: 34),
                   to: model.size(for: .compact))
        }
    }

    private func volumeChanged() {
        guard settings.volumeHUDEnabled, model.mode != .panel else { return }
        let v = model.volume
        showTransient(.hud(symbol: v.symbol, value: Double(v.muted ? 0 : v.volume)), hold: 1.6)
    }

    // MARK: Position

    private func screenID(_ s: NSScreen) -> Int {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    private func defaultAnchor() -> NSPoint {
        guard let s = NSScreen.screens.first else { return .zero }
        return NSPoint(x: s.frame.midX, y: s.visibleFrame.maxY - 6)
    }

    private func loadAnchor() -> NSPoint {
        guard let saved = PositionStore.load() else { return defaultAnchor() }
        let screen = NSScreen.screens.first { screenID($0) == saved.displayID } ?? NSScreen.screens.first
        guard let f = screen?.frame else { return defaultAnchor() }
        return NSPoint(x: f.minX + saved.fx * f.width, y: f.minY + saved.fy * f.height)
    }

    private func layoutPanel(size: CGSize) {
        var frame = NSRect(x: anchor.x - size.width / 2, y: anchor.y - size.height, width: size.width, height: size.height)
        if let sf = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(anchor) })?.frame {
            frame.origin.x = min(max(frame.origin.x, sf.minX), max(sf.minX, sf.maxX - frame.width))
        }
        panel.setFrame(frame, display: false)
        if catcher.isVisible { updateCatcherFrame() }
    }

    private func dragEnded() {
        let f = panel.frame
        var a = NSPoint(x: f.midX, y: f.maxY)
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(a) } ?? NSScreen.screens.first
        guard let screen else { return }
        let sf = screen.frame
        a.x = min(max(a.x, sf.minX + f.width / 2), sf.maxX - f.width / 2)
        a.y = min(max(a.y, sf.minY + f.height), sf.maxY)
        anchor = a
        PositionStore.save(SavedPosition(displayID: screenID(screen),
                                         fx: (a.x - sf.minX) / sf.width, fy: (a.y - sf.minY) / sf.height))
        layoutPanel(size: f.size)
        if model.mode != .compact && model.mode != .panel && !ringIsShowing { scheduleCollapse(after: 3) }
    }

    func resetPosition() {
        PositionStore.clear()
        anchor = defaultAnchor()
        layoutPanel(size: panel.isVisible ? panel.frame.size : model.size(for: model.mode))
    }

    // MARK: Clock

    private func makeFormatters() {
        timeFormatter = DateFormatter()
        timeFormatter.locale = .autoupdatingCurrent
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short                   // follows the macOS 12/24-hour setting
        dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    }

    private func refreshClock() {
        let now = Date()
        let t = timeFormatter.string(from: now), d = dateFormatter.string(from: now)
        if model.timeText != t { model.timeText = t }
        if model.dateText != d { model.dateText = d }
    }

    /// Once per minute, exactly on the minute. Also drives the break-reminder check.
    private func scheduleClock() {
        clockTimer?.invalidate()
        let next = Calendar.current.nextDate(after: Date(), matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            self?.refreshClock()
            self?.breakMonitor.tick()
            self?.scheduleClock()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    // MARK: Wake greeting

    private func handleWake() {
        refreshClock(); scheduleClock()
        breakMonitor.reset()
        model.timers.rescheduleAfterWake()
        model.battery.refresh()
        model.weather.wakeRefresh()
        guard settings.greetingEnabled, settings.islandEnabled else { return }
        guard Date().timeIntervalSince(lastGreeting) > 600 else { return }
        pendingGreetingSince = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.pendingGreetingSince != nil, !BreakMonitor.isSessionLocked() else { return }
            self.showGreeting()
        }
    }

    private func handleUnlock() {
        guard let since = pendingGreetingSince, Date().timeIntervalSince(since) < 120 else { return }
        showGreeting()
    }

    private func showGreeting() {
        pendingGreetingSince = nil
        guard settings.greetingEnabled, settings.islandEnabled else { return }
        lastGreeting = Date()
        let g = Self.greeting(for: Date())
        showTransient(.greeting(title: g.0, subtitle: g.1), hold: 4)
    }

    static func greeting(for date: Date) -> (String, String) {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12:  return ("Good Morning ☀️", "Hope you have a wonderful day!")
        case 12..<17: return ("Good Afternoon ☀️", "Time to get things done.")
        case 17..<21: return ("Good Evening 🌆", "How was your day?")
        default:      return ("Good Night 🌙", "Time to relax.")
        }
    }
}
