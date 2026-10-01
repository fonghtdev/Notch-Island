import Foundation

/// Nguồn chính: đọc bảng "Đang phát" của macOS qua mediaremote-adapter.
/// Nhận được MỌI nguồn phát: YouTube/SoundCloud trên Chrome, Safari, Arc…,
/// Music, Spotify, VLC, Podcasts… kèm ảnh bìa và vị trí phát.
///
/// Cơ chế: chạy `/usr/bin/perl mediaremote-adapter.pl <framework> stream`,
/// tiến trình này in ra mỗi dòng một JSON:
///   {"type":"data","diff":false,"payload":{"bundleIdentifier":…,"title":…}}
final class MediaRemoteAdapterProvider: NowPlayingProvider {
    let name = "MediaRemote (mọi nguồn)"
    var onChange: ((NowPlayingInfo?) -> Void)?
    var onFailure: (() -> Void)?

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    /// Tiến trình chết trong khoảng này sau khi khởi động → coi như adapter không dùng được.
    private static let minHealthyUptime: TimeInterval = 3
    private static let maxRestarts = 5

    private let paths: AdapterPaths
    private let parseQueue = DispatchQueue(label: "notchisland.adapter.parse")
    private let artwork = ArtworkProcessor()

    private var process: Process?
    private var buffer = Data()
    private var startedAt = Date()
    private var restarts = 0
    private var isStopping = false

    // Thông tin chẩn đoán (đọc/ghi từ nhiều luồng → khoá).
    private let statsLock = NSLock()
    private var lineCount = 0
    private var decodeFailures = 0
    private var lastLinePreview = "(chưa nhận dòng nào)"
    private var lastStderr = ""

    init(paths: AdapterPaths) {
        self.paths = paths
    }

    var diagnostics: String {
        statsLock.lock()
        defer { statsLock.unlock() }
        return """
        Đã nhận \(lineCount) dòng JSON, \(decodeFailures) dòng không đọc được, khởi động lại \(restarts) lần.
        Dòng gần nhất: \(lastLinePreview)
        stderr gần nhất: \(lastStderr.isEmpty ? "(trống)" : lastStderr)
        """
    }

    // MARK: - Vòng đời

    func start() {
        isStopping = false
        launchStream()
    }

    func stop() {
        isStopping = true
        process?.terminationHandler = nil
        (process?.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
    }

    deinit {
        stop()
    }

    private func launchStream() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [
            paths.script.path, paths.framework.path,
            "stream", "--no-diff", "--debounce=120", "--micros",
        ]

        let output = Pipe()
        process.standardOutput = output

        // Giữ lại stderr: đây là nơi adapter báo lỗi (thiếu framework, bị chặn…).
        let errors = Pipe()
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            NSLog("NotchIsland[adapter stderr]: \(text)")
            self?.statsLock.lock()
            self?.lastStderr = String(text.suffix(400))
            self?.statsLock.unlock()
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self?.parseQueue.async { self?.consume(chunk) }
        }

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            DispatchQueue.main.async { self?.handleExit(status: status) }
        }

        do {
            parseQueue.sync { buffer.removeAll() }
            startedAt = Date()
            try process.run()
            self.process = process
        } catch {
            NSLog("NotchIsland: không chạy được adapter – \(error.localizedDescription)")
            onFailure?()
        }
    }

    private func handleExit(status: Int32) {
        process = nil
        guard !isStopping else { return }

        let uptime = Date().timeIntervalSince(startedAt)
        NSLog("NotchIsland: adapter thoát (mã \(status)) sau \(Int(uptime))s")

        // Chết ngay khi vừa khởi động, hoặc chết quá nhiều lần → bỏ, dùng dự phòng.
        if uptime < Self.minHealthyUptime || restarts >= Self.maxRestarts {
            onFailure?()
            return
        }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, !self.isStopping else { return }
            self.launchStream()
        }
    }

    // MARK: - Điều khiển

    func send(_ command: MediaCommand) {
        run(["send", String(command.rawValue)])
    }

    /// Adapter nhận vị trí tua theo micro giây (số nguyên dương).
    func seek(to seconds: TimeInterval) {
        let micros = Int64((max(0, seconds) * 1_000_000).rounded())
        run(["seek", String(micros)])
    }

    private func run(_ arguments: [String]) {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = [paths.script.path, paths.framework.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("NotchIsland: gửi lệnh thất bại – \(error.localizedDescription)")
        }
    }

    // MARK: - Phân tích JSON (chạy trên parseQueue)

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        let newline = UInt8(ascii: "\n")

        while let index = buffer.firstIndex(of: newline) {
            let line = buffer[buffer.startIndex..<index]
            buffer.removeSubrange(buffer.startIndex...index)
            guard !line.isEmpty else { continue }
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        recordLine(line)

        guard let object = decode(line), object["type"] as? String == "data" else { return }

        let info = parse(object["payload"] as? [String: Any])
        DispatchQueue.main.async { [weak self] in self?.onChange?(info) }
    }

    /// Adapter đôi khi in `Infinity` / `NaN` (vd. `durationMicros` của livestream) – không phải JSON hợp lệ
    /// nên cả dòng bị bỏ và nhạc không hiện. Thay chúng bằng `null` rồi thử lại.
    private func decode(_ line: Data) -> [String: Any]? {
        if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
            return object
        }
        guard var text = String(data: line, encoding: .utf8) else { return countFailure() }
        text = text.replacingOccurrences(
            of: #":\s*-?(?:Infinity|inf|NaN|nan)\b"#,
            with: ":null",
            options: .regularExpression
        )
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return countFailure() }
        return object
    }

    private func countFailure() -> [String: Any]? {
        statsLock.lock()
        decodeFailures += 1
        statsLock.unlock()
        return nil
    }

    private func recordLine(_ line: Data) {
        var preview = String(decoding: line, as: UTF8.self)
        // Bỏ ảnh bìa base64 cho gọn.
        preview = preview.replacingOccurrences(
            of: #""artworkData"\s*:\s*"[^"]*""#,
            with: #""artworkData":"…""#,
            options: .regularExpression
        )
        statsLock.lock()
        lineCount += 1
        lastLinePreview = String(preview.prefix(400))
        statsLock.unlock()
    }

    /// Payload rỗng / null nghĩa là không có gì đang phát.
    private func parse(_ payload: [String: Any]?) -> NowPlayingInfo? {
        guard let payload,
              let bundleID = payload["bundleIdentifier"] as? String,
              let title = payload["title"] as? String, !title.isEmpty
        else { return nil }

        // Bỏ giá trị vô cực / NaN: `Int(.infinity)` ở chỗ hiển thị thời gian sẽ làm app crash.
        func number(_ key: String) -> Double? {
            guard let value = (payload[key] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return value
        }
        func micros(_ key: String) -> TimeInterval? { number(key).map { $0 / 1_000_000 } }

        // Trình duyệt phát qua tiến trình phụ: lấy app cha để mở đúng ứng dụng khi bấm vào.
        let parent = (payload["parentApplicationBundleIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let appID = AppCatalog.normalize(parent ?? bundleID)

        let isPlaying = payload["playing"] as? Bool ?? false
        let art = artwork.process(base64: payload["artworkData"] as? String)

        return NowPlayingInfo(
            bundleIdentifier: appID,
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            isPlaying: isPlaying,
            duration: micros("durationMicros") ?? number("duration"),
            elapsed: micros("elapsedTimeMicros") ?? number("elapsedTime"),
            timestamp: micros("timestamp").map { Date(timeIntervalSince1970: $0) },
            playbackRate: number("playbackRate") ?? (isPlaying ? 1 : 0),
            artwork: art?.image,
            artworkID: art?.id,
            accent: art?.accent ?? AppCatalog.accent(for: appID)
        )
    }
}
