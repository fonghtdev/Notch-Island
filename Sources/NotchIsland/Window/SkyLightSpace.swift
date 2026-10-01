import AppKit

/// Đưa cửa sổ lên TRÊN màn hình khoá (THỬ NGHIỆM, dùng API riêng tư của Apple).
///
/// Cách làm: tạo một "Space" riêng với tầng tuyệt đối rất cao rồi chuyển cửa sổ vào đó.
/// Nạp SkyLight bằng `dlopen` (như DisplayServices ở phần độ sáng): thiếu hàm nào thì `isAvailable = false`
/// và app vẫn chạy bình thường, chỉ là không hiện được trên màn hình khoá.
/// Apple có thể đổi/loại các hàm này ở bản macOS sau.
final class SkyLightSpace {
    static let shared = SkyLightSpace()

    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias CreateSpaceFn = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevelFn = @convention(c) (Int32, Int32, Int32) -> Void
    private typealias ShowSpacesFn = @convention(c) (Int32, CFArray) -> Void
    private typealias AddWindowsFn = @convention(c) (Int32, Int32, CFArray, Int32) -> Void

    private struct Operations {
        let connection: Int32
        let space: Int32
        let addWindows: AddWindowsFn
    }

    private let operations: Operations?

    var isAvailable: Bool { operations != nil }

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
              let createSymbol = dlsym(handle, "SLSSpaceCreate"),
              let levelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
              let showSymbol = dlsym(handle, "SLSShowSpaces"),
              let addSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            operations = nil
            return
        }

        let mainConnection = unsafeBitCast(connectionSymbol, to: ConnectionFn.self)
        let createSpace = unsafeBitCast(createSymbol, to: CreateSpaceFn.self)
        let setLevel = unsafeBitCast(levelSymbol, to: SetLevelFn.self)
        let showSpaces = unsafeBitCast(showSymbol, to: ShowSpacesFn.self)
        let addWindows = unsafeBitCast(addSymbol, to: AddWindowsFn.self)

        let connection = mainConnection()
        let space = createSpace(connection, 1, 0)
        setLevel(connection, space, 400)
        showSpaces(connection, [NSNumber(value: space)] as CFArray)
        operations = Operations(connection: connection, space: space, addWindows: addWindows)
    }

    /// Gọi SAU khi cửa sổ đã hiện (cần `windowNumber` hợp lệ). Trả về false nếu không dùng được.
    @discardableResult
    func attach(_ window: NSWindow) -> Bool {
        guard let operations, window.windowNumber > 0 else { return false }
        let windows = [NSNumber(value: Int32(window.windowNumber))] as CFArray
        operations.addWindows(operations.connection, operations.space, windows, 7)
        return true
    }
}
