import SwiftUI

/// Hình island: đỉnh phẳng áp sát mép màn hình, hai "tai" cong ngược ở góc trên
/// và hai góc bo tròn phía dưới. Cả hai bán kính đều animate được.
///
///   ╭─────────────────────╮   ← tai cong ngược (earRadius)
///    │                   │
///    ╰───────────────────╯    ← góc dưới (bottomRadius)
struct NotchShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(earRadius, bottomRadius) }
        set {
            earRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    /// Góc "liên tục" kiểu iOS: đoạn cong bắt đầu sớm hơn bán kính (`extent`) và điểm điều khiển cubic ở `curve`,
    /// nên đường cong ra khỏi cạnh thẳng từ từ – không có chỗ gãy gắt như góc bo bậc hai (nhìn "vuông", "gai").
    private static let extent: CGFloat = 1.25
    private static let curve: CGFloat = 0.58

    func path(in rect: CGRect) -> Path {
        let k = Self.curve
        let ear = min(earRadius, rect.width / 4, rect.height / 2)
        let left = rect.minX + ear, right = rect.maxX - ear
        let earY = min(ear * Self.extent, rect.height / 2)
        let bottom = min(bottomRadius * Self.extent, (right - left) / 2, rect.height - earY)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Tai trái: từ mép màn hình lượn xuống thân.
        path.addCurve(
            to: CGPoint(x: left, y: rect.minY + earY),
            control1: CGPoint(x: rect.minX + ear * k, y: rect.minY),
            control2: CGPoint(x: left, y: rect.minY + earY * (1 - k))
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))

        // Góc dưới trái
        path.addCurve(
            to: CGPoint(x: left + bottom, y: rect.maxY),
            control1: CGPoint(x: left, y: rect.maxY - bottom * (1 - k)),
            control2: CGPoint(x: left + bottom * (1 - k), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))

        // Góc dưới phải
        path.addCurve(
            to: CGPoint(x: right, y: rect.maxY - bottom),
            control1: CGPoint(x: right - bottom * (1 - k), y: rect.maxY),
            control2: CGPoint(x: right, y: rect.maxY - bottom * (1 - k))
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + earY))

        // Tai phải
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: right, y: rect.minY + earY * (1 - k)),
            control2: CGPoint(x: rect.maxX - ear * k, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
