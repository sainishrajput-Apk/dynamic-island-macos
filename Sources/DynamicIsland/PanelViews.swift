import SwiftUI

struct PanelView: View {
    @ObservedObject var model: IslandModel
    var onCollapse: () -> Void
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.page {
                case .home:     HomePage(model: model, battery: model.battery, weather: model.weather)
                case .music:    MusicPage(music: model.music)
                case .timer:    TimerPage(timers: model.timers)
                case .controls: ControlsPage(volume: model.volume, system: model.system, settings: Settings.shared)
                }
            }
            .id(model.page)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                ForEach(IslandPage.allCases) { p in
                    MagnifyButton(scale: 1.3, action: { model.page = p }) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(model.page == p ? theme.accent : theme.secondary)
                    }
                }
                Spacer()
                MagnifyButton(scale: 1.6, action: onCollapse) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 38)
        }
        .animation(.easeInOut(duration: 0.2), value: model.page)
    }
}

struct HomePage: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var battery: BatteryManager
    @ObservedObject var weather: WeatherManager
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 5) {
            Text(model.timeText)
                .font(.system(size: 42, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(spacing: 8) {
                Text(model.dateText).font(.system(size: 14, weight: .medium)).foregroundStyle(theme.secondary)
                if Settings.shared.weatherEnabled, let t = weather.temperature {
                    Text("·").foregroundStyle(theme.secondary)
                    Image(systemName: weather.symbol)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                    Text("\(t)°").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
            }
            if battery.hasBattery {
                HStack(spacing: 6) {
                    BatteryGlyph(percent: battery.percent, charging: battery.isCharging)
                    Text("\(battery.percent)%").font(.system(size: 12, weight: .medium)).monospacedDigit()
                    if battery.onAC {
                        Image(systemName: "bolt.fill").font(.system(size: 11)).foregroundStyle(.green)
                        Text(battery.chargeStatusText).font(.system(size: 12)).foregroundStyle(theme.secondary)
                    } else if let m = battery.timeToEmpty {
                        Text("· " + (m >= 60 ? "\(m / 60) h \(m % 60) min left" : "\(m) min left"))
                            .font(.system(size: 12)).foregroundStyle(theme.secondary)
                    }
                }
                .padding(.top, 3)
            }
        }
        .lineLimit(1)
    }
}

struct MusicPage: View {
    @ObservedObject var music: MusicManager
    @Environment(\.islandTheme) private var theme

    var body: some View {
        if let t = music.track {
            HStack(spacing: 16) {
                ArtworkView(image: music.artwork, size: 104)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(t.title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        if t.isAd {
                            Text("AD").font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(theme.accent)).foregroundStyle(Color.white)
                        }
                    }
                    Text(t.artist).font(.system(size: 13)).foregroundStyle(theme.secondary).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let pos = music.currentPosition(at: ctx.date)
                        let dur = max(t.duration, 1)
                        VStack(spacing: 3) {
                            SimpleBar(value: pos / dur, tint: theme.accent, height: 4)
                            HStack {
                                Text(formatTime(pos))
                                Spacer()
                                Text("-" + formatTime(max(dur - pos, 0)))
                            }
                            .font(.system(size: 10)).monospacedDigit().foregroundStyle(theme.secondary)
                        }
                    }
                    HStack(spacing: 20) {
                        Spacer()
                        transport("backward.fill", 16) { music.previous() }.opacity(t.isAd ? 0.3 : 1).disabled(t.isAd)
                        transport(music.isPlaying ? "pause.fill" : "play.fill", 22) { music.playPause() }
                        transport("forward.fill", 16) { music.next() }.opacity(t.isAd ? 0.3 : 1).disabled(t.isAd)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 24)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(theme.secondary)
                Text("Nothing playing").font(.system(size: 14, weight: .semibold))
                Text("Play something in Apple Music or Spotify").font(.system(size: 12)).foregroundStyle(theme.secondary)
            }
        }
    }

    private func transport(_ symbol: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        MagnifyButton(scale: 1.25, action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
        }
    }
}

struct TimerPage: View {
    @ObservedObject var timers: TimerManager
    @State private var tab = 0
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            AccentSegmented(items: [0, 1, 2], title: { ["Timer", "Stopwatch", "Alarm"][$0] }, selection: $tab)
                .frame(width: 290)
            Group {
                switch tab {
                case 0: countdown
                case 1: stopwatch
                default: alarm
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 10)
    }

    // MARK: Timer

    private var totalSeconds: Int { Int(timers.countdownTotal) }

    private func setTotal(h: Int? = nil, m: Int? = nil, s: Int? = nil) {
        let t = totalSeconds
        let nh = h ?? t / 3600, nm = m ?? (t % 3600) / 60, ns = s ?? t % 60
        timers.setTotal(seconds: nh * 3600 + nm * 60 + ns)
    }

    @ViewBuilder private var countdown: some View {
        if timers.countdownRunning || timers.countdownPaused != nil {
            VStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let remaining = timers.countdownRemaining(at: ctx.date)
                    VStack(spacing: 10) {
                        RollingDigits(text: formatTime(remaining), size: 46, countsDown: true)
                            .foregroundStyle(theme.timer)
                        SimpleBar(value: 1 - remaining / max(timers.countdownTotal, 1), tint: theme.timer, height: 4)
                            .frame(width: 220)
                    }
                }
                HStack(spacing: 8) {
                    Button(timers.countdownRunning ? "Pause" : "Resume") {
                        timers.countdownRunning ? timers.pauseCountdown() : timers.startCountdown()
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    Button("Cancel") { timers.resetCountdown() }.buttonStyle(PillButtonStyle())
                }
            }
        } else {
            HStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.accent.opacity(0.22)).frame(width: 196, height: 28)
                    HStack(spacing: 0) {
                        WheelPicker(count: 24, loops: true, label: { String($0) },
                                    index: Binding(get: { totalSeconds / 3600 }, set: { setTotal(h: $0) }),
                                    width: 64, rowH: 26, unit: "hr")
                        WheelPicker(count: 60, loops: true, label: { String($0) },
                                    index: Binding(get: { (totalSeconds % 3600) / 60 }, set: { setTotal(m: $0) }),
                                    width: 64, rowH: 26, unit: "min")
                        WheelPicker(count: 60, loops: true, label: { String($0) },
                                    index: Binding(get: { totalSeconds % 60 }, set: { setTotal(s: $0) }),
                                    width: 64, rowH: 26, unit: "sec")
                    }
                }
                VStack(spacing: 9) {
                    HStack(spacing: 6) {
                        ForEach([5, 15], id: \.self) { m in
                            Button("\(m)m") { timers.setTotal(seconds: m * 60) }.buttonStyle(PillButtonStyle())
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach([25, 45], id: \.self) { m in
                            Button("\(m)m") { timers.setTotal(seconds: m * 60) }.buttonStyle(PillButtonStyle())
                        }
                    }
                    Button("Start") { timers.startCountdown() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(totalSeconds == 0)
                        .opacity(totalSeconds == 0 ? 0.5 : 1)
                }
            }
        }
    }

    // MARK: Stopwatch

    private var stopwatch: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: timers.stopwatchRunning ? 0.1 : 1)) { ctx in
                let t = timers.stopwatchElapsed(at: ctx.date)
                let s = Int(t)
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    RollingDigits(text: formatTime(Double(s)), size: 46, countsDown: false)
                        .foregroundStyle(timers.stopwatchRunning ? theme.timer : theme.primary)
                    Text(String(format: ".%d", Int((t - Double(s)) * 10)))
                        .font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(theme.secondary)
                }
            }
            HStack(spacing: 8) {
                Button(timers.stopwatchRunning ? "Stop" : "Start") { timers.toggleStopwatch() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Reset") { timers.resetStopwatch() }.buttonStyle(PillButtonStyle())
            }
        }
    }

    // MARK: Alarm

    private var hourIdx: Int { let h = timers.alarmHour % 12; return h == 0 ? 11 : h - 1 }
    private var isPM: Bool { timers.alarmHour >= 12 }

    private func apply(hourIndex: Int, minute: Int, pm: Bool) {
        let h24 = ((hourIndex + 1) % 12) + (pm ? 12 : 0)
        timers.setAlarm(hour: h24, minute: minute, enabled: timers.alarmEnabled)
    }

    private var alarm: some View {
        HStack(spacing: 26) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.accent.opacity(0.22)).frame(width: 196, height: 28)
                HStack(spacing: 0) {
                    WheelPicker(count: 12, loops: true, label: { String($0 + 1) },
                                index: Binding(get: { hourIdx },
                                               set: { apply(hourIndex: $0, minute: timers.alarmMinute, pm: isPM) }),
                                width: 64, rowH: 26)
                    WheelPicker(count: 60, loops: true, label: { String(format: "%02d", $0) },
                                index: Binding(get: { timers.alarmMinute },
                                               set: { apply(hourIndex: hourIdx, minute: $0, pm: isPM) }),
                                width: 64, rowH: 26)
                    WheelPicker(count: 2, loops: false, label: { $0 == 0 ? "AM" : "PM" },
                                index: Binding(get: { isPM ? 1 : 0 },
                                               set: { apply(hourIndex: hourIdx, minute: timers.alarmMinute, pm: $0 == 1) }),
                                width: 64, rowH: 26)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Alarm").font(.system(size: 14, weight: .semibold))
                    PremiumToggle(isOn: Binding(
                        get: { timers.alarmEnabled },
                        set: { timers.setAlarm(hour: timers.alarmHour, minute: timers.alarmMinute, enabled: $0) }))
                }
                Text("Repeats daily").font(.system(size: 11)).foregroundStyle(theme.secondary)
                Text("Can't wake a sleeping Mac").font(.system(size: 11)).foregroundStyle(theme.secondary)
            }
        }
    }
}

struct ControlsPage: View {
    @ObservedObject var volume: VolumeManager
    @ObservedObject var system: SystemControls
    @ObservedObject var settings: Settings
    @Environment(\.islandTheme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            if volume.available {
                HStack(spacing: 10) {
                    Button { volume.toggleMute() } label: {
                        Image(systemName: volume.symbol).font(.system(size: 14)).frame(width: 24)
                    }
                    .buttonStyle(.plain)
                    AccentSlider(value: Binding(get: { Double(volume.volume) }, set: { volume.set(Float($0)) }))
                }
            }
            if system.brightnessAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "sun.max.fill").font(.system(size: 14)).frame(width: 24)
                    AccentSlider(value: Binding(get: { Double(system.brightness) }, set: { system.setBrightness(Float($0)) }),
                                 range: 0.02...1)
                }
            }
            if system.bluetoothAvailable {
                toggleRow("dot.radiowaves.left.and.right", "Bluetooth",
                          Binding(get: { system.bluetoothOn }, set: { system.setBluetooth($0) }))
            }
            toggleRow("figure.walk", "Break reminders", $settings.breakEnabled)
        }
        .padding(.horizontal, 28)
        .onAppear { system.refresh() }
    }

    private func toggleRow(_ symbol: String, _ title: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 24)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            PremiumToggle(isOn: binding)
        }
    }
}
