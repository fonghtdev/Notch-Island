import SwiftUI

/// Kiểu hiển thị giá trị của HUD.
enum HUDStyle: String, CaseIterable, Identifiable {
    /// Thanh ngang liền dưới hàng notch.
    case bar
    /// 16 vạch như HUD của macOS.
    case segments
    /// Vòng tròn ở cánh phải, không thêm hàng bên dưới (island thấp hơn).
    case ring

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bar: return "Thanh"
        case .segments: return "Vạch"
        case .ring: return "Vòng"
        }
    }
}

/// Độ bo góc của thanh / vạch / đầu vòng.
enum HUDCorner: String, CaseIterable, Identifiable {
    case round, soft, square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .round: return "Tròn"
        case .soft: return "Bo nhẹ"
        case .square: return "Vuông"
        }
    }

    func radius(forHeight height: CGFloat) -> CGFloat {
        switch self {
        case .round: return height / 2
        case .soft: return height * 0.3
        case .square: return 0
        }
    }
}

/// Toàn bộ thông số giao diện HUD – dữ liệu thuần, dựng từ `AppSettings`,
/// dùng chung cho HUD thật, xem trước trong Cài đặt và thanh trượt điều khiển nhanh.
struct HUDAppearance: Equatable {
    var style: HUDStyle = .bar
    var barHeight: CGFloat = 5
    var corner: HUDCorner = .round
    var showsPercent = true
    var volumeColor: Color = .white
    var brightnessColor: Color = .white
    var keyboardColor: Color = .white

    func color(for kind: HUDEvent.Kind) -> Color {
        switch kind {
        case .volume: return volumeColor
        case .brightness: return brightnessColor
        case .keyboard: return keyboardColor
        }
    }

    /// Chiều cao cộng thêm bên dưới hàng notch. Kiểu vòng nằm gọn trong hàng notch nên bằng 0.
    var extraHeight: CGFloat {
        style == .ring ? 0 : barHeight + 18
    }
}
