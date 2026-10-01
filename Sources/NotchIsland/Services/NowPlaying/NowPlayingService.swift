import Foundation

/// Chọn provider tốt nhất và tự chuyển sang dự phòng khi provider chính hỏng.
///
///   MediaRemoteAdapterProvider  ──(lỗi / không tìm thấy adapter)──▶  DistributedNotificationProvider
final class NowPlayingService {
    var onChange: ((NowPlayingInfo?) -> Void)?
    /// Báo tên provider đang dùng (hiện trong menu bar).
    var onProviderChange: ((String) -> Void)?

    private var active: NowPlayingProvider?

    var providerName: String { active?.name ?? "—" }

    func start() {
        if let paths = AdapterPaths.locate() {
            use(MediaRemoteAdapterProvider(paths: paths))
        } else {
            NSLog("NotchIsland: không tìm thấy mediaremote-adapter → dùng nguồn dự phòng")
            use(DistributedNotificationProvider())
        }
    }

    func send(_ command: MediaCommand) {
        active?.send(command)
    }

    func seek(to seconds: TimeInterval) {
        active?.seek(to: seconds)
    }

    /// Báo cáo chẩn đoán: adapter có được tìm thấy không, nguồn đang dùng, và kết quả lệnh `get` thực tế.
    /// `completion` luôn được gọi trên main thread.
    func diagnose(completion: @escaping (String) -> Void) {
        var report = """
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Nguồn đang dùng: \(providerName)
        Thư mục chạy: \(FileManager.default.currentDirectoryPath)

        """

        guard let paths = AdapterPaths.locate() else {
            report += """
            Adapter: KHÔNG TÌM THẤY → đang dùng nguồn dự phòng (chỉ Music/Spotify, không có YouTube).
            Cách sửa: chạy ./scripts/fetch-adapter.sh, rồi chạy `swift run` từ thư mục gốc dự án (nơi có thư mục Vendor/).
            """
            completion(report)
            return
        }

        report += "Adapter: đã tìm thấy\n  script: \(paths.script.path)\n  framework: \(paths.framework.path)\n"
        if let active {
            report += "\n" + active.diagnostics + "\n"
        }

        let header = report
        DispatchQueue.global(qos: .userInitiated).async {
            let output = Self.runGet(paths: paths)
            DispatchQueue.main.async {
                completion(header + "\n--- perl … get --no-artwork ---\n" + output)
            }
        }
    }

    /// Chạy `get` một lần (tối đa 6 giây) và trả về stdout + stderr + mã thoát.
    private static func runGet(paths: AdapterPaths) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script.path, paths.framework.path, "get", "--no-artwork"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return "Không chạy được perl: \(error.localizedDescription)"
        }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { text = "(không có đầu ra)" }
        if text.count > 1500 { text = String(text.prefix(1500)) + "…" }
        return "\(text)\n(mã thoát: \(process.terminationStatus))"
    }

    private func use(_ provider: NowPlayingProvider) {
        active?.stop()
        active = provider

        provider.onChange = { [weak self] info in
            self?.onChange?(info)
        }
        provider.onFailure = { [weak self, weak provider] in
            guard let self, let provider, provider === self.active,
                  !(provider is DistributedNotificationProvider)
            else { return }
            NSLog("NotchIsland: \(provider.name) lỗi → chuyển sang nguồn dự phòng")
            self.onChange?(nil)
            self.use(DistributedNotificationProvider())
        }

        provider.start()
        onProviderChange?(provider.name)
    }
}
