import CoreAudio
import Foundation

/// Đọc / chỉnh âm lượng của thiết bị âm thanh đầu ra mặc định qua CoreAudio (API công khai)
/// và báo khi âm lượng hoặc trạng thái tắt tiếng thay đổi (bất kể ai đổi).
final class VolumeController {
    /// Gọi trên main thread.
    var onChange: ((_ volume: Float, _ isMuted: Bool) -> Void)?

    /// 'vmvc' – kAudioHardwareServiceDeviceProperty_VirtualMainVolume (âm lượng tổng hợp các kênh).
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663

    private struct Registration {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private var registrations: [Registration] = []
    private var systemRegistration: Registration?

    // MARK: - Vòng đời

    func startObserving() {
        guard systemRegistration == nil else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.observeCurrentDevice()
        }
        let system = AudioObjectID(kAudioObjectSystemObject)
        if AudioObjectAddPropertyListenerBlock(system, &address, DispatchQueue.main, block) == noErr {
            systemRegistration = Registration(object: system, address: address, block: block)
        }
        observeCurrentDevice()
    }

    func stopObserving() {
        removeDeviceListeners()
        if var system = systemRegistration {
            AudioObjectRemovePropertyListenerBlock(system.object, &system.address, DispatchQueue.main, system.block)
            systemRegistration = nil
        }
    }

    deinit {
        stopObserving()
    }

    /// Gắn listener vào thiết bị đầu ra hiện tại (gọi lại khi người dùng đổi loa/tai nghe).
    private func observeCurrentDevice() {
        removeDeviceListeners()
        guard let device = defaultOutputDevice() else { return }

        for selector in [Self.virtualMainVolume, kAudioDevicePropertyMute] {
            var address = outputAddress(selector)
            guard AudioObjectHasProperty(device, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.notify()
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block) == noErr {
                registrations.append(Registration(object: device, address: address, block: block))
            }
        }
    }

    private func removeDeviceListeners() {
        for var registration in registrations {
            AudioObjectRemovePropertyListenerBlock(
                registration.object, &registration.address, DispatchQueue.main, registration.block
            )
        }
        registrations.removeAll()
    }

    private func notify() {
        guard let volume else { return }
        onChange?(volume, isMuted)
    }

    // MARK: - Đọc / ghi

    /// Thiết bị không hỗ trợ chỉnh âm lượng (vd. một số HDMI) → false, nên không chặn phím.
    var isSupported: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(Self.virtualMainVolume)
        return AudioObjectHasProperty(device, &address)
    }

    var volume: Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = outputAddress(Self.virtualMainVolume)
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    var isMuted: Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return false }
        return value != 0
    }

    @discardableResult
    func setVolume(_ newValue: Float) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(Self.virtualMainVolume)
        var value = min(max(newValue, 0), 1)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// Tăng/giảm âm lượng. Đang tắt tiếng mà chỉnh âm lượng thì bật tiếng lại (giống macOS).
    /// Trả về (âm lượng, tắt tiếng) sau khi chỉnh, hoặc nil nếu không chỉnh được.
    func step(by delta: Float) -> (volume: Float, isMuted: Bool)? {
        guard let current = volume else { return nil }
        if isMuted { setMuted(false) }
        let target = min(max(current + delta, 0), 1)
        guard setVolume(target) else { return nil }
        return (target, false)
    }

    func toggleMute() -> (volume: Float, isMuted: Bool)? {
        guard let current = volume else { return nil }
        let muted = !isMuted
        guard setMuted(muted) else { return nil }
        return (current, muted)
    }

    // MARK: - Helpers

    private func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != AudioObjectID(kAudioObjectUnknown) ? device : nil
    }

    private func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
