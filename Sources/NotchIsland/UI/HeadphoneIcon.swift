import AppKit
import SwiftUI

/// Biểu tượng tai nghe: dùng đúng SF Symbols của Apple cho AirPods / AirPods Pro / AirPods Max (và Beats),
/// biểu tượng chung cho tai nghe hãng khác. Hiện ra với hiệu ứng bật nhẹ; ngắt kết nối thì mờ đi và có vạch chéo.
struct HeadphoneIcon: View {
    let model: HeadphoneInfo.Model
    let isConnected: Bool

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [(isConnected ? Color.white : Color.gray).opacity(0.22), .clear],
                        center: .center, startRadius: 2, endRadius: 34
                    )
                )
                .scaleEffect(appeared ? 1 : 0.4)

            Image(systemName: Self.symbol(for: model))
                .font(.system(size: 36, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white.opacity(isConnected ? 1 : 0.45))
                .scaleEffect(appeared ? 1 : 0.55)
                .opacity(appeared ? 1 : 0)
                .bounceOnAppear(appeared)

            if !isConnected {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.7))
                    .rotationEffect(.degrees(90))
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { appeared = true }
        }
    }

    /// Biểu tượng đầu tiên trong danh sách ưu tiên mà bản macOS này có.
    static func symbol(for model: HeadphoneInfo.Model) -> String {
        for name in model.symbolCandidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return "headphones"
    }
}

private extension View {
    /// Hiệu ứng `bounce` của SF Symbols (macOS 14+); bản cũ hơn chỉ dùng hiệu ứng scale ở trên.
    @ViewBuilder
    func bounceOnAppear(_ trigger: Bool) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: trigger)
        } else {
            self
        }
    }
}
