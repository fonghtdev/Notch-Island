import AppKit
import SwiftUI

/// Cửa sổ Cài đặt. App chạy ở chế độ "accessory" (không icon Dock) nên phải tự kích hoạt app
/// để cửa sổ hiện lên phía trước.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings, onPreviewOnIsland: @escaping (HUDEvent) -> Void) {
        let host = NSHostingController(
            rootView: SettingsView(settings: settings, onPreviewOnIsland: onPreviewOnIsland)
        )
        window = NSWindow(contentViewController: host)
        window.title = "NotchIsland – Cài đặt"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
