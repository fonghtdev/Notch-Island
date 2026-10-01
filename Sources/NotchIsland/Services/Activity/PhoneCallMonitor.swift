import AppKit
import ObjectiveC
import SwiftUI

/// Cuộc gọi điện thoại (iPhone chuyển tiếp sang Mac) và FaceTime, đọc từ `TelephonyUtilities` – THỬ NGHIỆM.
///
/// Không có API công khai. Gọi `TUCallCenter` / `TUCall` của framework riêng qua ObjC runtime; mọi hàm đều kiểm tra
/// `responds(to:)` trước (gọi sai tên qua KVC là crash), nên máy nào thiếu hàm chỉ làm hoạt động không hiện chứ không sập app.
/// Cho biết tên người gọi, đang đổ chuông hay đã kết nối, giờ kết nối thật (đồng hồ khớp với app Điện thoại / FaceTime)
/// và cho trả lời / từ chối / tắt mic / kết thúc.
final class PhoneCallMonitor {
    var onChange: (([LiveActivity]) -> Void)?

    private static let frameworkPath = "/System/Library/PrivateFrameworks/TelephonyUtilities.framework/TelephonyUtilities"
    static let idPrefix = "phone:"

    private var timer: Timer?
    private var center: NSObject?
    private var last: [LiveActivity] = []
    private var calls: [String: NSObject] = [:]

    func start() {
        guard timer == nil else { return }
        if center == nil {
            dlopen(Self.frameworkPath, RTLD_NOW)
            if let cls = NSClassFromString("TUCallCenter") as? NSObject.Type,
               (cls as AnyObject).responds(to: NSSelectorFromString("sharedInstance")) {
                center = (cls as AnyObject).perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue() as? NSObject
            }
        }
        guard center != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        calls.removeAll()
        if !last.isEmpty {
            last = []
            onChange?([])
        }
    }

    // MARK: - KVC an toàn

    private static func read(_ object: NSObject, _ key: String) -> Any? {
        let capital = key.prefix(1).uppercased() + key.dropFirst()
        for name in [key, "is" + capital] where object.responds(to: NSSelectorFromString(name)) {
            return object.value(forKey: name)
        }
        return nil
    }

    private static func flag(_ object: NSObject, _ key: String) -> Bool { (read(object, key) as? NSNumber)?.boolValue ?? false }

    @discardableResult
    private static func write(_ object: NSObject, _ key: String, _ value: Any) -> Bool {
        let capital = key.prefix(1).uppercased() + key.dropFirst()
        guard object.responds(to: NSSelectorFromString("set\(capital):")) else { return false }
        object.setValue(value, forKey: key)
        return true
    }

    // MARK: - Đọc cuộc gọi

    private func currentCalls() -> [NSObject] {
        guard let center, center.responds(to: NSSelectorFromString("currentCalls")) else { return [] }
        return (center.value(forKey: "currentCalls") as? [NSObject]) ?? []
    }

    private func poll() {
        var list: [LiveActivity] = []
        var seen: [String: NSObject] = [:]
        for call in currentCalls() {
            let id = Self.idPrefix + (Self.read(call, "callUUID").map { "\($0)" } ?? "\(ObjectIdentifier(call).hashValue)")
            seen[id] = call
            list.append(Self.activity(id: id, call: call))
        }
        calls = seen
        guard list != last else { return }
        last = list
        onChange?(list)
    }

    private static func activity(id: String, call: NSObject) -> LiveActivity {
        let incoming = flag(call, "incoming")
        let connected = flag(call, "connected")
        let ringing = incoming && !connected
        let muted = flag(call, "uplinkMuted")
        let isVideo = flag(call, "video")
        let name = (read(call, "displayName") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (read(call, "suggestedDisplayName") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Số không xác định"

        let provider = (read(call, "provider") as? NSObject).flatMap { read($0, "localizedName") as? String }
        let service = provider == "FaceTime" ? "FaceTime" : "iPhone"
        var subtitle = ringing ? "Cuộc gọi đến · \(service)" : (connected ? service : "Đang gọi · \(service)")
        if connected, muted { subtitle += " · đã tắt mic" }

        return LiveActivity(
            id: id, kind: .call, title: name, subtitle: subtitle,
            symbolName: ringing ? "phone.arrow.down.left" : (isVideo ? "video.fill" : "phone.fill"),
            tint: ringing ? .blue : (muted ? .orange : .green), bundleIdentifier: "com.apple.FaceTime",
            // Giờ kết nối thật do hệ thống ghi nhận → đồng hồ khớp với app gọi.
            startedAt: connected ? (read(call, "dateConnected") as? Date) ?? Date() : nil,
            endsAt: nil, pausedRemaining: nil,
            call: LiveActivity.CallState(muted: muted, deafened: nil, camera: isVideo ? flag(call, "isSendingVideo") : nil, ringing: ringing)
        )
    }

    // MARK: - Điều khiển

    func perform(_ action: CallControl.Action, id: String) -> Bool {
        guard let center, let call = calls[id] else { return false }
        switch action {
        case .answer:
            return Self.send(center, "answerCall:", call)
        case .end:
            return Self.send(center, "disconnectCall:", call)
        case .mute:
            return Self.write(call, "uplinkMuted", !Self.flag(call, "uplinkMuted"))
        case .camera:
            return Self.write(call, "isSendingVideo", !Self.flag(call, "isSendingVideo"))
        case .deafen:
            return false
        }
    }

    private static func send(_ center: NSObject, _ selector: String, _ call: NSObject) -> Bool {
        let sel = NSSelectorFromString(selector)
        guard center.responds(to: sel) else { return false }
        _ = center.perform(sel, with: call)
        return true
    }

    // MARK: - Chẩn đoán

    func diagnose() -> String {
        dlopen(Self.frameworkPath, RTLD_NOW)
        if center == nil, let cls = NSClassFromString("TUCallCenter") as? NSObject.Type,
           (cls as AnyObject).responds(to: NSSelectorFromString("sharedInstance")) {
            center = (cls as AnyObject).perform(NSSelectorFromString("sharedInstance"))?.takeUnretainedValue() as? NSObject
        }
        guard center != nil else { return "TelephonyUtilities: không nạp được TUCallCenter" }
        let current = currentCalls()
        var lines = ["TelephonyUtilities: nạp được · số cuộc gọi hiện tại: \(current.count)"]
        for call in current {
            let keys = ["displayName", "callStatus", "incoming", "connected", "uplinkMuted", "video", "isSendingVideo", "dateConnected"]
            lines.append("  " + keys.map { "\($0)=\(Self.read(call, $0).map { "\($0)" } ?? "?")" }.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}
