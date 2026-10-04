import SwiftUI

// Bộ chuyển động dùng chung: mọi thứ hiện ra theo cùng một nhịp (lò xo mềm, trễ nhẹ theo thứ tự).

/// Hiện dần: mờ → rõ, trượt lên 6pt, phóng nhẹ từ 0,96. `delay` để so le theo thứ tự phần tử.
struct Reveal: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .scaleEffect(shown ? 1 : 0.96, anchor: .top)
            .onAppear {
                // Giảm chuyển động: hiện ngay, không trượt / phóng / trễ.
                if reduceMotion { shown = true; return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func reveal(delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }

    /// Đổi biểu tượng SF Symbol bằng hiệu ứng "replace" (macOS 14+); bản cũ đổi tức thì.
    @ViewBuilder
    func symbolSwap() -> some View {
        if #available(macOS 14.0, *) {
            self.contentTransition(.symbolEffect(.replace))
        } else {
            self
        }
    }
}

/// Số phần trăm chạy từ giá trị cũ tới giá trị mới (mọi phiên bản macOS).
struct CountingPercent: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))%")
    }
}

/// Vòng sáng lan ra từ biểu tượng: báo hiệu hoạt động đang chạy (ghi âm, cuộc gọi…).
struct PulseRing: View {
    let tint: Color
    let isActive: Bool
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(tint.opacity(0.5), lineWidth: 1.2)
            .scaleEffect(phase ? 1.45 : 1)
            .opacity(isActive && !reduceMotion ? (phase ? 0 : 0.7) : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { phase = true }
            }
            .allowsHitTesting(false)
    }
}
