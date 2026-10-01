import SwiftUI

/// Hình đảo: đỉnh phẳng áp sát mép màn hình, hai "tai" cong ngược ở góc trên
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

    func path(in rect: CGRect) -> Path {
        let ear = min(earRadius, rect.width / 4, rect.height / 2)
        let bottom = min(bottomRadius, (rect.width - ear * 2) / 2, rect.height - ear)

        let left = rect.minX + ear
        let right = rect.maxX - ear

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Tai trái
        path.addQuadCurve(
            to: CGPoint(x: left, y: rect.minY + ear),
            control: CGPoint(x: left, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))

        // Góc dưới trái
        path.addQuadCurve(
            to: CGPoint(x: left + bottom, y: rect.maxY),
            control: CGPoint(x: left, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))

        // Góc dưới phải
        path.addQuadCurve(
            to: CGPoint(x: right, y: rect.maxY - bottom),
            control: CGPoint(x: right, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: right, y: rect.minY + ear))

        // Tai phải
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: right, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
