import CoreAudio
import Foundation

/// Phát hiện tai nghe / loa Bluetooth kết nối hay ngắt, và đọc pin.
///
/// - Kết nối/ngắt: theo dõi danh sách thiết bị âm thanh của CoreAudio (công khai, không cần quyền).
///   Tai nghe Bluetooth xuất hiện như một thiết bị âm thanh có `transport type = Bluetooth`.
/// - Pin: `system_profiler SPBluetoothDataType -json` (có pin từng tai + hộp sạc của AirPods,
///   pin chung của tai nghe khác). Chạy nền, lúc kết nối và mỗi 60 giây.
final class HeadphoneMonitor {
    /// Vừa kết nối.
    var onConnect: ((HeadphoneInfo) -> Void)?
    /// Vừa ngắt kết nối.
    var onDisconnect: ((HeadphoneInfo) -> Void)?
    /// Thiết bị đang kết nối hiện tại (nil: không có) – phát lại khi pin cập nhật.
    var onUpdate: ((HeadphoneInfo?) -> Void)?

    private var current: HeadphoneInfo?
    private var knownNames: [String] = []
    private var batteryTimer: Timer?
    private var listening = false
    private let profilerQueue = DispatchQueue(label: "notchisland.headphones", qos: .utility)

    func start() {
        guard !listening else { return }
        listening = true

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
        ) { [weak self] _, _ in
            self?.refresh(initial: false)
        }
        if status != noErr { NSLog("NotchIsland: không theo dõi được thiết bị âm thanh (\(status))") }

        refresh(initial: true)

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            guard let name = self?.current?.name else { return }
            self?.fetchBattery(for: name)
        }
        RunLoop.main.add(timer, forMode: .common)
        batteryTimer = timer
    }

    // MARK: - Kết nối / ngắt

    private func refresh(initial: Bool) {
        let names = Self.bluetoothOutputNames()
        let previous = knownNames
        knownNames = names

        if initial {
            if let first = names.first {
                current = Self.makeInfo(name: first)
                onUpdate?(current)
                fetchBattery(for: first)
            }
            return
        }

        for name in previous where !names.contains(name) {
            var gone = (current?.name == name ? current : nil) ?? Self.makeInfo(name: name)
            gone.isConnected = false
            onDisconnect?(gone)
        }

        let added = names.filter { !previous.contains($0) }
        for name in added {
            let info = Self.makeInfo(name: name)
            current = info
            onConnect?(info)
            onUpdate?(info)
            fetchBattery(for: name)
        }

        if let existing = current, !names.contains(existing.name) {
            current = names.first.map { Self.makeInfo(name: $0) }
            onUpdate?(current)
        }
    }

    /// Đoán hình dáng từ tên: AirPods / Buds → tai nhét; còn lại → chụp tai.
    private static func makeInfo(name: String) -> HeadphoneInfo {
        HeadphoneInfo(name: name, shape: guessShape(name: name, hasEarLevels: false))
    }

    private static func guessShape(name: String, hasEarLevels: Bool) -> HeadphoneInfo.Shape {
        let lower = name.lowercased()
        if lower.contains("max") || lower.contains("headphone") || lower.contains("wh-") || lower.contains("over") {
            return .overEar
        }
        if hasEarLevels || lower.contains("pods") || lower.contains("buds") || lower.contains("ear") {
            return .earbuds
        }
        return .overEar
    }

    // MARK: - CoreAudio

    private static func bluetoothOutputNames() -> [String] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }

        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }

        var names: [String] = []
        for device in devices {
            guard isBluetooth(device), hasOutput(device), let name = deviceName(device), !names.contains(name) else { continue }
            names.append(name)
        }
        return names
    }

    private static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func hasOutput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func deviceName(_ device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: - Pin (system_profiler)

    private struct Battery {
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        var main: Int?
    }

    private func fetchBattery(for name: String) {
        profilerQueue.async { [weak self] in
            let battery = Self.readBattery(matching: name)
            DispatchQueue.main.async {
                guard let self, var info = self.current, info.name == name, let battery else { return }
                info.left = battery.left
                info.right = battery.right
                info.caseLevel = battery.caseLevel
                info.main = battery.main
                info.shape = Self.guessShape(name: name, hasEarLevels: battery.left != nil || battery.right != nil)
                guard info != self.current else { return }
                self.current = info
                self.onUpdate?(info)
            }
        }
    }

    private static func readBattery(matching name: String) -> Battery? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return nil }

        func percent(_ value: Any?) -> Int? {
            guard let text = value as? String else { return nil }
            return Int(text.filter(\.isNumber))
        }
        func key(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespaces)
        }

        let wanted = key(name)
        for section in sections {
            guard let connected = section["device_connected"] as? [[String: Any]] else { continue }
            for entry in connected {
                for (deviceName, value) in entry {
                    let candidate = key(deviceName)
                    guard candidate == wanted || candidate.contains(wanted) || wanted.contains(candidate),
                          let props = value as? [String: Any]
                    else { continue }
                    return Battery(
                        left: percent(props["device_batteryLevelLeft"]),
                        right: percent(props["device_batteryLevelRight"]),
                        caseLevel: percent(props["device_batteryLevelCase"]),
                        main: percent(props["device_batteryLevelMain"])
                    )
                }
            }
        }
        return nil
    }
}
