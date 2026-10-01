import AppKit
import ApplicationServices

/// Bắt phím âm lượng / độ sáng (phím "media" kiểu NX_SYSDEFINED) bằng CGEventTap.
/// Nếu handler trả về `true`, sự kiện bị nuốt → HUD mặc định của macOS không hiện.
/// Cần quyền Trợ năng (Accessibility).
final class MediaKeyTap {
    enum Key {
        case volumeUp, volumeDown, mute, brightnessUp, brightnessDown
        case keyboardUp, keyboardDown, keyboardToggle
    }

    /// (phím, có giữ Shift+Option không) → đã xử lý (nuốt sự kiện) hay chưa.
    var handler: ((Key, _ fine: Bool) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Tap riêng cho phím tắt bàn phím (fn+1 / fn+2). Tách riêng để nếu macOS đòi thêm quyền Giám sát đầu vào
    /// mà người dùng chưa cấp thì phần phím media (âm lượng, độ sáng) vẫn chạy bình thường.
    private var keyTap: CFMachPort?
    private var keyRunLoopSource: CFRunLoopSource?
    private var consumedShortcutCodes: Set<Int> = []

    /// Bật / tắt phím tắt (Cài đặt).
    var shortcutEnabled = true

    /// fn+1 giảm, fn+2 tăng đèn bàn phím (mã phím ANSI '1' = 18, '2' = 19).
    /// Chọn phím số vì macOS và hầu hết app không gán fn+số cho việc gì (khác F1/F2 mà nhiều app dùng).
    private static let shortcutMap: [Int: Key] = [
        18: .keyboardDown,
        19: .keyboardUp,
    ]
    /// Phím đã nuốt lúc nhấn xuống → phải nuốt cả lúc nhả, không thì hệ thống nhận lẻ.
    private var consumedKeyCodes: Set<Int> = []

    // Mã phím trong IOKit/hidsystem/ev_keymap.h
    private static let keyMap: [Int: Key] = [
        0: .volumeUp,
        1: .volumeDown,
        7: .mute,
        2: .brightnessUp,
        3: .brightnessDown,
        21: .keyboardUp,      // NX_KEYTYPE_ILLUMINATION_UP
        22: .keyboardDown,    // NX_KEYTYPE_ILLUMINATION_DOWN
        23: .keyboardToggle,  // NX_KEYTYPE_ILLUMINATION_TOGGLE
    ]

    private static let systemDefinedType: UInt32 = 14   // NX_SYSDEFINED
    private static let auxControlSubtype: Int16 = 8     // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    /// Đặt biến môi trường `NOTCHISLAND_DEBUG_KEYS=1` để ghi log mã mọi phím media
    /// (hữu ích khi một phím không phản hồi trên bàn phím của bạn).
    private static let debugKeys = ProcessInfo.processInfo.environment["NOTCHISLAND_DEBUG_KEYS"] == "1"

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Hiện hộp thoại xin quyền Trợ năng của macOS (nếu chưa có).
    static func requestPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    var isRunning: Bool { tap != nil }

    /// false nếu chưa có quyền hoặc hệ thống từ chối tạo tap.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        guard Self.hasPermission else { return false }

        let mask: CGEventMask = 1 << CGEventMask(Self.systemDefinedType)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        startShortcutTap()
        return true
    }

    private func startShortcutTap() {
        guard keyTap == nil else { return }
        let mask: CGEventMask = (1 << CGEventMask(CGEventType.keyDown.rawValue)) | (1 << CGEventMask(CGEventType.keyUp.rawValue))
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handleShortcut(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        keyTap = port
        keyRunLoopSource = source
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: false) }
        if let keyRunLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyRunLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        keyTap = nil
        keyRunLoopSource = nil
        consumedKeyCodes.removeAll()
        consumedShortcutCodes.removeAll()
    }

    deinit {
        stop()
    }

    // MARK: - Xử lý sự kiện (chạy trên main run loop)

    /// fn+1 / fn+2 (không kèm ⌘ ⌃ ⌥ ⇧) → đèn bàn phím giảm / tăng. Không chỉnh được (máy không có đèn) thì trả phím về cho hệ thống.
    fileprivate func handleShortcut(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }

        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let key = Self.shortcutMap[code] else { return Unmanaged.passUnretained(event) }

        // Nhả phím: nuốt nếu lúc nhấn đã nuốt (fn có thể đã nhả trước).
        if type == .keyUp {
            return consumedShortcutCodes.remove(code) != nil ? nil : Unmanaged.passUnretained(event)
        }

        guard shortcutEnabled else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        guard flags.contains(.maskSecondaryFn),
              flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        else { return Unmanaged.passUnretained(event) }

        if handler?(key, false) == true {
            consumedShortcutCodes.insert(code)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Hệ thống tự tắt tap nếu callback chậm → bật lại.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard type.rawValue == Self.systemDefinedType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxControlSubtype
        else { return Unmanaged.passUnretained(event) }

        let data = nsEvent.data1
        let keyCode = (data & 0xFFFF_0000) >> 16
        let flags = data & 0x0000_FFFF
        let isKeyDown = ((flags & 0xFF00) >> 8) == 0xA

        if Self.debugKeys {
            NSLog("NotchIsland[keys]: keyCode=\(keyCode) down=\(isKeyDown) flags=\(String(flags, radix: 16))")
        }

        guard let key = Self.keyMap[keyCode] else { return Unmanaged.passUnretained(event) }

        if isKeyDown {
            let fine = nsEvent.modifierFlags.isSuperset(of: [.shift, .option])
            if handler?(key, fine) == true {
                consumedKeyCodes.insert(keyCode)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        if consumedKeyCodes.remove(keyCode) != nil { return nil }
        return Unmanaged.passUnretained(event)
    }
}
