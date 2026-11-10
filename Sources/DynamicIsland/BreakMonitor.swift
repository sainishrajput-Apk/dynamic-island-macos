import Foundation
import CoreGraphics
import IOKit
import IOKit.pwr_mgt

/// Counts how long you have been continuously using the Mac and asks for a break.
/// "Using" = keyboard/mouse activity within the last 5 minutes, or a video holding the display awake.
/// Checked once a minute (piggybacks on the clock tick). A 5-minute gap resets the count.
final class BreakMonitor {
    var onDue: (() -> Void)?
    private var sessionStart: Date?
    private var snoozedUntil: Date?
    private let idleResetSeconds: TimeInterval = 5 * 60

    func reset() { sessionStart = nil; snoozedUntil = nil }
    func snooze(minutes: Int) { snoozedUntil = Date().addingTimeInterval(TimeInterval(minutes * 60)) }

    func tick() {
        let s = Settings.shared
        guard s.breakEnabled else { sessionStart = nil; snoozedUntil = nil; return }
        let now = Date()
        if Self.isSessionLocked() { sessionStart = nil; return }

        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                          eventType: CGEventType(rawValue: UInt32.max)!)
        if idle >= idleResetSeconds && !Self.displayHeldAwake() { sessionStart = nil; return }
        if sessionStart == nil { sessionStart = now; return }

        if let until = snoozedUntil {
            guard now >= until else { return }
            snoozedUntil = nil; sessionStart = now; onDue?(); return
        }
        if now.timeIntervalSince(sessionStart!) >= TimeInterval(s.breakIntervalMinutes * 60) {
            sessionStart = now
            onDue?()
        }
    }

    static func isSessionLocked() -> Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private static func displayHeldAwake() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&unmanaged) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { return false }
        return ((dict["PreventUserIdleDisplaySleep"] as? Int) ?? 0) > 0
    }
}
