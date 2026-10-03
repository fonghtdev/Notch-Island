import AppKit

/// Mở lại nguồn đang phát khi bấm vào island.
/// - Trình duyệt (Chrome, Brave, Edge, Arc, Safari…): tìm đúng tab (theo tiêu đề bài, rồi theo tên miền
///   YouTube/SoundCloud…), chuyển sang tab đó và đưa cửa sổ lên trước. Cần quyền Automation (hỏi lần đầu).
/// - App thường (Spotify, Music, Discord…): đưa app lên trước.
/// - Không tìm được tab / chưa cấp quyền: ít nhất cũng đưa trình duyệt lên trước.
enum SourceOpener {
    private static let queue = DispatchQueue(label: "notchisland.opener", qos: .userInitiated)

    private enum Dialect {
        case chromium, arc, safari

        init?(bundleID: String) {
            func matches(_ ids: [String]) -> Bool {
                ids.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
            }
            if matches(["com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
                        "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]) {
                self = .chromium
            } else if matches(["company.thebrowser.Browser"]) {
                self = .arc
            } else if matches(["com.apple.Safari"]) {
                self = .safari
            } else {
                return nil
            }
        }
    }

    /// Các trang phát nhạc/video: lượt tìm thứ hai khi không khớp tiêu đề.
    private static let mediaHosts = [
        "youtube.com", "youtu.be", "music.youtube.com", "soundcloud.com", "open.spotify.com",
        "music.apple.com", "twitch.tv", "netflix.com", "bandcamp.com",
    ]

    static func open(_ info: NowPlayingInfo) {
        let bundle = info.bundleIdentifier
        guard let dialect = Dialect(bundleID: bundle) else {
            activate(bundleID: bundle)
            return
        }
        queue.async {
            let source = makeScript(for: dialect, bundleID: bundle, title: info.title)
            if !run(source) {
                DispatchQueue.main.async { activate(bundleID: bundle) }
            }
        }
    }

    /// Đưa app lên trước (mở nếu chưa chạy).
    static func activate(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    // MARK: - AppleScript

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func makeScript(for dialect: Dialect, bundleID: String, title: String) -> String {
        let needle = escape(String(title.prefix(80)))
        let hostCondition = mediaHosts.map { "u contains \"\($0)\"" }.joined(separator: " or ")

        // Phần khác nhau giữa các trình duyệt: tên thuộc tính tiêu đề và cách chọn tab.
        let titleProperty: String
        let focus: String
        switch dialect {
        case .chromium:
            titleProperty = "title"
            focus = "set active tab index of w to i\n set index of w to 1\n activate"
        case .arc:
            titleProperty = "title"
            focus = "tell t to select\n activate"
        case .safari:
            titleProperty = "name"
            focus = "set current tab of w to t\n set index of w to 1\n activate"
        }

        let byTitle = title.isEmpty ? "" : """
        repeat with w in windows
            set i to 0
            repeat with t in tabs of w
                set i to i + 1
                if (\(titleProperty) of t) contains "\(needle)" then
                    \(focus)
                    return "hit"
                end if
            end repeat
        end repeat
        """

        return """
        tell application id "\(bundleID)"
            \(byTitle)
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    set u to URL of t
                    if \(hostCondition) then
                        \(focus)
                        return "hit"
                    end if
                end repeat
            end repeat
        end tell
        return "miss"
        """
    }

    /// true nếu đã chuyển được tới tab.
    private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("NotchIsland: AppleScript mở nguồn lỗi – \(error)")
            return false
        }
        return result.stringValue == "hit"
    }
}
