import AppKit
import CoreAudio
import CoreMediaIO

/// Phát hiện app đang dùng micro (biết TÊN app) và camera (chỉ biết "đang bật").
/// Nhờ vậy nhận ra Discord / Meet / Zoom đang gọi, Voice Memos đang ghi âm… mà không cần app đó hợp tác.
///
/// Micro: CoreAudio "process objects" (macOS 14.2+). Camera: CoreMediaIO. Cả hai đều không cần quyền.
/// Thăm dò mỗi 1,5 giây trên main thread (mỗi lần vài lời gọi nhẹ).
final class CaptureMonitor {
    var onChange: (([LiveActivity]) -> Void)?

    private var timer: Timer?
    private var firstSeen: [String: Date] = [:]
    private var last: [LiveActivity] = []
    /// Mốc bắt đầu đặt sẵn cho một hoạt động sắp quay lại (vd. tiếp tục ghi âm: nối tiếp thời gian đã ghi).
    private var seeds: [String: Date] = [:]

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
        if !last.isEmpty {
            last = []
            onChange?([])
        }
    }

    // MARK: - Phân loại

    private static let callApps: Set<String> = [
        "com.hnc.Discord", "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams",
        "com.tinyspeck.slackmacgap", "com.apple.FaceTime", "com.skype.skype", "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram", "com.cisco.webexmeetingsapp", "Cisco-Systems.Spark",
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

    /// Chỉ tính app người dùng nhìn thấy (có tiến trình app thật đang chạy). Dịch vụ nền không có app
    /// (CoreSpeech nghe "Hey Siri" liên tục…) bị loại, kể cả khi tên không nằm trong danh sách trên.
    private static func isRunningApp(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.activationPolicy != .prohibited }
    }

    private enum Role { case call, recorder, other }

    private static func role(of bundleID: String) -> Role {
        if callApps.contains(bundleID) { return .call }
        if recorderApps.contains(bundleID) { return .recorder }
        // Micro bật trong trình duyệt thường là cuộc họp (Meet, Teams web…).
        if browserPrefixes.contains(where: { bundleID == $0 || bundleID.hasPrefix($0 + ".") }) { return .call }
        return .other
    }

    // MARK: - Thăm dò

    private func poll() {
        let apps = Self.appsUsingMicrophone()
        let cameraOn = Self.isCameraRunning()

        var list: [LiveActivity] = []
        var seen = Set<String>()

        for bundle in apps {
            let id = "mic:\(bundle)"
            seen.insert(id)
            let started = firstSeen[id] ?? seeds.removeValue(forKey: id) ?? Date()
            firstSeen[id] = started
            list.append(makeActivity(id: id, bundle: bundle, started: started, cameraOn: cameraOn))
        }

        // Camera bật nhưng không thấy app nào dùng micro (vd. Photo Booth, FaceTime video không mic…).
        if cameraOn && apps.isEmpty {
            let id = "camera"
            seen.insert(id)
            let started = firstSeen[id] ?? Date()
            firstSeen[id] = started
            list.append(LiveActivity(
                id: id, kind: .camera, title: "Camera đang bật", subtitle: "Có app đang dùng camera",
                symbolName: "video.fill", tint: .green, bundleIdentifier: nil,
                startedAt: started, endsAt: nil, pausedRemaining: nil
            ))
        }

        firstSeen = firstSeen.filter { seen.contains($0.key) }
        list.sort { ($0.kind, $0.id) < ($1.kind, $1.id) }

        guard list != last else { return }
        last = list
        onChange?(list)
    }

    private func makeActivity(id: String, bundle: String, started: Date, cameraOn: Bool) -> LiveActivity {
        let name = AppCatalog.name(for: bundle)
        switch Self.role(of: bundle) {
        case .call:
            return LiveActivity(
                id: id, kind: .call, title: name,
                subtitle: cameraOn ? "Đang gọi · camera bật" : "Đang trong cuộc gọi",
                symbolName: cameraOn ? "video.fill" : "phone.fill", tint: .green, bundleIdentifier: bundle,
                startedAt: started, endsAt: nil, pausedRemaining: nil
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

    /// Bundle ID (đã đưa về app chính) của các app đang MỞ micro.
    private static func appsUsingMicrophone() -> [String] {
        var addr = address("prs#")   // kAudioHardwarePropertyProcessObjectList
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }

        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &objects) == noErr else { return [] }

        let ownID = Bundle.main.bundleIdentifier
        var result: [String] = []
        for object in objects {
            // kAudioProcessPropertyIsRunningInput
            guard readUInt32(object, "piri") == 1 else { continue }

            var bundle = readString(object, "pbid") ?? ""   // kAudioProcessPropertyBundleID
            if bundle.isEmpty, let pid = readUInt32(object, "ppid"),   // kAudioProcessPropertyPID
               let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
                bundle = app.bundleIdentifier ?? ""
            }
            guard !bundle.isEmpty else { continue }

            bundle = AppCatalog.normalize(bundle)
            let lowered = bundle.lowercased()
            guard bundle != ownID,
                  !ignoredPrefixes.contains(where: { lowered.hasPrefix($0) }),
                  isRunningApp(bundle),
                  !result.contains(bundle)
            else { continue }
            result.append(bundle)
        }
        return result
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
