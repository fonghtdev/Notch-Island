import AppKit
import ApplicationServices

/// Điều khiển app đang ghi âm (Voice Memos, QuickTime…) bằng cách bấm nút của chính app qua Trợ năng (Accessibility).
/// Cần cấp quyền Trợ năng cho NotchIsland (lần đầu hệ thống tự hỏi). Không có API công khai nào khác để
/// tạm dừng bản ghi của app khác.
enum RecorderControl {
    enum Action { case pauseResume, stop }
    enum Outcome: Equatable {
        case pressed(String)
        case notFound
        case needsPermission
    }

    private static let pauseNames = ["pause", "tạm dừng", "resume", "tiếp tục", "continue"]
    private static let stopNames = ["done", "xong", "stop", "dừng", "finish", "hoàn tất", "hoàn thành"]

    @discardableResult
    static func perform(_ action: Action, bundleID: String) -> Outcome {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return .needsPermission }

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return .notFound
        }
        let names = action == .pauseResume ? pauseNames : stopNames
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let button = findButton(in: root, names: names) else { return .notFound }
        let status = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
        return status == .success ? .pressed(button.name) : .notFound
    }

    // MARK: - Tìm nút

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func findButton(in root: AXUIElement, names: [String]) -> (element: AXUIElement, name: String)? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 600 {
            let (element, depth) = queue.removeFirst()
            visited += 1

            if (attribute(element, kAXRoleAttribute) as? String) == kAXButtonRole {
                let labels = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
                    .compactMap { attribute(element, $0) as? String }
                    .map { $0.lowercased() }
                for name in names where labels.contains(where: { $0 == name || $0.hasPrefix(name + " ") }) {
                    return (element, name)
                }
            }
            if depth < 9, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        return nil
    }
}
