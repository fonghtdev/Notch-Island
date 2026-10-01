import AppKit
import ApplicationServices

/// Đọc và điều khiển cuộc gọi của app khác qua Trợ năng (Accessibility): tên người đang gọi (tiêu đề cửa sổ),
/// đồng hồ thời gian gọi do chính app hiển thị, trạng thái tắt mic / tắt tiếng, và bấm nút tắt mic / tắt tiếng / kết thúc.
/// Không có API công khai nào khác; app nào không hiện nút ra cây Trợ năng thì chỉ có tên + thời gian suy ra từ micro.
enum CallControl {
    enum Action { case mute, deafen, end }

    /// Kết quả một lần quét cửa sổ của app đang gọi.
    struct Snapshot: Equatable {
        /// Tiêu đề cửa sổ của app chính / của tiến trình phụ (vd. cửa sổ cuộc gọi của ZaloCall).
        var windowTitles: [String] = []
        var helperTitles: [String] = []
        /// Mọi nhãn dạng "mm:ss" / "h:mm:ss" trong cửa sổ app (có thể lẫn giờ của tin nhắn → xem `CaptureMonitor.ingest`).
        var durations: [TimeInterval] = []
        var sampledAt = Date()
        /// nil = app không có nút đó (hoặc không đọc được).
        var muted: Bool?
        var deafened: Bool?
        var canEnd = false
        /// Mọi nút đọc được, để chẩn đoán.
        var labels: [String] = []
    }

    // Nhãn nút (chữ thường). Khớp khi bằng hẳn, hoặc bắt đầu bằng tên + khoảng trắng (trừ nhóm `exactOnly`).
    private static let muteNames = [
        "mute", "unmute", "mute microphone", "unmute microphone", "turn off microphone", "turn on microphone",
        "mute mic", "unmute mic", "microphone", "tắt tiếng", "bật tiếng", "tắt mic", "bật mic",
        "tắt micro", "bật micro", "tắt microphone", "bật microphone",
    ]
    /// Đang tắt mic khi nút đề nghị "bật lại".
    private static let unmuteHints = ["unmute", "turn on", "bật", "microphone off", "muted"]
    private static let deafenNames = ["deafen", "undeafen", "tắt âm thanh", "bật âm thanh"]
    private static let undeafenHints = ["undeafen", "bật âm thanh", "deafened"]
    private static let endNames = [
        "disconnect", "leave call", "end call", "hang up", "hangup", "leave meeting", "end meeting",
        "kết thúc cuộc gọi", "kết thúc", "ngắt kết nối", "rời cuộc gọi", "rời cuộc họp", "cúp máy", "tắt máy",
        "end", "leave", "rời",
    ]
    /// Discord dịch "Mute" = "Tắt âm" (mic) và "Deafen" = "Tắt tiếng" (loa) – ngược với các app khác.
    private static let discordMuteNames = ["mute", "unmute", "tắt âm", "bật âm"]
    private static let discordDeafenNames = ["deafen", "undeafen", "tắt tiếng", "bật tiếng"]
    private static let discordBundle = "com.hnc.Discord"
    private static let exactOnly: Set<String> = ["end", "leave", "rời", "mute", "unmute", "microphone"]

    private static let durationPattern = try! NSRegularExpression(pattern: #"^\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\s*$"#)

    // MARK: - Tiến trình của một app

    /// App chính + mọi tiến trình phụ cùng họ bundle (vd. `com.vng.zalo` + `com.vng.zalo.zalocall`:
    /// cửa sổ cuộc gọi của Zalo nằm ở tiến trình ZaloCall).
    static func pids(for bundleID: String) -> [pid_t] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard let id = app.bundleIdentifier else { return false }
                return id == bundleID || id.hasPrefix(bundleID + ".")
            }
            .map(\.processIdentifier)
    }

    private static func matches(_ label: String, _ names: [String]) -> Bool {
        names.contains { name in
            label == name || (!exactOnly.contains(name) && label.hasPrefix(name + " "))
        }
    }

    private static func labels(of element: AXUIElement) -> [String] {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute, kAXValueAttribute]
            .compactMap { RecorderControl.attribute(element, $0) as? String }
            .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isControl(_ role: String?) -> Bool {
        role == kAXButtonRole || role == kAXCheckBoxRole || role == kAXMenuButtonRole
            || role == kAXRadioButtonRole || role == kAXPopUpButtonRole
    }

    // MARK: - Duyệt cây Trợ năng

    private struct Hit {
        var element: AXUIElement
        var labels: [String]
        /// Với ô đánh dấu (Discord): giá trị 1 = đang bật chế độ tắt mic / tắt tiếng.
        var checked: Bool?
    }

    private struct Walk {
        var titles: [String] = []
        var helperTitles: [String] = []
        var texts: [String] = []
        var mute: Hit?
        var deafen: Hit?
        var end: Hit?
        var all: [String] = []
    }

    /// `deep` = false: chỉ lấy tiêu đề cửa sổ (trình duyệt: không ép dựng cây Trợ năng của cả trang web).
    private static func walk(bundleID: String, deep: Bool = true) -> Walk {
        var result = Walk()
        let muteSet = bundleID == discordBundle ? discordMuteNames : muteNames
        let deafenSet = bundleID == discordBundle ? discordDeafenNames : deafenNames
        for pid in pids(for: bundleID) {
            let isMain = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID
            let app = AXUIElementCreateApplication(pid)
            // Electron (Discord, Zalo, Teams…) chỉ dựng cây Trợ năng khi được yêu cầu.
            if deep { AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue) }
            guard let windows = RecorderControl.attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }

            for window in windows {
                if let title = RecorderControl.attribute(window, kAXTitleAttribute) as? String, !title.isEmpty {
                    if isMain { result.titles.append(title) } else { result.helperTitles.append(title) }
                }
                guard deep else { continue }
                // Cây của Electron rất sâu (nút tắt mic của Discord ở tầng ~18): duyệt rộng, có trần số nút.
                var queue: [(AXUIElement, Int)] = [(window, 0)]
                var head = 0
                while head < queue.count, head < 3500 {
                    let (element, depth) = queue[head]
                    head += 1
                    let role = RecorderControl.attribute(element, kAXRoleAttribute) as? String

                    if role == kAXStaticTextRole {
                        if let text = RecorderControl.attribute(element, kAXValueAttribute) as? String { result.texts.append(text) }
                    } else if isControl(role) {
                        let found = labels(of: element)
                        if let first = found.first, result.all.count < 60 { result.all.append("\(role ?? "?"): \(first)") }
                        let checked = (RecorderControl.attribute(element, kAXValueAttribute) as? NSNumber).map { $0.intValue == 1 }
                        let hit = Hit(element: element, labels: found, checked: role == kAXCheckBoxRole ? checked : nil)
                        if result.mute == nil, found.contains(where: { matches($0, muteSet) }) {
                            result.mute = hit
                        } else if result.deafen == nil, found.contains(where: { matches($0, deafenSet) }) {
                            result.deafen = hit
                        } else if result.end == nil, found.contains(where: { matches($0, endNames) }) {
                            result.end = hit
                        }
                    }
                    if depth < 40, let children = RecorderControl.attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                        queue.append(contentsOf: children.map { ($0, depth + 1) })
                    }
                }
            }
        }
        return result
    }

    private static func parseDurations(_ texts: [String]) -> [TimeInterval] {
        var result: [TimeInterval] = []
        for text in texts where result.count < 12 {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = durationPattern.firstMatch(in: text, range: range) else { continue }
            func part(_ i: Int) -> Double {
                Range(match.range(at: i), in: text).flatMap { Double(text[$0]) } ?? 0
            }
            result.append(part(1) * 3600 + part(2) * 60 + part(3))
        }
        return result
    }

    private static func isDown(_ hit: Hit, hints: [String]) -> Bool {
        if let checked = hit.checked { return checked }
        return hit.labels.contains { label in hints.contains { label.hasPrefix($0) || label.contains($0) } }
    }

    /// Quét cửa sổ app gọi (chạy ở luồng nền: cây của Electron có thể chậm).
    static func snapshot(bundleID: String, deep: Bool = true) -> Snapshot {
        guard AXIsProcessTrusted() else { return Snapshot() }
        let sampledAt = Date()
        let found = walk(bundleID: bundleID, deep: deep)
        var snapshot = Snapshot(windowTitles: found.titles, helperTitles: found.helperTitles, durations: parseDurations(found.texts), sampledAt: sampledAt, labels: found.all)
        snapshot.muted = found.mute.map { isDown($0, hints: unmuteHints) }
        snapshot.deafened = found.deafen.map { isDown($0, hints: undeafenHints) }
        snapshot.canEnd = found.end != nil
        return snapshot
    }

    /// Bấm nút tương ứng của app. false nếu không có quyền hoặc app không có nút đó.
    @discardableResult
    static func perform(_ action: Action, bundleID: String) -> Bool {
        // Chưa có quyền Trợ năng: hiện hộp thoại xin quyền của macOS.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return false }
        let found = walk(bundleID: bundleID)
        let hit: Hit?
        switch action {
        case .mute: hit = found.mute
        case .deafen: hit = found.deafen
        case .end: hit = found.end
        }
        guard let hit else { return false }
        return AXUIElementPerformAction(hit.element, kAXPressAction as CFString) == .success
    }
}
