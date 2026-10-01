import SwiftUI

/// Mọi con số về kích thước / chuyển động nằm ở một chỗ để dễ tinh chỉnh.
enum IslandMetrics {
    // Tỉ lệ chuẩn, cố định vĩnh viễn (không có tuỳ chọn trong Cài đặt):
    // thẻ mở rộng 440×172 (~2,56:1), bo góc thu gọn 10 khớp notch thật, bo góc mở rộng 26.
    /// Bán kính "tai" cong ngược ở hai góc trên, giúp đảo liền mạch với viền màn hình.
    static let earRadius: CGFloat = 6
    static let collapsedBottomRadius: CGFloat = 10
    static let expandedBottomRadius: CGFloat = 26

    /// Độ rộng mỗi "cánh" hai bên notch ở trạng thái compact.
    static let compactWingWidth: CGFloat = 44
    static let expandedSize = CGSize(width: 440, height: 172)
    /// Thẻ mở rộng co giãn theo nội dung (xem `ExpandedLayout`).
    static let mediaOnlyHeight: CGFloat = 148
    static let activityWidth: CGFloat = 348
    static let activityRowHeight: CGFloat = 44
    static let activityRowSpacing: CGFloat = 8
    static let idleSize = CGSize(width: 300, height: 88)

    /// Cửa sổ trong suốt luôn giữ cố định kích thước tối đa (+ chỗ cho bóng đổ),
    /// chỉ phần hình đảo thay đổi → không phải resize NSWindow khi animate.
    static let panelSize = CGSize(width: 580, height: 260)

    /// Notch giả cho màn hình không có tai thỏ (màn rời, MacBook đời cũ).
    static let fakeNotchSize = CGSize(width: 190, height: 32)

    /// HUD: rộng hơn compact một chút (chiều cao thêm phụ thuộc kiểu HUD, xem `HUDAppearance`).
    /// HUD: icon ở cánh trái, giá trị ở cánh phải; bề ngang bằng đúng chế độ compact (không nới thêm) để hai bên không bị tách xa.
    static let hudWingWidth: CGFloat = 44
    static let hudDuration: TimeInterval = 1.6

    /// Thẻ thông báo (banner): bề ngang cố định, chiều cao thêm phía dưới notch.
    static let bannerWidth: CGFloat = 330
    static let bannerExtraHeight: CGFloat = 60
    /// Thẻ cắm / rút sạc: gọn hơn, chỉ một thanh pin và một dòng chữ dưới hàng notch.
    static let powerExtraHeight: CGFloat = 54
    static let headphoneExtraHeight: CGFloat = 88
    static let bannerBottomRadius: CGFloat = 22

    static let hoverPadding: CGFloat = 6
    static let collapseDelay: TimeInterval = 0.08
    static let transientDuration: TimeInterval = 3

    /// Mở / chuyển chế độ: hơi đàn hồi nhẹ.
    static let spring = Animation.spring(response: 0.36, dampingFraction: 0.84)
    /// Thu lại: giảm chấn tới hạn (không nảy) và nhanh hơn, để thu lại cảm giác dứt khoát, không bị "trễ".
    static let closeSpring = Animation.spring(response: 0.28, dampingFraction: 1.0)
}
