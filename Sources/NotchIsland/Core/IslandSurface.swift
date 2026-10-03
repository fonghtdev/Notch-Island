import SwiftUI

/// Kiểu nền của island.
enum IslandBackgroundStyle: String, CaseIterable, Identifiable {
    /// Đen đặc – khớp hoàn toàn với notch.
    case solid
    /// Kính mờ (Material) – chạy trên mọi macOS 13+.
    case frosted
    /// Liquid Glass thật của macOS 26. Máy cũ hơn / bộ công cụ cũ hơn tự lùi về `frosted`.
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Đen"
        case .frosted: return "Kính mờ"
        case .glass: return "Liquid Glass"
        }
    }
}

/// Thông số nền island – dữ liệu thuần, dựng từ `AppSettings`.
struct IslandSurface: Equatable {
    var style: IslandBackgroundStyle = .solid
    /// Liquid Glass dạng "clear" (trong suốt hơn `regular`).
    var isClear = false
    /// Màu phủ lên kính để chữ trắng vẫn đọc được trên hình nền sáng.
    var tint: Color = .black
    var tintStrength: Double = 0.08

    /// Liquid Glass thật chỉ có khi VỪA build bằng Swift 6.2+ (Xcode 26) VỪA chạy trên macOS 26+.
    static var supportsLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}
