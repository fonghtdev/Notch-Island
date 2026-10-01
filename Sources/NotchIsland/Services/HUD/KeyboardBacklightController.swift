import Foundation

/// Chỉnh đèn nền bàn phím của MacBook qua `KeyboardBrightnessClient` trong CoreBrightness.framework
/// (riêng tư, không có tài liệu). Mọi lời gọi đều kiểm tra lúc chạy: thiếu class / selector /
/// bàn phím không có đèn → `isSupported` = false và app không chặn phím đèn nền.
///
/// Lưu ý đã biết (THỬ NGHIỆM): trên Apple Silicon chỉ setter `setBrightness:fadeSpeed:commit:forKeyboard:`
/// có tác dụng; setter cũ `setBrightness:forKeyboard:` là no-op. Kiểu tham số được suy từ các dự án
/// mã nguồn mở khác, chưa kiểm chứng trên mọi đời máy.
final class KeyboardBacklightController {
    private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias GetBrightness = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetBrightness = @convention(c) (AnyObject, Selector, Float, Int32, Bool, UInt64) -> Bool

    private static let fadeMilliseconds: Int32 = 80

    private var client: NSObject?
    private var keyboardID: UInt64?
    private var getFunction: GetBrightness?
    private var setFunction: SetBrightness?
    private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
    private let setSelector = NSSelectorFromString("setBrightness:fadeSpeed:commit:forKeyboard:")

    /// Getter đôi khi trả -1 → tự theo dõi mức đã đặt để HUD vẫn đúng.
    private var cachedLevel: Float = 0.5
    private var lastNonZero: Float = 0.5

    init() {
        let path = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
        guard dlopen(path, RTLD_LAZY) != nil,
              let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type
        else { return }

        let client = type.init()
        let idsSelector = NSSelectorFromString("copyKeyboardBacklightIDs")
        guard client.responds(to: idsSelector),
              client.responds(to: setSelector),
              client.responds(to: getSelector)
        else { return }

        let copyIDs = unsafeBitCast(client.method(for: idsSelector), to: CopyIDs.self)
        guard let ids = copyIDs(client, idsSelector)?.takeRetainedValue(),
              let first = ids.firstObject as? NSNumber
        else { return }

        self.client = client
        self.keyboardID = first.uint64Value
        self.getFunction = unsafeBitCast(client.method(for: getSelector), to: GetBrightness.self)
        self.setFunction = unsafeBitCast(client.method(for: setSelector), to: SetBrightness.self)

        if let current = readLevel() {
            cachedLevel = current
            if current > 0.01 { lastNonZero = current }
        }
    }

    var isSupported: Bool {
        client != nil && keyboardID != nil && setFunction != nil
    }

    /// Mức hiện tại 0...1.
    var level: Float {
        if let value = readLevel() {
            cachedLevel = value
        }
        return cachedLevel
    }

    @discardableResult
    func set(_ newValue: Float) -> Bool {
        guard let client, let keyboardID, let setFunction else { return false }
        let value = min(max(newValue, 0), 1)
        guard setFunction(client, setSelector, value, Self.fadeMilliseconds, true, keyboardID) else { return false }
        cachedLevel = value
        if value > 0.01 { lastNonZero = value }
        return true
    }

    func step(by delta: Float) -> Float? {
        let target = min(max(level + delta, 0), 1)
        return set(target) ? target : nil
    }

    /// Đang sáng thì tắt, đang tắt thì bật lại mức gần nhất.
    func toggle() -> Float? {
        let target: Float = level > 0.01 ? 0 : lastNonZero
        return set(target) ? target : nil
    }

    private func readLevel() -> Float? {
        guard let client, let keyboardID, let getFunction else { return nil }
        let value = getFunction(client, getSelector, keyboardID)
        return value >= 0 && value <= 1 ? value : nil
    }
}
