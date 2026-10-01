import AppKit

/// Điểm vào của app. Chạy dạng "agent" (không có icon Dock, không có cửa sổ chính).
@main
enum NotchIslandEntry {
    @MainActor private static var delegate: AppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}
