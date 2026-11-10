import Foundation
import IOKit.ps

/// Event-driven battery state (IOKit power-source notifications — no polling).
/// Time-to-full / time-remaining come from macOS's own estimate (the same one the battery menu uses).
final class BatteryManager: ObservableObject {
    @Published private(set) var percent = 0
    @Published private(set) var isCharging = false
    @Published private(set) var isCharged = false
    @Published private(set) var onAC = false
    @Published private(set) var hasBattery = false
    @Published private(set) var timeToFull: Int?     // minutes; nil while macOS is still calculating
    @Published private(set) var timeToEmpty: Int?
    var onPluggedIn: (() -> Void)?
    var onUnplugged: (() -> Void)?
    var onLowBattery: ((Int) -> Void)?

    private var source: CFRunLoopSource?
    private var firstRead = true
    private var lowLevelAlerted = 100

    func start() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let s = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryManager>.fromOpaque(ctx).takeUnretainedValue().refresh()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .commonModes)
            source = s
        }
        refresh()
    }

    func refresh() {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let info = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let cap = info[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = cap > 0 ? Int((Double(cur) / Double(cap) * 100).rounded()) : cur
            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let charged = info[kIOPSIsChargedKey] as? Bool ?? false
            let ac = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let ttf = (info[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 >= 0 ? $0 : nil }
            let tte = (info[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 >= 0 ? $0 : nil }
            apply(pct, charging, charged, ac, ttf, tte)
            return
        }
    }

    private func apply(_ pct: Int, _ charging: Bool, _ charged: Bool, _ ac: Bool, _ ttf: Int?, _ tte: Int?) {
        let wasAC = onAC
        let first = firstRead
        firstRead = false
        hasBattery = true
        if percent != pct { percent = pct }
        if isCharging != charging { isCharging = charging }
        if isCharged != charged { isCharged = charged }
        if onAC != ac { onAC = ac }
        if timeToFull != ttf { timeToFull = ttf }
        if timeToEmpty != tte { timeToEmpty = tte }
        if !first && ac && !wasAC { onPluggedIn?() }
        if !first && !ac && wasAC { onUnplugged?() }
        if ac || pct > 20 {
            lowLevelAlerted = 100
        } else {
            for level in [10, 20] where pct <= level && lowLevelAlerted > level {
                lowLevelAlerted = level
                onLowBattery?(pct)
                break
            }
        }
    }

    // MARK: Text for the UI

    private func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }

    var chargeStatusText: String {
        if isCharged || (onAC && percent >= 100) { return "Fully charged" }
        if onAC && !isCharging { return "Plugged in, not charging" }
        if let m = timeToFull { return m == 0 ? "Almost full" : "\(duration(m)) until full" }
        return "Calculating time to full…"
    }

    var dischargeStatusText: String {
        if let m = timeToEmpty { return "\(duration(m)) remaining" }
        return "Calculating time remaining…"
    }
}
