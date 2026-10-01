import SwiftUI

/// Chữ một dòng: vừa khung thì đứng yên; dài hơn khung thì tự chạy ngang (kiểu "slide") theo vòng lặp,
/// dừng ở đầu một nhịp cho dễ đọc. Hai đầu mờ dần khi đang chạy.
struct MarqueeText: View {
    let text: String
    var font: Font = .system(size: 13)
    /// Tốc độ chạy (điểm/giây).
    var speed: CGFloat = 34
    /// Khoảng trống giữa hai lần lặp của chuỗi.
    var gap: CGFloat = 40
    /// Dừng ở vị trí đầu bao lâu trước mỗi vòng.
    var pause: TimeInterval = 1.6

    @State private var textWidth: CGFloat = 0
    @State private var start = Date()

    var body: some View {
        // Bản vô hình định kích thước (chiều cao một dòng, chiều rộng theo khung cha).
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    let overflow = textWidth > proxy.size.width + 1
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !overflow)) { context in
                        HStack(spacing: gap) {
                            label
                            if overflow { label }
                        }
                        .offset(x: overflow ? -offset(at: context.date) : 0)
                    }
                    .frame(width: proxy.size.width, alignment: .leading)
                    .clipped()
                    .mask(fade(active: overflow))
                }
            }
            // Đo chiều rộng tự nhiên của chữ.
            .background(
                label
                    .fixedSize()
                    .hidden()
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: MarqueeWidthKey.self, value: proxy.size.width)
                    })
            )
            .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
            .onChange(of: text) { _ in start = Date() }
    }

    private var label: some View {
        Text(text).font(font).lineLimit(1).fixedSize()
    }

    private func offset(at date: Date) -> CGFloat {
        let distance = textWidth + gap
        let run = TimeInterval(distance / speed)
        let t = date.timeIntervalSince(start).truncatingRemainder(dividingBy: pause + run)
        return t < pause ? 0 : CGFloat(t - pause) * speed
    }

    private func fade(active: Bool) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(active ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: 8)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(active ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 8)
        }
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
