import Foundation

/// Gom các nguồn âm lượng / độ sáng / đèn bàn phím thành một luồng `HUDEvent`,
/// đồng thời cho UI đọc và đặt mức từng loại (thanh trượt điều khiển nhanh).
///
/// Hai chế độ cho HUD:
/// - **Quan sát** (mặc định): chỉ nghe thay đổi âm lượng qua CoreAudio → hiện HUD của ta,
///   HUD hệ thống vẫn hiện song song. Không cần quyền gì.
/// - **Thay thế** (`setIntercepting(true)`): bắt phím media bằng CGEventTap, tự chỉnh
///   rồi nuốt phím → chỉ còn HUD của ta. Cần quyền Trợ năng.
final class HUDService {
    /// Gọi trên main thread.
    var onEvent: ((HUDEvent) -> Void)?

    /// Cho phép điều khiển đèn nền bàn phím (thử nghiệm). Tắt → không chặn phím đèn nền.
    var keyboardControlEnabled = true

    private let volume = VolumeController()
    private let brightness = BrightnessController()
    private let keyboard = KeyboardBacklightController()
    private let tap = MediaKeyTap()

    private var wantsIntercepting = false
    private var permissionTimer: Timer?

    private static let normalStep: Float = 1.0 / 16
    private static let fineStep: Float = 1.0 / 64

    func start() {
        volume.onChange = { [weak self] value, muted in
            self?.onEvent?(HUDEvent(kind: .volume, value: Double(value), isMuted: muted))
        }
        volume.startObserving()

        tap.handler = { [weak self] key, fine in
            self?.handle(key, fine: fine) ?? false
        }
    }

    deinit {
        permissionTimer?.invalidate()
        tap.stop()
        volume.stopObserving()
    }

    // MARK: - Đọc / đặt mức (cho thanh trượt điều khiển nhanh)

    func isSupported(_ kind: HUDEvent.Kind) -> Bool {
        switch kind {
        case .volume: return volume.isSupported
        case .brightness: return brightness.isSupported
        case .keyboard: return keyboardControlEnabled && keyboard.isSupported
        }
    }

    func level(of kind: HUDEvent.Kind) -> Double? {
        switch kind {
        case .volume:
            guard let current = volume.volume else { return nil }
            return volume.isMuted ? 0 : Double(current)
        case .brightness:
            guard let current = brightness.brightness else { return nil }
            return Double(current)
        case .keyboard: return keyboard.isSupported ? Double(keyboard.level) : nil
        }
    }

    func setLevel(_ value: Double, for kind: HUDEvent.Kind) {
        let clamped = Float(min(max(value, 0), 1))
        switch kind {
        case .volume:
            if volume.isMuted, clamped > 0 { volume.setMuted(false) }
            volume.setVolume(clamped)
        case .brightness:
            brightness.set(clamped)
        case .keyboard:
            keyboard.set(clamped)
        }
    }

    // MARK: - Chế độ thay thế

    func setIntercepting(_ enabled: Bool) {
        guard enabled != wantsIntercepting else { return }
        wantsIntercepting = enabled

        if !enabled {
            permissionTimer?.invalidate()
            permissionTimer = nil
            tap.stop()
            return
        }

        if tap.start() { return }

        // Chưa có quyền: im lặng kiểm tra định kỳ; được cấp lúc nào là tự bật lúc đó
        // (hộp thoại xin quyền do màn chào / Cài đặt gọi, không bật ở đây để khỏi hiện lặp).
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self, self.wantsIntercepting else { timer.invalidate(); return }
            if self.tap.start() {
                timer.invalidate()
                self.permissionTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    // MARK: - Xử lý phím (main thread)

    private func handle(_ key: MediaKey, fine: Bool) -> Bool {
        let step = fine ? Self.fineStep : Self.normalStep

        switch key {
        case .volumeUp, .volumeDown:
            guard volume.isSupported,
                  let result = volume.step(by: key == .volumeUp ? step : -step)
            else { return false }
            emitVolume(result)
            return true

        case .mute:
            guard volume.isSupported, let result = volume.toggleMute() else { return false }
            emitVolume(result)
            return true

        case .brightnessUp, .brightnessDown:
            guard brightness.isSupported,
                  let value = brightness.step(by: key == .brightnessUp ? step : -step)
            else { return false }
            onEvent?(HUDEvent(kind: .brightness, value: Double(value)))
            return true

        case .keyboardUp, .keyboardDown:
            guard keyboardControlEnabled, keyboard.isSupported,
                  let value = keyboard.step(by: key == .keyboardUp ? step : -step)
            else { return false }
            onEvent?(HUDEvent(kind: .keyboard, value: Double(value)))
            return true

        case .keyboardToggle:
            guard keyboardControlEnabled, keyboard.isSupported, let value = keyboard.toggle() else { return false }
            onEvent?(HUDEvent(kind: .keyboard, value: Double(value)))
            return true
        }
    }

    private func emitVolume(_ result: (volume: Float, isMuted: Bool)) {
        onEvent?(HUDEvent(kind: .volume, value: Double(result.volume), isMuted: result.isMuted))
    }
}

private typealias MediaKey = MediaKeyTap.Key
