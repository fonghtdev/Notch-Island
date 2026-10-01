import SwiftUI

/// HUD âm lượng / độ sáng màn hình / đèn bàn phím.
/// Hàng trên ngang notch: icon trái, giá trị phải. Bên dưới (trừ kiểu vòng) là thanh hoặc vạch.
struct HUDView: View {
    let event: HUDEvent
    let notchSize: CGSize
    let appearance: HUDAppearance

    private var tint: Color { appearance.color(for: event.kind) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: event.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: IslandMetrics.compactWingWidth)

                Spacer(minLength: notchSize.width)

                trailing
                    .frame(width: IslandMetrics.compactWingWidth)
            }
            .frame(height: notchSize.height)

            switch appearance.style {
            case .bar:
                HUDBar(value: event.displayValue, tint: tint, appearance: appearance)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .frame(height: appearance.extraHeight, alignment: .top)
            case .segments:
                HUDSegments(value: event.displayValue, tint: tint, appearance: appearance)
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .frame(height: appearance.extraHeight, alignment: .top)
            case .ring:
                EmptyView()
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var trailing: some View {
        if appearance.style == .ring {
            HUDRing(value: event.displayValue, tint: tint, appearance: appearance)
        } else if appearance.showsPercent {
            Text(event.isMuted ? "Tắt" : "\(Int((event.displayValue * 100).rounded()))")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        } else {
            Color.clear
        }
    }
}

/// Thanh liền.
struct HUDBar: View {
    let value: Double
    let tint: Color
    let appearance: HUDAppearance

    var body: some View {
        let height = appearance.barHeight
        let radius = appearance.corner.radius(forHeight: height)

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(0.18))
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(tint)
                    .frame(width: value > 0 ? max(height, proxy.size.width * CGFloat(value)) : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

/// 16 vạch như HUD của macOS.
struct HUDSegments: View {
    static let count = 16

    let value: Double
    let tint: Color
    let appearance: HUDAppearance

    var body: some View {
        let height = appearance.barHeight + 2
        let filled = Int((value * Double(Self.count)).rounded())

        HStack(spacing: 2) {
            ForEach(0..<Self.count, id: \.self) { index in
                RoundedRectangle(
                    cornerRadius: min(appearance.corner.radius(forHeight: height), 3),
                    style: .continuous
                )
                .fill(index < filled ? tint : Color.white.opacity(0.18))
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.08), value: filled)
    }
}

/// Vòng tròn nhỏ đặt ở cánh phải.
struct HUDRing: View {
    let value: Double
    let tint: Color
    let appearance: HUDAppearance

    var body: some View {
        let line = max(2.5, appearance.barHeight * 0.6)

        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: line)
            Circle()
                .trim(from: 0, to: CGFloat(value))
                .stroke(tint, style: StrokeStyle(
                    lineWidth: line,
                    lineCap: appearance.corner == .square ? .butt : .round
                ))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}
