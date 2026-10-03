import AppKit
import ServiceManagement

/// Gỡ sạch NotchIsland: mục khởi động cùng macOS, cài đặt, cache, file tạm, quyền đã cấp, rồi chuyển app vào Thùng rác.
@MainActor
enum Uninstaller {
    /// AppDelegate gắn vào: hiện lời cảm ơn trên island.
    static var showFarewell: (() -> Void)?

    static func confirmAndRun() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Gỡ NotchIsland khỏi máy?"
        alert.informativeText = "Sẽ xoá toàn bộ cài đặt, dữ liệu tạm, quyền đã cấp (Trợ năng, Toàn bộ ổ đĩa), tắt mở cùng macOS và chuyển app vào Thùng rác. Không thể hoàn tác."
        alert.addButton(withTitle: "Gỡ cài đặt")
        alert.addButton(withTitle: "Huỷ")
        alert.buttons[0].hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run()
    }

    private static func run() {
        let fm = FileManager.default
        let id = Bundle.main.bundleIdentifier ?? "dev.fong.notchisland"
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")

        try? SMAppService.mainApp.unregister()
        // Bản `swift run` không có bundle id: UserDefaults dùng tên tiến trình làm domain.
        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        UserDefaults.standard.removePersistentDomain(forName: domain)

        for path in ["Application Support/NotchIsland", "Caches/\(id)", "HTTPStorages/\(id)"] {
            try? fm.removeItem(at: library.appendingPathComponent(path))
        }
        try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent("notchisland-nc"))

        // Xoá quyền đã cấp cho app khỏi cơ sở dữ liệu TCC.
        let tcc = Process()
        tcc.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        tcc.arguments = ["reset", "All", id]
        try? tcc.run()
        tcc.waitUntilExit()

        // App đang chạy là gói .app thì chuyển vào Thùng rác (bản `swift run` không có gì để xoá).
        let bundle = Bundle.main.bundleURL
        var trashFailed = false
        if bundle.pathExtension == "app" {
            do { try fm.trashItem(at: bundle, resultingItemURL: nil) } catch { trashFailed = true }
        }

        // cfprefsd có thể ghi lại file plist lúc thoát → xoá lần nữa sau khi app đã tắt.
        let plist = library.appendingPathComponent("Preferences/\(domain).plist").path
        let cleanup = Process()
        cleanup.executableURL = URL(fileURLWithPath: "/bin/sh")
        cleanup.arguments = ["-c", "sleep 1; rm -f '\(plist)'"]
        try? cleanup.run()

        // Đóng cửa sổ Cài đặt, để island hiện lời cảm ơn rồi mới tắt hẳn.
        NSApp.windows.filter { $0.styleMask.contains(.titled) }.forEach { $0.close() }
        showFarewell?()
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandMetrics.farewellDuration + 0.6) {
            if trashFailed {
                let alert = NSAlert()
                alert.messageText = "Đã xoá dữ liệu, nhưng chưa xoá được app"
                alert.informativeText = "Hãy tự kéo NotchIsland.app vào Thùng rác."
                alert.runModal()
            }
            NSApp.terminate(nil)
        }
    }
}
