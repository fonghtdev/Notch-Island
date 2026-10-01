import AppKit

/// Tự cập nhật không cần framework ngoài: hỏi GitHub Releases bản mới nhất, tải DMG,
/// chép app mới đè lên app cũ rồi mở lại. Tải bằng URLSession nên file không bị gắn cờ
/// quarantine → bản mới mở lên không gặp lại cảnh báo Gatekeeper.
@MainActor
final class UpdateService: NSObject, ObservableObject {
    struct Release: Equatable {
        let version: String
        let notes: String
        let dmgURL: URL
        let pageURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private let settings: AppSettings
    private var timer: Timer?
    private var session: URLSession?
    private var pendingRelease: Release?

    private enum Key {
        static let lastCheck = "lastUpdateCheck"
        static let lastPrompted = "lastPromptedUpdateVersion"
    }

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    // MARK: - Lịch tự kiểm tra

    /// Gọi một lần lúc app khởi động: kiểm tra sau ít giây, rồi lặp lại mỗi 6 giờ (chỉ khi bật tự kiểm tra).
    func startAutomaticChecks() {
        guard AppInfo.hasRepo else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20 * 1_000_000_000)
            await self?.automaticCheck()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.automaticCheck() }
        }
    }

    private func automaticCheck() async {
        guard settings.autoCheckUpdates else { return }
        let last = UserDefaults.standard.double(forKey: Key.lastCheck)
        guard Date().timeIntervalSince1970 - last > 5 * 3600 else { return }
        await check(userInitiated: false)
    }

    // MARK: - Kiểm tra

    var availableRelease: Release? {
        if case .available(let release) = state { return release }
        return nil
    }

    /// `userInitiated`: người dùng bấm tay → luôn báo kết quả; tự động → chỉ nhắc khi có bản mới (một lần cho mỗi phiên bản).
    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        guard AppInfo.hasRepo else {
            state = .failed("Bản build này chưa cấu hình kho phát hành nên không kiểm tra được.")
            return
        }
        state = .checking
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Key.lastCheck)

        do {
            let release = try await fetchLatest()
            if Self.isNewer(release.version, than: AppInfo.version) {
                state = .available(release)
                if userInitiated || UserDefaults.standard.string(forKey: Key.lastPrompted) != release.version {
                    UserDefaults.standard.set(release.version, forKey: Key.lastPrompted)
                    promptToInstall(release)
                }
            } else {
                state = .upToDate
            }
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    private func fetchLatest() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(AppInfo.releaseRepo)/releases/latest") else {
            throw UpdateError.message("Địa chỉ kho không hợp lệ.")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("NotchIsland/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 404 {
                throw UpdateError.message("Chưa có bản phát hành nào (hoặc kho đang để riêng tư).")
            }
            throw UpdateError.message("GitHub trả về lỗi \(http.statusCode).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw UpdateError.message("Không đọc được thông tin phiên bản.")
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        guard let link = dmg?["browser_download_url"] as? String, let dmgURL = URL(string: link) else {
            throw UpdateError.message("Bản phát hành mới chưa có file DMG.")
        }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        let notes = (json["body"] as? String) ?? ""
        return Release(version: Self.normalize(tag), notes: Self.shortNotes(notes), dmgURL: dmgURL, pageURL: page)
    }

    // MARK: - So sánh phiên bản

    private static func normalize(_ tag: String) -> String {
        var text = tag.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        return text
    }

    private static func components(_ version: String) -> [Int] {
        let core = version.split(separator: "-").first.map(String.init) ?? version
        return core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Ghi chú phát hành: bỏ dòng "Full Changelog" tự sinh và cắt gọn để vừa hộp thoại.
    private static func shortNotes(_ body: String) -> String {
        let lines = body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().contains("full changelog") && !$0.hasPrefix("## What") }
        let joined = lines.prefix(8).joined(separator: "\n")
        return joined.count > 600 ? String(joined.prefix(600)) + "…" : joined
    }

    // MARK: - Hỏi người dùng

    private func promptToInstall(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Có NotchIsland \(release.version) mới"
        alert.informativeText = "Bạn đang dùng \(AppInfo.version)." + (release.notes.isEmpty ? "" : "\n\n\(release.notes)")
        alert.addButton(withTitle: "Cập nhật & khởi động lại")
        alert.addButton(withTitle: "Để sau")
        if release.pageURL != nil { alert.addButton(withTitle: "Xem chi tiết") }
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install()
        case .alertThirdButtonReturn:
            if let page = release.pageURL { NSWorkspace.shared.open(page) }
        default:
            break
        }
    }

    // MARK: - Tải + cài

    func install() {
        guard let release = availableRelease else { return }
        // Chạy bằng `swift run` (không phải .app) hoặc thư mục không ghi được → mở DMG cho người dùng tự kéo thả.
        let bundle = Bundle.main.bundleURL
        let parent = bundle.deletingLastPathComponent().path
        guard bundle.pathExtension == "app", FileManager.default.isWritableFile(atPath: parent) else {
            NSWorkspace.shared.open(release.dmgURL)
            state = .failed("Không tự ghi đè được vào \(parent) – đã mở trang tải, hãy kéo bản mới vào Applications.")
            return
        }
        pendingRelease = release
        state = .downloading(0)

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: release.dmgURL).resume()
    }

    fileprivate func downloadFinished(at file: URL) {
        state = .installing
        let bundle = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        Task.detached(priority: .userInitiated) {
            do {
                let staged = try Self.stageApp(fromDMG: file, expectedBundleID: bundleID)
                try Self.launchSwapScript(newApp: staged, destination: bundle, pid: pid)
                await MainActor.run { NSApp.terminate(nil) }
            } catch {
                await MainActor.run { [weak self] in
                    self?.state = .failed(error.localizedDescription)
                }
            }
        }
    }

    fileprivate func downloadFailed(_ message: String) {
        state = .failed(message)
    }

    fileprivate func downloadProgress(_ fraction: Double) {
        if case .downloading = state { state = .downloading(fraction) }
    }

    /// Mở DMG, chép .app ra thư mục tạm, kiểm tra đúng bundle id rồi đẩy DMG ra.
    private nonisolated static func stageApp(fromDMG dmg: URL, expectedBundleID: String) throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIslandUpdate-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mnt")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path, dmg.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

        let items = try FileManager.default.contentsOfDirectory(atPath: mount.path)
        guard let appName = items.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.message("File cập nhật không chứa app.")
        }
        let source = mount.appendingPathComponent(appName)
        guard Bundle(url: source)?.bundleIdentifier == expectedBundleID else {
            throw UpdateError.message("File cập nhật không đúng của NotchIsland.")
        }
        let staged = work.appendingPathComponent("NotchIsland.app")
        try run("/usr/bin/ditto", [source.path, staged.path])
        try? FileManager.default.removeItem(at: dmg)
        return staged
    }

    /// Script chạy tách rời: đợi app thoát → thay bản cũ bằng bản mới (giữ bản cũ để khôi phục nếu lỗi) → mở lại.
    private nonisolated static func launchSwapScript(newApp: URL, destination: URL, pid: Int32) throws {
        let script = """
        #!/bin/sh
        PID="$1"; NEW="$2"; DEST="$3"; OLD="$DEST.old"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        rm -rf "$OLD"
        if mv "$DEST" "$OLD" && /usr/bin/ditto "$NEW" "$DEST"; then
            /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
            rm -rf "$OLD" "$(dirname "$NEW")"
        else
            rm -rf "$DEST"; mv "$OLD" "$DEST"
        fi
        /usr/bin/open "$DEST"
        """
        let file = newApp.deletingLastPathComponent().appendingPathComponent("swap.sh")
        try script.write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [file.path, String(pid), newApp.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    @discardableResult
    private nonisolated static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.message("Lệnh \((tool as NSString).lastPathComponent) thất bại (\(process.terminationStatus)).")
        }
        return process.terminationStatus
    }
}

private enum UpdateError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

extension UpdateService: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.downloadProgress(fraction) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // File tạm bị xoá ngay khi hàm này trả về → phải chuyển đi ngay.
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("NotchIsland-\(UUID().uuidString).dmg")
        do {
            try FileManager.default.moveItem(at: location, to: target)
            Task { @MainActor in self.downloadFinished(at: target) }
        } catch {
            Task { @MainActor in self.downloadFailed("Không lưu được file tải về.") }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        Task { @MainActor in self.downloadFailed("Tải thất bại: \(error.localizedDescription)") }
    }
}
