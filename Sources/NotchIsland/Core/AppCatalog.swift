import AppKit
import SwiftUI

/// Tra tên / icon / màu của app theo bundle ID. Có cache, chỉ gọi trên main thread.
enum AppCatalog {
    private static var names: [String: String] = [:]
    private static var icons: [String: NSImage] = [:]

    static let knownAccents: [String: Color] = [
        "com.apple.Music": Color(red: 0.98, green: 0.26, blue: 0.36),
        "com.spotify.client": Color(red: 0.12, green: 0.84, blue: 0.38),
        "com.google.Chrome": Color(red: 1.0, green: 0.2, blue: 0.2),
        "com.apple.Safari": Color(red: 0.2, green: 0.6, blue: 1.0),
        "company.thebrowser.Browser": Color(red: 0.95, green: 0.35, blue: 0.55),
    ]

    /// Đưa tiến trình phụ về app chính: `com.google.Chrome.helper.Renderer` → `com.google.Chrome`,
    /// `com.apple.WebKit.GPU` → Safari. Hàm thuần, dùng được trên mọi luồng.
    static func normalize(_ bundleID: String) -> String {
        if bundleID.hasPrefix("com.apple.WebKit") { return "com.apple.Safari" }
        if let range = bundleID.range(of: ".helper", options: .caseInsensitive) {
            return String(bundleID[..<range.lowerBound])
        }
        return bundleID
    }

    static func accent(for bundleID: String) -> Color {
        knownAccents[bundleID] ?? Color(white: 0.9)
    }

    static func name(for bundleID: String) -> String {
        if let cached = names[bundleID] { return cached }
        var name = bundleID
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        }
        names[bundleID] = name
        return name
    }

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}
