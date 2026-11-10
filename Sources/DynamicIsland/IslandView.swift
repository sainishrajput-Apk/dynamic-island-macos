import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var music: MusicManager
    @ObservedObject var timers: TimerManager
    @ObservedObject var battery: BatteryManager
    @ObservedObject var settings: Settings
    var onTap: () -> Void
    var onCollapse: () -> Void
    var onRing: (RingKind, RingAction) -> Void

    private var isDark: Bool {
        switch settings.appearance {
        case .dark: return true
        case .light: return false
        case .auto: return model.systemDark
        }
    }

    var body: some View {
        let size = model.size(for: model.mode)
        let theme = IslandTheme(isDark: isDark, accent: settings.accent.color)
        let hidden = model.mode == .compact && !settings.showDateTime && !model.hasActivity

        ZStack {
            background
            content(theme)
        }
        .environment(\.islandTheme, theme)
        .environment(\.colorScheme, isDark ? .dark : .light)
        .foregroundStyle(theme.primary)
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: model.mode.cornerRadius, style: .continuous))
        .opacity(hidden ? 0 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .animation(settings.animation.swiftUIAnimation, value: model.mode)
        .animation(settings.animation.swiftUIAnimation, value: model.hasActivity)
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: model.mode.cornerRadius, style: .continuous)
        let base: Color = isDark ? .black : Color(white: 0.96)
        ZStack {
            switch settings.style {
            case .solid:
                shape.fill(base)
            case .tinted:
                shape.fill(base).overlay(shape.fill(settings.accent.color.opacity(isDark ? 0.30 : 0.22)))
            case .glass:
                shape.fill(.ultraThinMaterial)
            }
            if model.mode == .panel {
                shape.fill(LinearGradient(colors: [Color.white.opacity(isDark ? 0.07 : 0.0), .clear],
                                          startPoint: .top, endPoint: .center))
            }
            shape.strokeBorder(
                LinearGradient(colors: [(isDark ? Color.white : Color.black).opacity(isDark ? 0.20 : 0.10),
                                        (isDark ? Color.white : Color.black).opacity(0.02)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 0.7)
        }
    }

    // MARK: Compact pill with live activities

    @ViewBuilder private func compactContent(_ theme: IslandTheme) -> some View {
        if !model.hasActivity {
            Text(model.timeText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1)
        } else {
            HStack(spacing: 0) {
                leftSlot(theme).frame(minWidth: 26, alignment: .leading)
                Spacer(minLength: 6)
                Text(model.timeText)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit().lineLimit(1)
                Spacer(minLength: 6)
                rightSlot(theme).frame(minWidth: 26, alignment: .trailing)
            }
            .padding(.horizontal, 12)
        }
    }

    private var countdownActive: Bool { timers.countdownRunning || timers.countdownPaused != nil }

    @ViewBuilder private func leftSlot(_ theme: IslandTheme) -> some View {
        if model.musicCompactActive {
            ArtworkView(image: music.artwork, size: 22)
        } else if countdownActive {
            Image(systemName: "timer").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.timer)
        } else if timers.stopwatchRunning {
            Image(systemName: "stopwatch.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.timer)
        } else if timers.alarmEnabled {
            Image(systemName: "alarm.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.timer)
        }
    }

    @ViewBuilder private func rightSlot(_ theme: IslandTheme) -> some View {
        if countdownActive {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(formatTime(timers.countdownRemaining(at: ctx.date)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(theme.timer)
            }
        } else if timers.stopwatchRunning {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(formatTime(timers.stopwatchElapsed(at: ctx.date)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(theme.timer)
            }
        } else if model.musicCompactActive {
            if settings.showEqualizer { EqualizerBars(color: theme.accent) }
            else { Image(systemName: "waveform").font(.system(size: 13)).foregroundStyle(theme.accent) }
        } else if timers.alarmEnabled {
            Text(timers.alarmLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(theme.timer)
        }
    }

    @ViewBuilder private func content(_ theme: IslandTheme) -> some View {
        switch model.mode {
        case .compact:
            compactContent(theme).transition(.opacity)

        case .panel:
            PanelView(model: model, onCollapse: onCollapse).transition(.opacity)

        case .greeting(let title, let subtitle):
            VStack(spacing: 4) {
                Text(title).font(.system(size: 20, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(theme.secondary)
            }
            .lineLimit(1).transition(.opacity)

        case .power(let plugged):
            PowerView(battery: battery, plugged: plugged).transition(.opacity)

        case .hud(let symbol, let value):
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).frame(width: 24)
                SimpleBar(value: value, tint: theme.accent, height: 6)
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 18).transition(.opacity)

        case .alert(let title, let subtitle, let symbol):
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 26, weight: .semibold)).foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.secondary)
                }
                Spacer()
            }
            .lineLimit(1).padding(.horizontal, 22).transition(.opacity)

        case .ring(let title, let subtitle, let symbol, let kind):
            HStack(spacing: 14) {
                WiggleIcon(symbol: symbol, color: kind == .breakTime ? theme.accent : theme.timer, wiggle: kind == .alarm)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(theme.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                VStack(spacing: 6) {
                    if kind != .timer {
                        Button(kind == .alarm ? "Snooze 9 min" : "Snooze 10 min") { onRing(kind, .snooze) }
                            .buttonStyle(PillButtonStyle())
                    }
                    Button(kind == .breakTime ? "Got it" : "Stop") { onRing(kind, .stop) }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            .padding(.horizontal, 20).transition(.opacity)
        }
    }
}
