import CoreAudio
import Foundation

/// System output volume/mute via CoreAudio (public API). Listens for changes, so no polling.
final class VolumeManager: ObservableObject {
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    @Published private(set) var available = false
    var onExternalChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var internalChange = false
    private static let volSel = AudioObjectPropertySelector(0x766D7663)   // 'vmvc' virtual main volume
    private static let muteSel = AudioObjectPropertySelector(kAudioDevicePropertyMute)

    private lazy var deviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.deviceValueChanged() }
    private lazy var defaultDeviceBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachToDefaultDevice() }

    private func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    func start() {
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main, defaultDeviceBlock)
        attachToDefaultDevice()
    }

    private func detach() {
        guard device != kAudioObjectUnknown else { return }
        var va = addr(Self.volSel), ma = addr(Self.muteSel)
        _ = AudioObjectRemovePropertyListenerBlock(device, &va, DispatchQueue.main, deviceBlock)
        _ = AudioObjectRemovePropertyListenerBlock(device, &ma, DispatchQueue.main, deviceBlock)
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func attachToDefaultDevice() {
        detach()
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        var dev = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev) == noErr,
              dev != kAudioObjectUnknown else { available = false; return }
        device = dev
        var va = addr(Self.volSel), ma = addr(Self.muteSel)
        _ = AudioObjectAddPropertyListenerBlock(dev, &va, DispatchQueue.main, deviceBlock)
        _ = AudioObjectAddPropertyListenerBlock(dev, &ma, DispatchQueue.main, deviceBlock)
        readValues()
    }

    private func readValues() {
        var va = addr(Self.volSel)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &va) else { available = false; return }
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectGetPropertyData(device, &va, 0, nil, &size, &v) == noErr {
            volume = v; available = true
        }
        var ma = addr(Self.muteSel)
        if AudioObjectHasProperty(device, &ma) {
            var m: UInt32 = 0
            var msize = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(device, &ma, 0, nil, &msize, &m) == noErr { muted = m != 0 }
        }
    }

    private func deviceValueChanged() {
        let oldV = volume, oldM = muted
        readValues()
        if !internalChange && (oldV != volume || oldM != muted) { onExternalChange?() }
    }

    // MARK: Control from the island

    func set(_ v: Float) {
        guard device != kAudioObjectUnknown else { return }
        internalChange = true
        var value = min(max(v, 0), 1)
        var va = addr(Self.volSel)
        _ = AudioObjectSetPropertyData(device, &va, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        volume = value
        if muted && value > 0 { setMuted(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.internalChange = false }
    }

    func toggleMute() { internalChange = true; setMuted(!muted)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.internalChange = false } }

    private func setMuted(_ m: Bool) {
        var ma = addr(Self.muteSel)
        guard AudioObjectHasProperty(device, &ma) else { return }
        var value: UInt32 = m ? 1 : 0
        _ = AudioObjectSetPropertyData(device, &ma, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        muted = m
    }

    var symbol: String {
        if muted || volume <= 0.001 { return "speaker.slash.fill" }
        if volume < 0.34 { return "speaker.wave.1.fill" }
        if volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
