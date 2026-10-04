import SwiftUI
import Combine

/// Cài đặt người dùng, lưu bằng UserDefaults. Mỗi thay đổi tự ghi xuống đĩa
/// và phát `objectWillChange` để UI / ViewModel cập nhật.
final class AppSettings: ObservableObject {
    static let barHeightRange: ClosedRange<Double> = 3...10
    static let glassTintStrengthRange: ClosedRange<Double> = 0...0.7

    private enum Key {
        static let showNowPlaying = "showNowPlaying"
        static let showBatteryAlerts = "showBatteryAlerts"
        static let showHUD = "showHUD"
        static let showLiveActivities = "showLiveActivities"
        static let showHeadphones = "showHeadphones"
        static let hdArtwork = "hdArtwork"
        static let autoCheckUpdates = "autoCheckUpdates"
        static let keyboardShortcut = "keyboardShortcut"
        static let showOnLockScreen = "showOnLockScreen"
        static let lockScreenNotifications = "lockScreenNotifications"
        static let iphoneNotifications = "iphoneNotifications"
        static let hoverToExpand = "hoverToExpand"
        static let displayID = "displayID"
        static let hudStyle = "hudStyle"
        static let hudBarHeight = "hudBarHeight"
        static let hudCorner = "hudCorner"
        static let hudShowsPercent = "hudShowsPercent"
        static let volumeColor = "volumeColor"
        static let brightnessColor = "brightnessColor"
        static let keyboardColor = "keyboardColor"
        static let islandStyle = "islandStyle"
        static let ambientLight = "ambientLight"
        static let ambientIntensity = "ambientIntensity"
        static let glassClear = "glassClear"
        static let glassTint = "glassTint"
        static let glassTintStrength = "glassTintStrength"
    }

    private let defaults: UserDefaults

    // MARK: Tính năng

    @Published var showNowPlaying: Bool {
        didSet { defaults.set(showNowPlaying, forKey: Key.showNowPlaying) }
    }
    @Published var showBatteryAlerts: Bool {
        didSet { defaults.set(showBatteryAlerts, forKey: Key.showBatteryAlerts) }
    }
    /// Thông báo từ iPhone hiện trên island (cần quyền Toàn bộ ổ đĩa để đọc Trung tâm thông báo).
    @Published var iphoneNotifications: Bool {
        didSet { defaults.set(iphoneNotifications, forKey: Key.iphoneNotifications) }
    }
    @Published var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: Key.showHUD) }
    }

    /// Hiện hoạt động đang diễn ra: hẹn giờ, cuộc gọi (Discord, Meet…), ghi âm, camera.
    @Published var showLiveActivities: Bool {
        didSet { defaults.set(showLiveActivities, forKey: Key.showLiveActivities) }
    }
    /// Phím tắt fn+F1 / fn+F2 chỉnh đèn bàn phím (chỉ khi máy có đèn bàn phím).
    @Published var keyboardShortcut: Bool {
        didSet { defaults.set(keyboardShortcut, forKey: Key.keyboardShortcut) }
    }
    /// Tự kiểm tra bản mới trên GitHub Releases (không gửi dữ liệu cá nhân).
    @Published var autoCheckUpdates: Bool {
        didSet { defaults.set(autoCheckUpdates, forKey: Key.autoCheckUpdates) }
    }
    /// Tra ảnh bìa độ phân giải cao trên iTunes (gửi tên bài + nghệ sĩ tới Apple).
    @Published var hdArtwork: Bool {
        didSet { defaults.set(hdArtwork, forKey: Key.hdArtwork) }
    }
    /// Thẻ 3D khi tai nghe Bluetooth kết nối / ngắt.
    @Published var showHeadphones: Bool {
        didSet { defaults.set(showHeadphones, forKey: Key.showHeadphones) }
    }
    /// Thẻ giữa màn hình khoá (thử nghiệm, API riêng tư).
    @Published var showOnLockScreen: Bool {
        didSet { defaults.set(showOnLockScreen, forKey: Key.showOnLockScreen) }
    }
    /// Hiện thông báo trên màn hình khoá (thử nghiệm, cần quyền Toàn bộ ổ đĩa).
    @Published var lockScreenNotifications: Bool {
        didSet { defaults.set(lockScreenNotifications, forKey: Key.lockScreenNotifications) }
    }

    // MARK: Hành vi & vị trí

    /// true: rê chuột vào là mở. false: phải bấm vào đảo.
    @Published var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: Key.hoverToExpand) }
    }
    /// 0 = tự động (ưu tiên màn hình có notch). Khác 0 = `CGDirectDisplayID` đã chọn.
    @Published var displayID: Int {
        didSet { defaults.set(displayID, forKey: Key.displayID) }
    }

    // MARK: Nền đảo

    @Published var islandStyle: IslandBackgroundStyle {
        didSet {
            defaults.set(islandStyle.rawValue, forKey: Key.islandStyle)
            // Vừa chọn Liquid Glass: đặt sẵn giá trị như Control Center: kính "regular" (không phải clear), không phủ màu (người dùng vẫn chỉnh lại được).
            if islandStyle == .glass, oldValue != .glass {
                glassClear = false
                glassTintStrength = 0
            }
        }
    }
    @Published var glassClear: Bool {
        didSet { defaults.set(glassClear, forKey: Key.glassClear) }
    }
    @Published var glassTint: Color {
        didSet { defaults.set(glassTint.hexString, forKey: Key.glassTint) }
    }
    @Published var glassTintStrength: Double {
        didSet { defaults.set(glassTintStrength, forKey: Key.glassTintStrength) }
    }

    var islandSurface: IslandSurface {
        IslandSurface(style: islandStyle, isClear: glassClear, tint: glassTint, tintStrength: glassTintStrength)
    }

    // MARK: Ambient light

    /// Ánh sáng viền màn hình theo màu nội dung (cần quyền Ghi màn hình). Mặc định tắt.
    @Published var ambientLight: Bool {
        didSet { defaults.set(ambientLight, forKey: Key.ambientLight) }
    }
    @Published var ambientIntensity: Double {
        didSet { defaults.set(ambientIntensity, forKey: Key.ambientIntensity) }
    }

    // MARK: Giao diện HUD

    @Published var hudStyle: HUDStyle {
        didSet { defaults.set(hudStyle.rawValue, forKey: Key.hudStyle) }
    }
    @Published var hudBarHeight: Double {
        didSet { defaults.set(hudBarHeight, forKey: Key.hudBarHeight) }
    }
    @Published var hudCorner: HUDCorner {
        didSet { defaults.set(hudCorner.rawValue, forKey: Key.hudCorner) }
    }
    @Published var hudShowsPercent: Bool {
        didSet { defaults.set(hudShowsPercent, forKey: Key.hudShowsPercent) }
    }
    @Published var volumeColor: Color {
        didSet { defaults.set(volumeColor.hexString, forKey: Key.volumeColor) }
    }
    @Published var brightnessColor: Color {
        didSet { defaults.set(brightnessColor.hexString, forKey: Key.brightnessColor) }
    }
    @Published var keyboardColor: Color {
        didSet { defaults.set(keyboardColor.hexString, forKey: Key.keyboardColor) }
    }

    var hudAppearance: HUDAppearance {
        HUDAppearance(
            style: hudStyle,
            barHeight: CGFloat(hudBarHeight),
            corner: hudCorner,
            showsPercent: hudShowsPercent,
            volumeColor: volumeColor,
            brightnessColor: brightnessColor,
            keyboardColor: keyboardColor
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showNowPlaying: true,
            Key.showBatteryAlerts: true,
            Key.showHUD: true,
            Key.showLiveActivities: true,
            Key.showHeadphones: true,
            Key.hdArtwork: true,
            Key.autoCheckUpdates: true,
            Key.keyboardShortcut: true,
            Key.showOnLockScreen: true,
            Key.lockScreenNotifications: false,
            Key.iphoneNotifications: false,
            Key.hoverToExpand: true,
            Key.displayID: 0,
            Key.hudStyle: HUDStyle.bar.rawValue,
            Key.hudBarHeight: 5.0,
            Key.hudCorner: HUDCorner.round.rawValue,
            Key.hudShowsPercent: true,
            Key.volumeColor: "#FFFFFF",
            Key.brightnessColor: "#FFFFFF",
            Key.keyboardColor: "#FFFFFF",
            Key.islandStyle: IslandBackgroundStyle.solid.rawValue,
            Key.glassClear: false,
            Key.glassTint: "#000000",
            Key.glassTintStrength: 0.08,
            Key.ambientLight: false,
            Key.ambientIntensity: 0.7,
        ])

        func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            min(max(value, range.lowerBound), range.upperBound)
        }

        showNowPlaying = defaults.bool(forKey: Key.showNowPlaying)
        showBatteryAlerts = defaults.bool(forKey: Key.showBatteryAlerts)
        showHUD = defaults.bool(forKey: Key.showHUD)
        showLiveActivities = defaults.bool(forKey: Key.showLiveActivities)
        showHeadphones = defaults.bool(forKey: Key.showHeadphones)
        hdArtwork = defaults.bool(forKey: Key.hdArtwork)
        autoCheckUpdates = defaults.bool(forKey: Key.autoCheckUpdates)
        keyboardShortcut = defaults.bool(forKey: Key.keyboardShortcut)
        showOnLockScreen = defaults.bool(forKey: Key.showOnLockScreen)
        lockScreenNotifications = defaults.bool(forKey: Key.lockScreenNotifications)
        iphoneNotifications = defaults.bool(forKey: Key.iphoneNotifications)
        hoverToExpand = defaults.bool(forKey: Key.hoverToExpand)
        displayID = defaults.integer(forKey: Key.displayID)

        islandStyle = IslandBackgroundStyle(rawValue: defaults.string(forKey: Key.islandStyle) ?? "") ?? .solid
        glassClear = defaults.bool(forKey: Key.glassClear)
        glassTint = Color(hex: defaults.string(forKey: Key.glassTint) ?? "#000000")
        glassTintStrength = clamp(defaults.double(forKey: Key.glassTintStrength), Self.glassTintStrengthRange)

        // Bản trước đặt sẵn Clear bật cho Liquid Glass; Control Center dùng Regular → đưa giá trị đã lưu về Regular một lần.
        if defaults.integer(forKey: "glassPresetVersion") < 2 {
            defaults.set(false, forKey: Key.glassClear)
            glassClear = false
            defaults.set(2, forKey: "glassPresetVersion")
        }
        ambientLight = defaults.bool(forKey: Key.ambientLight)
        ambientIntensity = clamp(defaults.double(forKey: Key.ambientIntensity), 0.2...1)

        hudStyle = HUDStyle(rawValue: defaults.string(forKey: Key.hudStyle) ?? "") ?? .bar
        hudBarHeight = clamp(defaults.double(forKey: Key.hudBarHeight), Self.barHeightRange)
        hudCorner = HUDCorner(rawValue: defaults.string(forKey: Key.hudCorner) ?? "") ?? .round
        hudShowsPercent = defaults.bool(forKey: Key.hudShowsPercent)
        volumeColor = Color(hex: defaults.string(forKey: Key.volumeColor) ?? "#FFFFFF")
        brightnessColor = Color(hex: defaults.string(forKey: Key.brightnessColor) ?? "#FFFFFF")
        keyboardColor = Color(hex: defaults.string(forKey: Key.keyboardColor) ?? "#FFFFFF")
    }

    /// Đưa toàn bộ giao diện HUD và nền đảo về mặc định.
    func resetAppearance() {
        hudStyle = .bar
        hudBarHeight = 5
        hudCorner = .round
        hudShowsPercent = true
        volumeColor = .white
        brightnessColor = .white
        keyboardColor = .white
        islandStyle = .solid
        glassClear = false
        glassTint = .black
        glassTintStrength = 0.08
    }
}
