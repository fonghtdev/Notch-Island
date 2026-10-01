import AppKit
import ServiceManagement

/// Lần chạy đầu tiên: tự bật "Mở cùng macOS" và xin quyền Trợ năng một lần duy nhất,
/// để người dùng không phải tự dò trong Cài đặt.
@MainActor
enum Onboarding {
    private static let doneKey = "didOnboard.v1"

    /// false nếu app đang chạy thẳng từ ổ DMG (chưa kéo vào Applications) và đã nhắc người dùng.
    static func ensureInstalledLocation() -> Bool {
        guard Bundle.main.bundlePath.hasPrefix("/Volumes/") else { return true }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Hãy kéo NotchIsland vào thư mục Applications"
        alert.informativeText = "Bạn đang mở app trực tiếp từ ổ cài đặt. Kéo NotchIsland vào Applications, eject ổ đĩa rồi mở lại từ đó để app giữ được quyền và tự khởi động cùng macOS."
        alert.addButton(withTitle: "Đóng")
        alert.runModal()
        return false
    }

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defaults.set(true, forKey: doneKey)

        // Mở cùng macOS: bật sẵn (người dùng vẫn tắt được trong Cài đặt).
        try? SMAppService.mainApp.register()

        guard !MediaKeyTap.hasPermission else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Chào mừng đến với NotchIsland"
        alert.informativeText = "NotchIsland đã được bật tự khởi động cùng macOS.\n\nĐể thay HUD âm lượng / độ sáng mặc định của macOS, app cần quyền Trợ năng. Bấm \"Cấp quyền\", bật NotchIsland trong danh sách – app sẽ tự áp dụng ngay, không cần mở lại."
        alert.addButton(withTitle: "Cấp quyền")
        alert.addButton(withTitle: "Để sau")
        if alert.runModal() == .alertFirstButtonReturn {
            MediaKeyTap.requestPermission()
        }
    }
}
