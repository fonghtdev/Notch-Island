import AppKit
import SwiftUI

/// Cửa sổ Cài đặt. App chạy ở chế độ "accessory" (không icon Dock) nên phải tự kích hoạt app
/// để cửa sổ hiện lên phía trước.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(settings: AppSettings, updater: UpdateService, onPreviewOnIsland: @escaping (HUDEvent) -> Void) {
        let host = NSHostingController(
            rootView: SettingsView(settings: settings, onPreviewOnIsland: onPreviewOnIsland, updater: updater)
        )
        if #available(macOS 13.0, *) { host.sizingOptions = [] }
        window = NSWindow(contentViewController: host)
        window.title = "NotchIsland – Cài đặt"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.setContentSize(NSSize(width: 500, height: 700))
        window.contentMinSize = NSSize(width: 500, height: 460)
        window.contentMaxSize = NSSize(width: 500, height: 1000)
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
