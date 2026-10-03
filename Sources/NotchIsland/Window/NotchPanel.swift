import AppKit
import SwiftUI

/// Cửa sổ trong suốt, không viền, nằm trên cả thanh menu, có mặt ở mọi Space
/// và cả khi app khác đang full-screen.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        // Mặc định cho click xuyên qua; chỉ bắt chuột khi con trỏ nằm trên island.
        ignoresMouseEvents = true

        // Đặt tầng CUỐI CÙNG và KHÔNG bật `isFloatingPanel`: thuộc tính đó tự ghi đè `level`
        // về tầng "floating" (thấp hơn thanh menu) → chữ menu (Help, Window…) vẽ đè lên island.
        // mainMenu + 3: nằm trên chữ thanh menu nhưng vẫn dưới menu thả xuống / popup.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Mặc định AppKit đẩy cửa sổ xuống dưới thanh menu. Trả nguyên frame để
    /// Island được đặt sát mép trên màn hình, đè lên vùng notch/camera.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Nhận click ngay lần đầu dù app không active (không cần click 2 lần).
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
