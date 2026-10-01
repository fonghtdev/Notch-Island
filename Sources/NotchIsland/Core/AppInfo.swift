import AppKit

/// Thông tin về chính app: phiên bản, nơi phát hành, trang hỗ trợ.
/// Kho phát hành (`NIReleaseRepo`) được script build ghi vào Info.plist – không cần sửa code.
enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// "owner/name" của kho GitHub chứa các bản Release; rỗng nếu build cục bộ chưa cấu hình.
    static var releaseRepo: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "NIReleaseRepo") as? String ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var hasRepo: Bool { releaseRepo.contains("/") }

    /// Trang hỗ trợ: `NISupportURL` nếu có, không thì trang chủ của kho.
    static var supportURL: URL? {
        if let custom = Bundle.main.object(forInfoDictionaryKey: "NISupportURL") as? String,
           let url = URL(string: custom.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true {
            return url
        }
        return hasRepo ? URL(string: "https://github.com/\(releaseRepo)") : nil
    }

    /// Form báo lỗi GitHub điền sẵn nội dung + chẩn đoán: người dùng chỉ cần bấm "Submit new issue".
    @MainActor
    static func reportURL(message: String) -> URL? {
        guard hasRepo, var c = URLComponents(string: "https://github.com/\(releaseRepo)/issues/new") else { return nil }
        let first = message.split(separator: "\n").first.map(String.init) ?? ""
        c.queryItems = [
            URLQueryItem(name: "title", value: String(first.prefix(80))),
            URLQueryItem(name: "body", value: "\(message)\n\n---\n\(diagnostics())"),
        ]
        return c.url
    }

    static var releasesURL: URL? {
        hasRepo ? URL(string: "https://github.com/\(releaseRepo)/releases") : nil
    }

    /// Đoạn thông tin dán kèm khi báo lỗi.
    @MainActor
    static func diagnostics(extra: [String] = []) -> String {
        #if arch(arm64)
        let arch = "Apple Silicon (arm64)"
        #else
        let arch = "Intel (x86_64)"
        #endif
        var lines = [
            "NotchIsland \(version) (build \(build))",
            "macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(arch)",
            "Quyền Trợ năng: \(MediaKeyTap.hasPermission ? "đã cấp" : "chưa cấp")",
            "Vị trí app: \(Bundle.main.bundlePath)",
        ]
        lines.append(contentsOf: extra)
        return lines.joined(separator: "\n")
    }
}
