import Foundation
import CoreGraphics

/// Built-in display brightness and Bluetooth power.
/// Both use PRIVATE Apple functions loaded at runtime with dlopen/dlsym. They are not in any
/// public SDK, so Apple may change or remove them in any macOS update. If a function can't be
/// found, the matching control is hidden instead of faking it.
final class SystemControls: ObservableObject {
    @Published var brightness: Float = 0.5
    @Published private(set) var brightnessAvailable = false
    @Published private(set) var bluetoothOn = false
    @Published private(set) var bluetoothAvailable = false

    private typealias BrightGet = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias BrightSet = @convention(c) (UInt32, Float) -> Int32
    private typealias BTGet = @convention(c) () -> Int32
    private typealias BTSet = @convention(c) (Int32) -> Void

    private var getBrightness: BrightGet?
    private var setBrightnessFn: BrightSet?
    private var getBT: BTGet?
    private var setBT: BTSet?

    init() {
        if let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
           let g = dlsym(h, "DisplayServicesGetBrightness"),
           let s = dlsym(h, "DisplayServicesSetBrightness") {
            getBrightness = unsafeBitCast(g, to: BrightGet.self)
            setBrightnessFn = unsafeBitCast(s, to: BrightSet.self)
        }
        if let h = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
           let g = dlsym(h, "IOBluetoothPreferenceGetControllerPowerState"),
           let s = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") {
            getBT = unsafeBitCast(g, to: BTGet.self)
            setBT = unsafeBitCast(s, to: BTSet.self)
        }
        refresh()
    }

    /// Called when the Controls page opens (neither value has a change notification).
    func refresh() {
        if let get = getBrightness {
            var b: Float = 0
            if get(CGMainDisplayID(), &b) == 0 { brightness = b; brightnessAvailable = true }
            else { brightnessAvailable = false }
        }
        if let get = getBT { bluetoothOn = get() != 0; bluetoothAvailable = true }
    }

    func setBrightness(_ v: Float) {
        brightness = v
        _ = setBrightnessFn?(CGMainDisplayID(), min(max(v, 0), 1))
    }

    func setBluetooth(_ on: Bool) {
        setBT?(on ? 1 : 0)
        bluetoothOn = on
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.refresh() }
    }
}
