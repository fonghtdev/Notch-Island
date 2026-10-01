import AppKit
import SwiftUI

enum IslandMode: Equatable {
    /// Đảo trùng khít notch – "ẩn mình".
    case collapsed
    /// Nở hai cánh sang ngang (đang phát nhạc, vừa cắm sạc…).
    case compact
    /// Hiện HUD âm lượng / độ sáng (nở ngang và thêm một thanh bên dưới).
    case hud
    /// Thẻ thông báo ngắn: cắm/rút sạc, tai nghe, hết giờ (nở xuống dưới notch).
    case banner
    /// Mở rộng khi rê chuột vào.
    case expanded
}

/// Thông tin "Đang phát" – không phụ thuộc nguồn (Music, Spotify, YouTube trên Chrome/Safari…).
struct NowPlayingInfo: Equatable {
    /// Bundle ID của app đang phát, vd. `com.google.Chrome`, `com.spotify.client`.
    var bundleIdentifier: String
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool

    var duration: TimeInterval?
    /// Vị trí phát tại thời điểm `timestamp`.
    var elapsed: TimeInterval?
    var timestamp: Date?
    var playbackRate: Double = 1
    /// Lúc app nhận được bản cập nhật này; làm mốc nội suy khi nguồn không (hoặc báo sai) `timestamp`.
    var receivedAt = Date()

    var artwork: NSImage?
    /// Định danh ảnh bìa để so sánh nhanh (NSImage không so sánh nội dung được).
    var artworkID: Int?
    /// Màu nhấn: lấy từ ảnh bìa nếu có, không thì theo app.
    var accent: Color

    var appName: String { AppCatalog.name(for: bundleIdentifier) }
    var appIcon: NSImage? { AppCatalog.icon(for: bundleIdentifier) }

    /// Vị trí phát hiện tại, nội suy từ lần cập nhật cuối: elapsed + (bây giờ − mốc) × tốc độ.
    /// Chịu được nguồn thiếu `timestamp` (trình duyệt, YouTube…) hoặc báo `playbackRate` = 0 dù đang phát.
    func currentElapsed(at date: Date = Date()) -> TimeInterval? {
        guard let elapsed else { return nil }
        var value = elapsed
        if isPlaying {
            var base = receivedAt
            if let timestamp, abs(timestamp.timeIntervalSince(receivedAt)) < 86_400 {
                base = min(timestamp, receivedAt)
            }
            let rate = playbackRate > 0 ? playbackRate : 1
            value += max(0, date.timeIntervalSince(base)) * rate
        }
        if let duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && lhs.duration == rhs.duration
            && lhs.elapsed == rhs.elapsed
            && lhs.timestamp == rhs.timestamp
            && lhs.playbackRate == rhs.playbackRate
            && lhs.artworkID == rhs.artworkID
            && lhs.accent == rhs.accent
    }
}

/// Lệnh điều khiển – rawValue trùng mã lệnh `send` của mediaremote-adapter.
enum MediaCommand: Int {
    case playPause = 2
    case next = 4
    case previous = 5
}

struct BatteryInfo: Equatable {
    var level: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    var hasBattery: Bool
    /// Số phút tới khi đầy (đang sạc) hoặc tới khi hết pin (đang dùng pin). nil = chưa ước tính được.
    var minutesRemaining: Int? = nil
    /// Công suất bộ sạc đang cắm (W); nil nếu không đọc được / không cắm.
    var adapterWatts: Int? = nil

    static let unknown = BatteryInfo(level: 100, isCharging: false, isPluggedIn: true, hasBattery: false)

    var symbolName: String {
        if isCharging { return "battery.100.bolt" }
        switch level {
        case 88...: return "battery.100"
        case 63..<88: return "battery.75"
        case 38..<63: return "battery.50"
        case 13..<38: return "battery.25"
        default: return "battery.0"
        }
    }

    var tint: Color {
        if isCharging || isPluggedIn { return .green }
        return level <= 20 ? .red : .white
    }

    /// "Đầy sau 1 giờ 20 phút" / "Dùng được 3 giờ 5 phút".
    var remainingText: String? {
        guard let minutes = minutesRemaining, minutes > 0 else { return nil }
        let h = minutes / 60, m = minutes % 60
        let text = h > 0 ? "\(h) giờ \(m) phút" : "\(m) phút"
        return isCharging ? "Đầy sau \(text)" : "Dùng được \(text)"
    }
}

/// Sự kiện ngắn hạn, tự biến mất sau `IslandMetrics.transientDuration`.
enum TransientActivity: Equatable {
    case charging(BatteryInfo)
    case unplugged(BatteryInfo)
    case headphones(HeadphoneInfo)
    case timerFinished(String)

    /// Thời gian hiện trước khi tự ẩn.
    var duration: TimeInterval {
        switch self {
        case .headphones: return 4.5
        case .timerFinished: return 6
        case .charging, .unplugged: return IslandMetrics.transientDuration
        }
    }
}

/// Một lần thay đổi âm lượng / độ sáng cần hiển thị.
struct HUDEvent: Equatable {
    enum Kind: CaseIterable { case volume, brightness, keyboard }

    var kind: Kind
    /// 0...1
    var value: Double
    var isMuted = false

    /// Giá trị hiển thị: tắt tiếng thì thanh về 0.
    var displayValue: Double { isMuted ? 0 : min(max(value, 0), 1) }

    var symbolName: String {
        switch kind {
        case .volume:
            if isMuted || value <= 0.001 { return "speaker.slash.fill" }
            if value < 0.34 { return "speaker.wave.1.fill" }
            if value < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return value < 0.3 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard:
            return value < 0.05 ? "light.min" : "light.max"
        }
    }
}
