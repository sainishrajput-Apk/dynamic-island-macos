import SwiftUI
import AppKit

struct IslandTheme {
    var isDark: Bool
    var accent: Color
    var primary: Color { isDark ? .white : .black }
    var secondary: Color { isDark ? Color.white.opacity(0.62) : Color.black.opacity(0.55) }
    var track: Color { isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12) }
    /// iPhone-style yellow/orange used for timers, stopwatch and alarms.
    var timer: Color { Color(red: 1.0, green: 0.72, blue: 0.08) }
}

private struct IslandThemeKey: EnvironmentKey {
    static let defaultValue = IslandTheme(isDark: true, accent: .blue)
}
extension EnvironmentValues {
    var islandTheme: IslandTheme {
        get { self[IslandThemeKey.self] }
        set { self[IslandThemeKey.self] = newValue }
    }
}

func hapticTick() {
    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
}

func formatTime(_ t: TimeInterval) -> String {
    let s = Int(t.rounded(.down))
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

struct SimpleBar: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 5
    @Environment(\.islandTheme) private var theme
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track)
                Capsule().fill(tint).frame(width: CGFloat(max(0, min(1, value))) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    @Environment(\.islandTheme) private var theme
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    theme.track
                    Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(theme.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

/// Decorative equalizer. NOT driven by the real audio.
struct EqualizerBars: View {
    var color: Color
    @State private var up = false
    private let low: [CGFloat] = [4, 8, 5, 9, 4]
    private let high: [CGFloat] = [14, 6, 16, 7, 12]
    private let dur: [Double] = [0.45, 0.6, 0.38, 0.55, 0.5]
    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(color)
                    .frame(width: 3, height: up ? high[i] : low[i])
                    .animation(.easeInOut(duration: dur[i]).repeatForever(autoreverses: true), value: up)
            }
        }
        .frame(height: 18)
        .onAppear { up = true }
    }
}

struct BatteryGlyph: View {
    var percent: Int
    var charging: Bool
    @Environment(\.islandTheme) private var theme
    private var fill: Color { charging ? .green : (percent <= 20 ? .red : theme.primary) }
    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.secondary, lineWidth: 1)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(fill)
                    .frame(width: max(2, 24 * CGFloat(min(max(percent, 0), 100)) / 100), height: 10)
                    .padding(.leading, 2)
            }
            .frame(width: 28, height: 14)
            RoundedRectangle(cornerRadius: 1).fill(theme.secondary).frame(width: 2, height: 5)
        }
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.islandTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 13).padding(.vertical, 6)
            .background(
                Capsule().fill(prominent
                    ? AnyShapeStyle(LinearGradient(colors: [theme.accent.opacity(0.98), theme.accent.opacity(0.78)],
                                                   startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(theme.track))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0.22 : 0.08), lineWidth: 0.6))
            .foregroundStyle(prominent ? Color.white : theme.primary)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Hover magnify

struct MagnifyButton<Label: View>: View {
    var scale: CGFloat = 1.45
    var action: () -> Void
    @ViewBuilder var label: () -> Label
    @State private var hovering = false
    @Environment(\.islandTheme) private var theme

    var body: some View {
        Button(action: action) {
            label()
                .scaleEffect(hovering ? scale : 1)
                .frame(width: 34, height: 28)
                .background(
                    Capsule()
                        .fill(theme.primary.opacity(0.14))
                        .overlay(Capsule().strokeBorder(theme.primary.opacity(0.28), lineWidth: 0.6))
                        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                        .scaleEffect(hovering ? scale * 0.95 : 0.55)
                        .opacity(hovering ? 1 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.30, dampingFraction: 0.60)) { hovering = h }
            if h { hapticTick() }
        }
    }
}

// MARK: - Toggle, slider, segmented control (all follow the accent colour)

struct PremiumToggle: View {
    @Binding var isOn: Bool
    @GestureState private var pressing = false
    @Environment(\.islandTheme) private var theme

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn
                      ? AnyShapeStyle(LinearGradient(colors: [theme.accent.opacity(0.88), theme.accent],
                                                     startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color(white: 0.30)))
            Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.6)
            Capsule()
                .fill(Color.white)
                .frame(width: pressing ? 32 : 26, height: 26)
                .shadow(color: .black.opacity(0.28), radius: 2.5, y: 1.5)
                .padding(2)
        }
        .frame(width: 52, height: 30)
        .animation(.spring(response: 0.34, dampingFraction: 0.70), value: isOn)
        .animation(.spring(response: 0.25, dampingFraction: 0.80), value: pressing)
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
                .onEnded { _ in isOn.toggle(); hapticTick() }
        )
    }
}

struct AccentSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    @Environment(\.islandTheme) private var theme
    @State private var dragging = false
    private let knob: CGFloat = 20

    var body: some View {
        GeometryReader { g in
            let w = max(g.size.width, knob + 1)
            let n = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = CGFloat(min(max(n, 0), 1)) * (w - knob)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.track).frame(height: 6)
                Capsule().fill(theme.accent).frame(width: x + knob / 2, height: 6)
                Circle().fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.3), radius: 2.5, y: 1)
                    .scaleEffect(dragging ? 1.12 : 1)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        let p = min(max(Double((v.location.x - knob / 2) / (w - knob)), 0), 1)
                        value = range.lowerBound + p * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in dragging = false }
            )
        }
        .frame(height: 24)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: dragging)
    }
}

struct AccentSegmented<T: Hashable>: View {
    let items: [T]
    let title: (T) -> String
    @Binding var selection: T
    @Namespace private var ns
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.self) { item in
                Text(title(item))
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundStyle(selection == item ? Color.white : theme.secondary)
                    .background {
                        if selection == item {
                            Capsule().fill(theme.accent).matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = item }
                    }
            }
        }
        .padding(2)
        .background(Capsule().fill(theme.track))
    }
}

struct RollingDigits: View {
    var text: String
    var size: CGFloat
    var countsDown = true
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: countsDown))
            .animation(.easeInOut(duration: 0.28), value: text)
    }
}

// MARK: - Free-scrolling wheel (iOS-style, with momentum)

/// Turns trackpad / mouse-wheel scrolling over the wheel into a continuous position (in rows),
/// then snaps to the nearest row when the scroll (and its momentum) ends.
final class WheelScroller: ObservableObject {
    @Published var pos: CGFloat = 0
    var hovering = false
    var count = 1
    var loops = true
    var rowH: CGFloat = 28
    var onIndex: ((Int) -> Void)?
    private var monitor: Any?
    private var lastIndex = 0
    private var lastHaptic = Date.distantPast
    private var settleWork: DispatchWorkItem?

    func wrap(_ i: Int) -> Int { loops ? ((i % count) + count) % count : min(max(i, 0), count - 1) }
    private func clamped(_ p: CGFloat) -> CGFloat { loops ? p : min(max(p, 0), CGFloat(count - 1)) }

    func configure(count: Int, loops: Bool, rowH: CGFloat, index: Int) {
        self.count = count; self.loops = loops; self.rowH = rowH
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { pos = CGFloat(index) }
        lastIndex = index
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, self.hovering else { return e }
            self.handle(e)
            return nil
        }
    }
    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        hovering = false
    }

    private func tick() {
        let now = Date()
        if now.timeIntervalSince(lastHaptic) > 0.035 { lastHaptic = now; hapticTick() }
    }

    func setImmediate(_ p: CGFloat) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { pos = clamped(p) }
        let i = wrap(Int(pos.rounded()))
        if i != lastIndex { lastIndex = i; onIndex?(i); tick() }
    }

    func animate(to target: Int) {
        let t = loops ? CGFloat(target) : CGFloat(min(max(target, 0), count - 1))
        let i = wrap(Int(t))
        if i != lastIndex { lastIndex = i; onIndex?(i); tick() }
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 19)) { pos = t }
    }

    func settle() { settleWork?.cancel(); animate(to: Int(pos.rounded())) }

    /// Called when the bound value changes from outside (for example a preset button).
    func sync(to idx: Int) {
        let cur = Int(pos.rounded())
        let curWrapped = wrap(cur)
        if curWrapped == idx { return }
        var delta = idx - curWrapped
        if loops {
            if delta > count / 2 { delta -= count } else if delta < -count / 2 { delta += count }
        }
        lastIndex = idx
        withAnimation(.interpolatingSpring(stiffness: 170, damping: 19)) {
            pos = loops ? CGFloat(cur + delta) : CGFloat(idx)
        }
    }

    private func handle(_ e: NSEvent) {
        if e.hasPreciseScrollingDeltas {
            setImmediate(pos - e.scrollingDeltaY / rowH)
            if e.momentumPhase == .ended || e.phase == .cancelled || (e.phase == .ended && e.momentumPhase.isEmpty) {
                settle()
            } else {
                settleWork?.cancel()
                let w = DispatchWorkItem { [weak self] in self?.settle() }
                settleWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
            }
        } else {
            let rows = max(1, min(6, Int(abs(e.scrollingDeltaY).rounded(.up))))
            animate(to: Int(pos.rounded()) + (e.scrollingDeltaY < 0 ? rows : -rows))
        }
    }
}

/// The rows themselves. Conforms to Animatable so the roll between positions is drawn smoothly every frame.
struct WheelRows: View, Animatable {
    var pos: CGFloat
    let count: Int
    let loops: Bool
    let rowH: CGFloat
    let width: CGFloat
    let label: (Int) -> String
    let onTapRow: (Int) -> Void

    var animatableData: CGFloat {
        get { pos }
        set { pos = newValue }
    }

    var body: some View {
        let base = Int(floor(pos))
        ZStack {
            ForEach(Array((base - 3)...(base + 4)), id: \.self) { r in
                if loops || (r >= 0 && r < count) {
                    let y = CGFloat(r) - pos
                    let d = abs(y)
                    let baseText = Text(label(((r % count) + count) % count))
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    let framedText = baseText.frame(width: width, height: rowH)
                    let scaledText = framedText.scaleEffect(max(0.7, 1 - 0.10 * d))
                    let fadedText = scaledText.opacity(max(0.10, 1 - 0.36 * d))
                    let rotatedText = fadedText.rotation3DEffect(.degrees(Double(y) * -16), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
                    let offsetText = rotatedText.offset(y: y * rowH)
                    let shapedText = offsetText.contentShape(Rectangle())
                    shapedText.onTapGesture { onTapRow(r) }
                }
            }
        }
    }
}

struct WheelPicker: View {
    let count: Int
    let loops: Bool
    let label: (Int) -> String
    @Binding var index: Int
    var width: CGFloat = 58
    var rowH: CGFloat = 28
    var unit: String? = nil
    @StateObject private var scroller = WheelScroller()
    @State private var dragStart: CGFloat?
    @Environment(\.islandTheme) private var theme

    var body: some View {
        WheelRows(pos: scroller.pos, count: count, loops: loops, rowH: rowH, width: width,
                  label: label, onTapRow: { scroller.animate(to: $0) })
            .frame(width: width, height: rowH * 5)
            .mask(fade)
            .overlay(alignment: .center) {
                if let unit {
                    Text(unit).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.secondary)
                        .offset(x: width * 0.36, y: 2)
                }
            }
            .contentShape(Rectangle())
            .onHover { h in
                scroller.hovering = h
                if !h { scroller.settle() }
            }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if dragStart == nil { dragStart = scroller.pos }
                        scroller.setImmediate((dragStart ?? scroller.pos) - v.translation.height / rowH)
                    }
                    .onEnded { v in
                        let predicted = (dragStart ?? scroller.pos) - v.predictedEndTranslation.height / rowH
                        dragStart = nil
                        scroller.animate(to: Int(predicted.rounded()))
                    }
            )
            .onAppear {
                scroller.configure(count: count, loops: loops, rowH: rowH, index: index)
                scroller.onIndex = { index = $0 }
                scroller.start()
            }
            .onDisappear { scroller.stop() }
            .onChange(of: index) { scroller.sync(to: $0) }
    }

    private var fade: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0),
                               .init(color: .black, location: 0.30),
                               .init(color: .black, location: 0.70),
                               .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Small icons

struct WiggleIcon: View {
    var symbol: String
    var color: Color
    var wiggle: Bool
    @State private var on = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(color)
            .rotationEffect(.degrees(wiggle ? (on ? 12 : -12) : 0))
            .animation(wiggle ? .easeInOut(duration: 0.12).repeatForever(autoreverses: true) : .default, value: on)
            .onAppear { on = true }
    }
}

struct PowerView: View {
    @ObservedObject var battery: BatteryManager
    var plugged: Bool
    @State private var pulse = false
    @Environment(\.islandTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plugged ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(plugged ? Color.green : theme.secondary)
                .scaleEffect(plugged ? (pulse ? 1.14 : 0.94) : 1)
                .frame(width: 26)
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            VStack(alignment: .leading, spacing: 2) {
                Text(plugged ? "Charging" : "On Battery").font(.system(size: 14, weight: .semibold))
                Text(plugged ? battery.chargeStatusText : battery.dischargeStatusText)
                    .font(.system(size: 11)).foregroundStyle(theme.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            Text("\(battery.percent)%")
                .font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
            BatteryGlyph(percent: battery.percent, charging: plugged && battery.isCharging)
        }
        .padding(.horizontal, 20)
        .onAppear { pulse = plugged }
    }
}
