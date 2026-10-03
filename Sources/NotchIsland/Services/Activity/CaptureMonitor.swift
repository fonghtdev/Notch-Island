import AppKit
import ApplicationServices
import CoreAudio
import CoreMediaIO

/// Phát hiện app đang dùng micro (biết TÊN app) và camera (chỉ biết "đang bật").
/// Nhờ vậy nhận ra Discord / Zalo / Messenger / Meet… đang gọi, Voice Memos đang ghi âm… mà không cần app đó hợp tác.
///
/// Micro: CoreAudio "process objects" (macOS 14.2+). Camera: CoreMediaIO. Cả hai đều không cần quyền.
/// Thăm dò mỗi 1,5 giây trên main thread (mỗi lần vài lời gọi nhẹ).
/// Với cuộc gọi, thêm một vòng quét cửa sổ app bằng Trợ năng (luồng nền, 2 giây/lần) để biết người gọi,
/// trạng thái tắt mic và đồng bộ đồng hồ với chính app đó – xem `CallControl`.
final class CaptureMonitor {
    var onChange: (([LiveActivity]) -> Void)?

    private var timer: Timer?
    private var firstSeen: [String: Date] = [:]
    private var last: [LiveActivity] = []
    /// Mốc bắt đầu đặt sẵn cho một hoạt động sắp quay lại (vd. tiếp tục ghi âm: nối tiếp thời gian đã ghi).
    private var seeds: [String: Date] = [:]

    // MARK: Cuộc gọi
    /// Lần cuối còn thấy micro / âm thanh của cuộc gọi: app nhả micro khi bạn tắt mic, nên giữ lại một lúc
    /// thay vì xoá hoạt động và đặt lại đồng hồ.
    private var callLastActive: [String: Date] = [:]
    /// Cuộc gọi vừa bấm "kết thúc" từ island: ẩn ngay, không chờ micro nhả.
    private var endedAt: [String: Date] = [:]
    private var probes: [String: CallControl.Snapshot] = [:]
    private var probing: Set<String> = []
    private var lastProbe: [String: Date] = [:]
    private var prevDurations: [String: (at: Date, values: [TimeInterval])] = [:]
    /// Mốc bắt đầu suy ra từ đồng hồ của chính app gọi.
    private var timerSync: [String: Date] = [:]
    private let probeQueue = DispatchQueue(label: "notchisland.callprobe", qos: .utility)

    private static let callGrace: TimeInterval = 5
    /// Camera do chính NotchIsland mở (xem trước trên island) không phải "app khác đang dùng camera".
    static var ownCameraUntil = Date.distantPast

    func seed(id: String, startedAt: Date) {
        seeds[id] = startedAt
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firstSeen.removeAll()
        callLastActive.removeAll()
        endedAt.removeAll()
        probes.removeAll()
        lastProbe.removeAll()
        prevDurations.removeAll()
        timerSync.removeAll()
        if !last.isEmpty {
            last = []
            onChange?([])
        }
    }

    /// Sau khi bấm nút điều khiển cuộc gọi: kết thúc → ẩn ngay; mọi nút → quét lại sớm để cập nhật trạng thái.
    func didPerform(_ action: CallControl.Action, activityID: String) {
        if action == .end {
            endedAt[activityID] = Date()
            poll()
        }
        lastProbe[String(activityID.dropFirst(4))] = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.poll() }
    }

    // MARK: - Phân loại

    private static let callApps: Set<String> = [
        "com.hnc.Discord", "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.tinyspeck.slackmacgap", "com.apple.FaceTime", "com.skype.skype", "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark", "com.vng.zalo",
    ]
    /// Dịch vụ gọi nhận ra theo tên app / bundle ID / tiêu đề cửa sổ trình duyệt (chữ thường).
    /// Nhờ vậy cả Safari Web App ("Tiktok", "Facebook"…) lẫn tab Messenger / Meet trong trình duyệt đều nhận được.
    private static let services: [(name: String, keys: [String])] = [
        ("Messenger", ["messenger"]), ("Facebook", ["facebook"]), ("Instagram", ["instagram"]),
        ("TikTok", ["tiktok"]), ("Zalo", ["zalo"]), ("Discord", ["discord"]), ("Telegram", ["telegram"]),
        ("WhatsApp", ["whatsapp"]), ("Viber", ["viber"]), ("LINE", ["jp.naver.line"]), ("WeChat", ["wechat", "tencent.xin"]),
        ("Skype", ["skype"]), ("Zoom", ["zoom"]), ("Microsoft Teams", ["teams"]), ("Slack", ["slack"]),
        ("FaceTime", ["facetime"]), ("Webex", ["webex"]), ("Google Meet", ["google meet", "meet.google"]),
    ]
    private static let recorderApps: Set<String> = [
        "com.apple.VoiceMemos", "com.apple.QuickTimePlayerX", "com.obsproject.obs-studio",
        "com.apple.garageband10", "com.apple.logic10", "com.apple.Photobooth",
    ]
    private static let browserPrefixes = [
        "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "company.thebrowser.Browser", "org.mozilla.firefox", "com.apple.Safari",
    ]
    /// Dịch vụ hệ thống (Siri, đọc chính tả…) cũng mở micro – không phải việc người dùng cần biết.
    /// So sánh KHÔNG phân biệt hoa/thường (bundle thật là `com.apple.CoreSpeech`, `com.apple.Siri`…).
    private static let ignoredPrefixes = [
        "com.apple.siri", "com.apple.assistant", "com.apple.corespeech", "com.apple.audio",
        "com.apple.speech", "com.apple.voicebanking", "com.apple.accessibility", "com.apple.voiceover",
        "com.apple.universalaccess", "com.apple.dictation", "com.apple.coreaudio", "com.apple.telephonyutilities",
        "com.apple.avconference", "com.apple.controlcenter", "com.apple.hearingd",
    ]

    private static let untrustedMainTitle: Set<String> = ["com.vng.zalo"]

    static func service(in text: String) -> String? {
        let lowered = text.lowercased()
        return services.first { $0.keys.contains(where: lowered.contains) }?.name
    }

    /// Trình duyệt thật (không tính Safari Web App – app riêng, có tên riêng).
    private static func isBrowser(_ bundleID: String) -> Bool {
        guard !bundleID.contains(".WebApp.") else { return false }
        return browserPrefixes.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    private enum Role { case call, recorder, other }

    private static func role(of bundleID: String, name: String) -> Role {
        if callApps.contains(bundleID) || service(in: bundleID + " " + name) != nil { return .call }
        if recorderApps.contains(bundleID) { return .recorder }
        // Micro bật trong trình duyệt thường là cuộc họp (Meet, Teams web…).
        if isBrowser(bundleID) { return .call }
        return .other
    }

    // MARK: - Thăm dò

    private func poll() {
        let now = Date()
        let audio = Self.audioUsers()
        let cameraOn = Self.isCameraRunning()

        var list: [LiveActivity] = []
        var seen = Set<String>()

        for bundle in audio.inputs {
            let id = "mic:\(bundle)"
            if let ended = endedAt[id], now.timeIntervalSince(ended) < 6 { continue }
            seen.insert(id)
            let started = firstSeen[id] ?? seeds.removeValue(forKey: id) ?? now
            firstSeen[id] = started
            callLastActive[id] = now
            list.append(makeActivity(id: id, bundle: bundle, started: started, micOn: true, cameraOn: cameraOn))
        }

        // Cuộc gọi vừa nhả micro (tắt mic trong app, hoặc đã kết thúc): giữ lại một lúc, không đặt lại đồng hồ.
        // App gọi riêng còn phát âm thanh (nghe người kia nói) thì coi như vẫn đang gọi.
        for (id, started) in firstSeen where id.hasPrefix("mic:") && !seen.contains(id) {
            let bundle = String(id.dropFirst(4))
            if let ended = endedAt[id], now.timeIntervalSince(ended) < 6 { continue }
            guard Self.role(of: bundle, name: AppCatalog.name(for: bundle)) == .call else { continue }
            if !Self.isBrowser(bundle), audio.outputs.contains(bundle) { callLastActive[id] = now }
            guard let active = callLastActive[id], now.timeIntervalSince(active) < Self.callGrace else { continue }
            seen.insert(id)
            list.append(makeActivity(id: id, bundle: bundle, started: started, micOn: false, cameraOn: cameraOn))
        }

        // Camera bật nhưng không thấy app nào dùng micro (vd. Photo Booth, FaceTime video không mic…).
        if cameraOn && list.isEmpty && now > Self.ownCameraUntil {
            let id = "camera"
            seen.insert(id)
            let started = firstSeen[id] ?? now
            firstSeen[id] = started
            list.append(LiveActivity(
                id: id, kind: .camera, title: "Camera đang bật", subtitle: "Có app đang dùng camera",
                symbolName: "video.fill", tint: .green, bundleIdentifier: nil,
                startedAt: started, endsAt: nil, pausedRemaining: nil
            ))
        }

        // Dọn trạng thái của những cuộc gọi đã kết thúc hẳn.
        let activeBundles = Set(seen.compactMap { $0.hasPrefix("mic:") ? String($0.dropFirst(4)) : nil })
        firstSeen = firstSeen.filter { seen.contains($0.key) }
        callLastActive = callLastActive.filter { seen.contains($0.key) }
        endedAt = endedAt.filter { now.timeIntervalSince($0.value) < 30 }
        probes = probes.filter { activeBundles.contains($0.key) }
        lastProbe = lastProbe.filter { activeBundles.contains($0.key) }
        prevDurations = prevDurations.filter { activeBundles.contains($0.key) }
        timerSync = timerSync.filter { activeBundles.contains($0.key) }

        list.sort { ($0.kind, $0.id) < ($1.kind, $1.id) }

        guard list != last else { return }
        last = list
        onChange?(list)
    }

    private func makeActivity(id: String, bundle: String, started: Date, micOn: Bool, cameraOn: Bool) -> LiveActivity {
        let name = AppCatalog.name(for: bundle)
        switch Self.role(of: bundle, name: name) {
        case .call:
            let browser = Self.isBrowser(bundle)
            let snap = probes[bundle]
            // Cửa sổ cuộc gọi thường nằm ở tiến trình phụ (ZaloCall) → ưu tiên. Cửa sổ chính của Zalo mang tên tài khoản
            // của chính bạn ("Zalo - <tên bạn>") nên không dùng làm tên người gọi.
            var titles = snap?.helperTitles ?? []
            if !Self.untrustedMainTitle.contains(bundle) { titles += snap?.windowTitles ?? [] }
            let found = Self.identify(titles: titles, appName: name, browser: browser)
            // Trình duyệt: chỉ quét sâu (cả trang web) khi đã thấy tab của một dịch vụ gọi, để không làm nặng trình duyệt.
            scheduleProbe(bundle, deep: !browser || found.service != nil)

            var title = Self.service(in: bundle + " " + name) ?? name
            if browser, let service = found.service { title = service }
            // Đồng hồ: ưu tiên mốc suy ra từ đồng hồ của chính app gọi.
            var start = started
            if let synced = timerSync[bundle] {
                start = synced
                firstSeen[id] = synced
            }

            let muted = snap?.muted ?? !micOn   // app không có nút tắt mic → suy ra từ việc micro còn mở hay không
            var subtitle = found.caller ?? "Đang trong cuộc gọi"
            if cameraOn { subtitle += " · camera bật" }
            if muted { subtitle += " · đã tắt mic" }
            return LiveActivity(
                id: id, kind: .call, title: title, subtitle: subtitle,
                symbolName: cameraOn ? "video.fill" : "phone.fill", tint: muted ? .orange : .green, bundleIdentifier: bundle,
                startedAt: start, endsAt: nil, pausedRemaining: nil,
                // Trình duyệt chỉ có nút khi quét sâu thật sự thấy nút trong trang.
                call: browser && snap?.muted == nil && snap?.canEnd != true ? nil
                    : LiveActivity.CallState(muted: muted, deafened: snap?.deafened, camera: snap?.cameraOn)
            )
        case .recorder:
            return LiveActivity(
                id: id, kind: .recording, title: "Đang ghi âm", subtitle: name,
                symbolName: "record.circle", tint: .red, bundleIdentifier: bundle,
                startedAt: started, endsAt: nil, pausedRemaining: nil
            )
        case .other:
            return LiveActivity(
                id: id, kind: .microphone, title: "Micro đang bật", subtitle: name,
                symbolName: "mic.fill", tint: .orange, bundleIdentifier: bundle,
                startedAt: started, endsAt: nil, pausedRemaining: nil
            )
        }
    }

    // MARK: - Quét cửa sổ app gọi

    private func scheduleProbe(_ bundle: String, deep: Bool) {
        guard !probing.contains(bundle), Date().timeIntervalSince(lastProbe[bundle] ?? .distantPast) >= 2 else { return }
        probing.insert(bundle)
        probeQueue.async { [weak self] in
            let snapshot = CallControl.snapshot(bundleID: bundle, deep: deep)
            DispatchQueue.main.async {
                guard let self else { return }
                self.probing.remove(bundle)
                self.lastProbe[bundle] = Date()
                self.ingest(snapshot, bundle: bundle)
                if self.timer != nil { self.poll() }
            }
        }
    }

    /// Nhãn "mm:ss" trong cửa sổ có thể là giờ của tin nhắn. Chỉ tin nhãn nào TĂNG đúng bằng thời gian giữa hai lần quét:
    /// đó mới là đồng hồ đang chạy của cuộc gọi.
    private func ingest(_ snapshot: CallControl.Snapshot, bundle: String) {
        probes[bundle] = snapshot
        if let previous = prevDurations[bundle], !snapshot.durations.isEmpty {
            let dt = snapshot.sampledAt.timeIntervalSince(previous.at)
            if dt >= 1.5, let current = snapshot.durations.first(where: { value in
                previous.values.contains { abs((value - $0) - dt) <= 1.5 }
            }) {
                // App hiển thị phần nguyên giây: thời gian thật nằm trong [current, current + 1).
                timerSync[bundle] = snapshot.sampledAt.addingTimeInterval(-current - 0.5)
            }
        }
        prevDurations[bundle] = (snapshot.sampledAt, snapshot.durations)
    }

    /// Suy ra dịch vụ + tên người / kênh từ tiêu đề cửa sổ: "Nguyễn A | Messenger - Google Chrome" → (Messenger, "Nguyễn A").
    private static func identify(titles: [String], appName: String, browser: Bool) -> (service: String?, caller: String?) {
        var candidates = titles
        var service: String?
        if browser {
            guard let hit = titles.first(where: { Self.service(in: $0) != nil }) else { return (nil, nil) }
            service = Self.service(in: hit)
            candidates = [hit]
        }
        let skip = Set([appName, service ?? ""].map { $0.lowercased() })
        for title in candidates {
            var text = title
            for separator in [" - ", " – ", " — ", " | "] { text = text.replacingOccurrences(of: separator, with: "\u{1}") }
            let parts = text.split(separator: "\u{1}").map {
                String($0).replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }.filter { !$0.isEmpty && !skip.contains($0.lowercased()) && Self.service(in: $0) == nil }
            if !parts.isEmpty { return (service, parts.prefix(2).joined(separator: " · ")) }
        }
        return (service, nil)
    }

    // MARK: - Chẩn đoán

    /// Báo cáo cho người hỗ trợ: app nào đang mở micro, và những gì đọc được từ cửa sổ của app gọi.
    func diagnose(completion: @escaping (String) -> Void) {
        let audio = Self.audioUsers()
        var targets = audio.inputs
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundle = app.bundleIdentifier, !targets.contains(bundle),
                  Self.service(in: bundle + " " + (app.localizedName ?? "")) != nil else { continue }
            targets.append(bundle)
        }
        let names = Dictionary(uniqueKeysWithValues: targets.map { ($0, AppCatalog.name(for: $0)) })
        let trusted = AXIsProcessTrusted()

        probeQueue.async {
            var lines = [
                "Quyền Trợ năng: \(trusted ? "đã cấp" : "CHƯA cấp (không đọc được người gọi / không bấm được nút)")",
                "Micro đang mở bởi: \(audio.inputs.isEmpty ? "(không có)" : audio.inputs.joined(separator: ", "))",
                "Âm thanh ra từ: \(audio.outputs.isEmpty ? "(không có)" : audio.outputs.sorted().joined(separator: ", "))",
                "",
                "Tiến trình âm thanh:",
            ]
            lines.append(contentsOf: audio.debug.map { "  " + $0 })
            for bundle in targets {
                let name = names[bundle] ?? bundle
                let browser = Self.isBrowser(bundle)
                let snap = CallControl.snapshot(bundleID: bundle, deep: !browser)
                lines.append("")
                lines.append("== \(name) (\(bundle))\(browser ? " [trình duyệt]" : "") – pid: \(CallControl.pids(for: bundle).map(String.init).joined(separator: ","))")
                lines.append("  cửa sổ chính: \(snap.windowTitles.isEmpty ? "(không đọc được)" : snap.windowTitles.joined(separator: " | "))")
                lines.append("  cửa sổ tiến trình phụ: \(snap.helperTitles.isEmpty ? "(không có)" : snap.helperTitles.joined(separator: " | "))")
                lines.append("  nhãn thời gian: \(snap.durations.isEmpty ? "(không thấy)" : snap.durations.map { LiveActivity.format($0) }.joined(separator: ", "))")
                lines.append("  camera: \(snap.cameraOn.map { $0 ? "đang bật" : "đang tắt" } ?? "không thấy nút")")
                lines.append("  tắt mic: \(snap.muted.map { $0 ? "đang tắt" : "đang bật" } ?? "không thấy nút")"
                    + " · tắt tiếng: \(snap.deafened.map { $0 ? "đang tắt" : "đang bật" } ?? "không thấy nút")"
                    + " · kết thúc: \(snap.canEnd ? "có nút" : "không thấy nút")")
                if !snap.labels.isEmpty { lines.append("  nút: " + snap.labels.joined(separator: "; ")) }
            }
            DispatchQueue.main.async { completion(lines.joined(separator: "\n")) }
        }
    }

    // MARK: - Micro (CoreAudio process objects, macOS 14.2+)

    private static func fourCC(_ text: String) -> UInt32 {
        text.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func address(_ selector: String) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: fourCC(selector),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func readUInt32(_ object: AudioObjectID, _ selector: String) -> UInt32? {
        var addr = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func readString(_ object: AudioObjectID, _ selector: String) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr,
              let value
        else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: Tiến trình → app chính

    /// `responsibility_get_pid_responsible_for_pid` (API riêng của libSystem, nạp bằng dlsym): trả về app "chịu trách nhiệm"
    /// cho một tiến trình phụ / XPC – vd. WebKit.GPU của một Safari Web App, ZaloCall của Zalo.
    private static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    /// App thường (có icon Dock) sở hữu tiến trình này: app "chịu trách nhiệm", rồi tổ tiên gần nhất, rồi chính nó.
    /// Nhờ vậy micro mở bởi `com.vng.zalo.zalocall` hay `Discord Helper` đều tính cho đúng app.
    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        var candidates: [pid_t] = []
        if let responsible = responsiblePID?(pid), responsible > 1 { candidates.append(responsible) }
        var current = pid
        for _ in 0..<6 {
            guard let parent = parentPID(of: current), parent > 1 else { break }
            candidates.append(parent)
            current = parent
        }
        candidates.append(pid)
        for candidate in candidates {
            if let app = NSRunningApplication(processIdentifier: candidate), app.activationPolicy == .regular { return app }
        }
        return nil
    }

    private static func ownerBundle(raw: String, pid: pid_t?) -> String? {
        if let pid, let id = owningApp(of: pid)?.bundleIdentifier { return id }
        var bundle = raw
        if bundle.isEmpty, let pid, let app = NSRunningApplication(processIdentifier: pid) { bundle = app.bundleIdentifier ?? "" }
        guard !bundle.isEmpty else { return nil }
        bundle = AppCatalog.normalize(bundle)
        // Dịch vụ nền không có app (CoreSpeech nghe "Hey Siri" liên tục…) bị loại.
        let visible = NSRunningApplication.runningApplications(withBundleIdentifier: bundle)
            .contains { $0.activationPolicy != .prohibited }
        return visible ? bundle : nil
    }

    /// Bundle ID (đã đưa về app chính) của các app đang MỞ micro, và các app đang phát âm thanh ra.
    private static func audioUsers() -> (inputs: [String], outputs: Set<String>, debug: [String]) {
        var addr = address("prs#")   // kAudioHardwarePropertyProcessObjectList
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return ([], [], []) }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &objects) == noErr else { return ([], [], []) }

        let ownID = Bundle.main.bundleIdentifier
        var inputs: [String] = []
        var outputs = Set<String>()
        var debug: [String] = []
        for object in objects {
            let isInput = readUInt32(object, "piri") == 1    // kAudioProcessPropertyIsRunningInput
            let isOutput = readUInt32(object, "piro") == 1   // kAudioProcessPropertyIsRunningOutput
            guard isInput || isOutput else { continue }

            let raw = readString(object, "pbid") ?? ""        // kAudioProcessPropertyBundleID
            let pid = readUInt32(object, "ppid").map { pid_t($0) }   // kAudioProcessPropertyPID
            guard let bundle = ownerBundle(raw: raw, pid: pid) else { continue }
            debug.append("\(isInput ? "mic" : "out") pid=\(pid.map(String.init) ?? "?") \(raw.isEmpty ? "(không có bundle)" : raw) → \(bundle)")

            let lowered = bundle.lowercased()
            guard bundle != ownID, !ignoredPrefixes.contains(where: { lowered.hasPrefix($0) }) else { continue }
            if isInput, !inputs.contains(bundle) { inputs.append(bundle) }
            if isOutput { outputs.insert(bundle) }
        }
        return (inputs, outputs, debug)
    }

    // MARK: - Camera (CoreMediaIO)

    private static func isCameraRunning() -> Bool {
        func cmioAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
            CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(selector),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
        }

        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var devicesAddress = cmioAddress(Int(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &devicesAddress, 0, nil, &size) == 0, size > 0 else { return false }

        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &devicesAddress, 0, nil, size, &used, &devices) == 0 else { return false }

        for device in devices {
            var runningAddress = cmioAddress(Int(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var running: UInt32 = 0
            var runningUsed: UInt32 = 0
            let status = CMIOObjectGetPropertyData(
                device, &runningAddress, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &runningUsed, &running
            )
            if status == 0, running != 0 { return true }
        }
        return false
    }
}
