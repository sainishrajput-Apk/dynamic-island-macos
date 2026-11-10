import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Form {
            Section("Island") {
                Toggle("Enable Dynamic Island", isOn: $settings.islandEnabled)
                Toggle("Lock position", isOn: $settings.positionLocked)
                Button("Reset to default position") {
                    PositionStore.clear()
                    NotificationCenter.default.post(name: .resetPositionRequested, object: nil)
                }
                row("Animation") {
                    AccentSegmented(items: AnimationIntensity.allCases, title: { $0.label }, selection: $settings.animation)
                        .frame(width: 270)
                }
            }
            Section("Appearance") {
                row("Mode") {
                    AccentSegmented(items: AppearanceMode.allCases, title: { $0.label }, selection: $settings.appearance)
                        .frame(width: 210)
                }
                row("Style") {
                    AccentSegmented(items: IslandStyle.allCases, title: { $0.label }, selection: $settings.style)
                        .frame(width: 210)
                }
                row("Accent colour") {
                    HStack(spacing: 10) {
                        ForEach(AccentChoice.allCases) { a in
                            Circle().fill(a.color).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(Color.primary, lineWidth: settings.accent == a ? 2 : 0).padding(-3))
                                .onTapGesture { settings.accent = a }
                        }
                    }
                }
                Text("Glass style uses live blur, which costs more GPU than Solid.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Features") {
                Toggle("Show date and time", isOn: $settings.showDateTime)
                Toggle("Greet me when my Mac wakes", isOn: $settings.greetingEnabled)
                Toggle("Music (Apple Music, Spotify)", isOn: $settings.musicEnabled)
                Toggle("Animated equalizer", isOn: $settings.showEqualizer)
                Toggle("Charging and unplug animation", isOn: $settings.chargingEnabled)
                Toggle("Low battery alerts", isOn: $settings.lowBatteryAlerts)
                Toggle("Volume pop-up", isOn: $settings.volumeHUDEnabled)
            }
            Section("Weather") {
                Toggle("Show weather beside the date", isOn: $settings.weatherEnabled)
                TextField("City", text: $settings.weatherCity)
                Text("Uses Open-Meteo (free). One small request every 30 minutes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Break reminders") {
                Toggle("Remind me to take a break", isOn: $settings.breakEnabled)
                row("Remind after") {
                    AccentSegmented(items: [30, 45, 60, 90], title: { "\($0) min" }, selection: $settings.breakIntervalMinutes)
                        .frame(width: 270)
                }
                Text("Counts time you are actively using the Mac. A 5-minute pause resets it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Button("Reset all settings", role: .destructive) { settings.resetAll() }
            }
        }
        .formStyle(.grouped)
        .tint(settings.accent.color)
        .environment(\.islandTheme, IslandTheme(isDark: scheme == .dark, accent: settings.accent.color))
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack { Text(title); Spacer(); content() }
    }
}
