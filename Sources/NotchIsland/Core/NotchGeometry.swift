import AppKit

/// Vị trí & kích thước notch trên một màn hình.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let notchSize: CGSize
    let hasPhysicalNotch: Bool

    static let placeholder = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        notchSize: IslandMetrics.fakeNotchSize,
        hasPhysicalNotch: false
    )

    /// Đọc notch thật qua `safeAreaInsets` + `auxiliaryTop{Left,Right}Area` (macOS 12+).
    /// Nếu không có notch → tạo notch giả cao bằng thanh menu.
    static func measure(_ screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame

        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            return NotchGeometry(
                screenFrame: frame,
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasPhysicalNotch: true
            )
        }

        let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
        let height = menuBarHeight > 0 ? menuBarHeight : IslandMetrics.fakeNotchSize.height
        return NotchGeometry(
            screenFrame: frame,
            notchSize: CGSize(width: IslandMetrics.fakeNotchSize.width, height: height),
            hasPhysicalNotch: false
        )
    }

    /// `displayID` khác 0 và màn hình đó đang kết nối → dùng nó.
    /// Ngược lại (tự động): ưu tiên màn hình có notch thật (MacBook), không thì màn hình chính.
    static func preferredScreen(displayID: Int = 0) -> NSScreen? {
        if displayID != 0, let chosen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return chosen
        }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

extension NSScreen {
    /// `CGDirectDisplayID` của màn hình (0 nếu không đọc được).
    var displayID: Int {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}
