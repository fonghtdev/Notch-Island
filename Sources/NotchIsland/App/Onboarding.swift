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

    private static let versionKey = "lastLaunchedVersion"

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: versionKey)
        defaults.set(AppInfo.version, forKey: versionKey)

        guard !defaults.bool(forKey: doneKey) else {
            // Vừa cập nhật: bản ký ad-hoc có thể làm macOS quên quyền Trợ năng → nhắc cấp lại một lần.
            if let previous, previous != AppInfo.version, !MediaKeyTap.hasPermission {
                askAccessibility(intro: "NotchIsland vừa cập nhật lên \(AppInfo.version). macOS có thể đã quên quyền Trợ năng sau khi cập nhật.\n\n")
            }
            return
        }
        defaults.set(true, forKey: doneKey)

        // Mở cùng macOS: bật sẵn (người dùng vẫn tắt được trong Cài đặt).
        try? SMAppService.mainApp.register()

        guard !MediaKeyTap.hasPermission else { return }
        askAccessibility(intro: "NotchIsland đã được bật tự khởi động cùng macOS.\n\n")
    }

    private static func askAccessibility(intro: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cần quyền Trợ năng"
        alert.informativeText = intro + "Để thay HUD âm lượng / độ sáng mặc định của macOS, app cần quyền Trợ năng. Bấm \"Cấp quyền\", bật NotchIsland trong danh sách – app sẽ tự áp dụng ngay, không cần mở lại."
        alert.addButton(withTitle: "Cấp quyền")
        alert.addButton(withTitle: "Để sau")
        if alert.runModal() == .alertFirstButtonReturn {
            MediaKeyTap.requestPermission()
        }
    }

    /// macOS không có hộp thoại xin quyền Toàn bộ ổ đĩa: chỉ có thể giải thích rồi mở thẳng trang cấp quyền.
    /// Chỉ hỏi đúng một lần; `hasAccess` cũng là phép thử khiến macOS liệt kê app trong danh sách quyền.
    static func askFullDiskAccess() {
        let defaults = UserDefaults.standard
        guard !NotificationReader.hasAccess, !defaults.bool(forKey: "askedFullDiskAccess") else { return }
        defaults.set(true, forKey: "askedFullDiskAccess")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cần quyền Toàn bộ ổ đĩa"
        alert.informativeText = "Để đọc thông báo, hãy bật NotchIsland trong danh sách (bấm + nếu chưa thấy), rồi thoát và mở lại app."
        alert.addButton(withTitle: "Mở Cài đặt hệ thống")
        alert.addButton(withTitle: "Để sau")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
