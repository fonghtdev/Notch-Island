import Foundation

/// Vị trí script perl + framework của mediaremote-adapter.
struct AdapterPaths {
    static let scriptName = "mediaremote-adapter.pl"
    static let frameworkName = "MediaRemoteAdapter.framework"

    let script: URL
    let framework: URL

    /// Tìm theo thứ tự:
    /// 1. Bên trong gói .app (Contents/Resources + Contents/Frameworks) – bản phát hành.
    /// 2. Biến môi trường `NOTCHISLAND_ADAPTER_DIR` – tuỳ chỉnh.
    /// 3. `Vendor/mediaremote-adapter` trong thư mục hiện tại – khi `swift run`.
    static func locate() -> AdapterPaths? {
        var candidates: [AdapterPaths] = []

        if let resources = Bundle.main.resourceURL, let frameworks = Bundle.main.privateFrameworksURL {
            candidates.append(AdapterPaths(
                script: resources.appendingPathComponent(scriptName),
                framework: frameworks.appendingPathComponent(frameworkName)
            ))
        }

        if let custom = ProcessInfo.processInfo.environment["NOTCHISLAND_ADAPTER_DIR"] {
            candidates.append(vendorLayout(URL(fileURLWithPath: custom)))
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        candidates.append(vendorLayout(cwd.appendingPathComponent("Vendor/mediaremote-adapter")))

        let fm = FileManager.default
        return candidates.first {
            fm.fileExists(atPath: $0.script.path) && fm.fileExists(atPath: $0.framework.path)
        }
    }

    /// Cấu trúc thư mục của repo adapter sau khi build bằng cmake.
    private static func vendorLayout(_ root: URL) -> AdapterPaths {
        AdapterPaths(
            script: root.appendingPathComponent("bin/\(scriptName)"),
            framework: root.appendingPathComponent("build/\(frameworkName)")
        )
    }
}
