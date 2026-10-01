import AppKit
import CoreGraphics

/// Chỉnh độ sáng màn hình tích hợp của MacBook.
///
/// macOS không có API công khai cho việc này, nên ta nạp `DisplayServices.framework`
/// (riêng tư) lúc chạy bằng dlopen. Nếu Apple đổi/xoá nó, hoặc Mac không có màn hình
/// tích hợp, `isSupported` = false và app không chặn phím độ sáng.
final class BrightnessController {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32

    private let getFunction: GetBrightness?
    private let setFunction: SetBrightness?

    init() {
        let path = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
        let handle = dlopen(path, RTLD_LAZY)
        getFunction = handle
            .flatMap { dlsym($0, "DisplayServicesGetBrightness") }
            .map { unsafeBitCast($0, to: GetBrightness.self) }
        setFunction = handle
            .flatMap { dlsym($0, "DisplayServicesSetBrightness") }
            .map { unsafeBitCast($0, to: SetBrightness.self) }
    }

    var isSupported: Bool {
        getFunction != nil && setFunction != nil && builtInDisplay != nil
    }

    var brightness: Float? {
        guard let getFunction, let display = builtInDisplay else { return nil }
        var value: Float = 0
        return getFunction(display, &value) == 0 ? value : nil
    }

    /// Tăng/giảm độ sáng, trả về giá trị mới (nil nếu không chỉnh được).
    func step(by delta: Float) -> Float? {
        guard let current = brightness else { return nil }
        let target = min(max(current + delta, 0), 1)
        return set(target) ? target : nil
    }

    @discardableResult
    func set(_ value: Float) -> Bool {
        guard let setFunction, let display = builtInDisplay else { return false }
        return setFunction(display, min(max(value, 0), 1)) == 0
    }

    private var builtInDisplay: CGDirectDisplayID? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let id = CGDirectDisplayID(number.uint32Value)
            if CGDisplayIsBuiltin(id) != 0 { return id }
        }
        return nil
    }
}
