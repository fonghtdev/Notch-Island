import SwiftUI

/// Hoạt động đang diễn ra ở ngoài app (hẹn giờ, cuộc gọi, ghi âm…).
/// Hiện trên đảo suốt thời gian còn diễn ra: hai cánh nhỏ khi thu gọn, một hàng đầy đủ khi mở rộng.
struct LiveActivity: Identifiable, Equatable {
    enum Kind: Int, Comparable {
        /// Thứ tự = độ ưu tiên hiển thị (nhỏ hơn = quan trọng hơn).
        case call, recording, timer, stopwatch, microphone, camera

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: String
    var kind: Kind
    var title: String
    var subtitle: String
    var symbolName: String
    var tint: Color
    /// App sẽ được mở khi bấm vào hàng này (nil: không làm gì).
    var bundleIdentifier: String?
    /// Có giá trị → đồng hồ đếm LÊN từ thời điểm này (cuộc gọi, ghi âm…).
    var startedAt: Date?
    /// Có giá trị → đồng hồ đếm XUỐNG tới thời điểm này (hẹn giờ).
    var endsAt: Date?
    /// Hẹn giờ đang tạm dừng: số giây còn lại.
    var pausedRemaining: TimeInterval?
    /// Bấm giờ / ghi âm đang tạm dừng: số giây đã trôi.
    var pausedElapsed: TimeInterval? = nil
    /// Chỉ cuộc gọi của app (không phải trình duyệt): trạng thái mic / tắt tiếng. nil = chưa biết app có nút đó.
    var call: CallState? = nil

    struct CallState: Equatable {
        var muted: Bool?
        var deafened: Bool?
    }

    /// Mốc để đồng hồ hiển thị nhảy đúng lúc giây của hoạt động tròn (không trễ tới 1 giây so với app gốc).
    var tickAnchor: Date { startedAt ?? endsAt ?? Date() }

    var isPaused: Bool { pausedRemaining != nil || pausedElapsed != nil }

    /// Nút điều khiển hiện trên hàng hoạt động.
    enum Controls { case none, timer, stopwatch, recording, call }
    var controls: Controls {
        if id == "timer" { return .timer }
        if id == "stopwatch" { return .stopwatch }
        if kind == .recording { return .recording }
        if kind == .call, call != nil { return .call }
        return .none
    }

    /// Chuỗi đồng hồ tại thời điểm `date`; nil nếu hoạt động không có đồng hồ.
    func clockText(at date: Date = Date()) -> String? {
        if let pausedElapsed { return Self.format(pausedElapsed.rounded(.down)) }
        if let pausedRemaining { return Self.format(pausedRemaining.rounded(.up)) }
        if let endsAt { return Self.format(max(0, endsAt.timeIntervalSince(date)).rounded(.up)) }
        if let startedAt { return Self.format(max(0, date.timeIntervalSince(startedAt)).rounded(.down)) }
        return nil
    }

    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(max(0, seconds))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

/// Tai nghe Bluetooth đang kết nối.
struct HeadphoneInfo: Equatable, Identifiable {
    enum Shape { case earbuds, overEar }

    var id: String { name }
    var name: String
    var shape: Shape
    var isConnected = true
    /// Pin từng tai / hộp sạc (AirPods…), hoặc pin chung (`main`). nil = chưa đọc được.
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var main: Int?

    /// Mức pin đại diện: pin chung, hoặc tai yếu nhất.
    var level: Int? {
        if let main { return main }
        return [left, right].compactMap { $0 }.min()
    }

    var hasBatteryData: Bool { level != nil || caseLevel != nil }

    /// Kiểu thiết bị để chọn biểu tượng: AirPods / AirPods Pro / AirPods Max dùng đúng biểu tượng của Apple (SF Symbols),
    /// Beats và tai nghe hãng khác dùng biểu tượng chung theo hình dáng.
    enum Model: Equatable {
        case airpods, airpods3, airpodsPro, airpodsMax
        case beatsEarbuds, beatsOverEar
        case genericEarbuds, genericOverEar

        /// Danh sách ưu tiên: cái đầu tiên có trên bản macOS đang chạy sẽ được dùng.
        var symbolCandidates: [String] {
            switch self {
            case .airpods: return ["airpods"]
            case .airpods3: return ["airpods.gen3", "airpods"]
            case .airpodsPro: return ["airpodspro"]
            case .airpodsMax: return ["airpodsmax"]
            case .beatsEarbuds: return ["beats.studiobuds", "beats.powerbeats.pro", "earbuds", "airpods"]
            case .beatsOverEar: return ["beats.headphones", "headphones"]
            case .genericEarbuds: return ["earbuds", "airpods"]
            case .genericOverEar: return ["headphones"]
            }
        }
    }

    var model: Model {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return .airpodsMax }
        if lower.contains("airpods pro") { return .airpodsPro }
        if lower.contains("airpods") {
            let isGen3Plus = ["3rd", "gen 3", "gen3", "(3", "4th", "gen 4", "gen4", "(4"].contains { lower.contains($0) }
            return isGen3Plus ? .airpods3 : .airpods
        }
        if lower.contains("beats") || lower.contains("powerbeats") {
            return shape == .overEar ? .beatsOverEar : .beatsEarbuds
        }
        return shape == .overEar ? .genericOverEar : .genericEarbuds
    }
}

/// Một thông báo đọc từ Trung tâm thông báo (chỉ dùng cho màn hình khoá).
struct NotificationItem: Identifiable, Equatable {
    let id: Int64
    var bundleIdentifier: String
    var title: String
    var subtitle: String
    var body: String
    var date: Date
}
