import SwiftUI

/// Thẻ thông báo ngắn nở xuống dưới notch: cắm/rút sạc, tai nghe, hết giờ.
struct BannerView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        Group {
            switch viewModel.visibleTransient {
            case .charging(let info)?:
                PowerBanner(info: info, isPlugged: true, notch: viewModel.geometry.notchSize)
            case .unplugged(let info)?:
                PowerBanner(info: info, isPlugged: false, notch: viewModel.geometry.notchSize)
            default:
                VStack(spacing: 0) {
                    // Hàng ngang notch: để trống cho camera.
                    Color.clear.frame(height: viewModel.geometry.notchSize.height)

                    transientContent
                        .padding(.horizontal, 18)
                        .padding(.bottom, 10)
                        .frame(maxHeight: .infinity)
                }
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var transientContent: some View {
        switch viewModel.visibleTransient {
        case .headphones(let info)?:
            HeadphoneBanner(info: latest(of: info))
        case .timerFinished(let label)?:
            TimerDoneBanner(label: label)
        case .notification(let item)?:
            NotificationBanner(item: item)
        case .farewell?:
            FarewellBanner()
        case .welcome?:
            WelcomeBanner()
        case .charging?, .unplugged?, nil:
            EmptyView()
        }
    }

    /// Ưu tiên bản mới nhất của thiết bị đang kết nối (pin được đọc trễ sau lúc kết nối).
    private func latest(of info: HeadphoneInfo) -> HeadphoneInfo {
        if info.isConnected, let live = viewModel.headphones, live.id == info.id { return live }
        return info
    }
}

// MARK: - Cắm / rút sạc

/// Thẻ cắm / rút sạc, tối giản: hàng notch có tia chớp bên trái và phần trăm bên phải (hai bên camera),
/// bên dưới là một thanh pin mảnh chạy đầy tới mức hiện tại và một dòng chữ.
struct PowerBanner: View {
    let info: BatteryInfo
    let isPlugged: Bool
    let notch: CGSize

    @State private var shown = false
    @State private var displayLevel: Double = 0

    private var tint: Color {
        if isPlugged { return .green }
        return info.level <= 20 ? .red : .white
    }

    private var title: String {
        if isPlugged { return info.isCharging ? "Đang sạc" : "Đã cắm nguồn" }
        return info.level <= 20 ? "Pin yếu" : "Đã rút sạc"
    }

    private var detail: String? {
        if isPlugged {
            var parts: [String] = []
            if info.isCharging {
                if let remaining = info.remainingText { parts.append(remaining) }
            } else if info.level >= 99 {
                parts.append("Pin đã đầy")
            }
            if let watts = info.adapterWatts { parts.append("\(watts)W") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        return info.remainingText
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hàng ngang notch: biểu tượng | (camera) | phần trăm.
            HStack(spacing: 0) {
                PowerGlyph(isPlugged: isPlugged, isCharging: info.isCharging, tint: tint)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: notch.width)
                CountingPercent(value: displayLevel)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity)
            }
            .frame(height: notch.height)

            VStack(spacing: 9) {
                PowerBar(progress: displayLevel / 100, tint: tint, isShimmering: info.isCharging)
                    .frame(height: 5)

                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.bottom, 6)
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 5)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.86).delay(0.08)) { shown = true }
            withAnimation(.easeOut(duration: 0.95).delay(0.12)) { displayLevel = Double(min(max(info.level, 0), 100)) }
        }
    }
}

/// Tia chớp (đang sạc) / tia chớp gạch (rút sạc) trên một quầng sáng mềm; nảy vào khi xuất hiện.
struct PowerGlyph: View {
    let isPlugged: Bool
    let isCharging: Bool
    let tint: Color

    @State private var appeared = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.35))
                .frame(width: 22, height: 22)
                .blur(radius: 9)
                .opacity(isCharging ? (breathe ? 1 : 0.4) : 0.5)

            Image(systemName: isPlugged ? "bolt.fill" : "bolt.slash.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .symbolSwap()
        }
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.58).delay(0.05)) { appeared = true }
            if isCharging {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true).delay(0.5)) { breathe = true }
            }
        }
    }
}

/// Thanh pin mảnh. Khi đang sạc có vệt sáng chạy dọc phần đã đầy.
struct PowerBar: View {
    let progress: Double
    let tint: Color
    let isShimmering: Bool

    @State private var sweep = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(width * CGFloat(min(max(progress, 0), 1)), 0)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: fill)
                    .overlay(alignment: .leading) {
                        if isShimmering {
                            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: 36)
                                .offset(x: sweep ? fill : -36)
                        }
                    }
                    .clipShape(Capsule())
            }
        }
        .onAppear {
            guard isShimmering else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false).delay(1)) { sweep = true }
        }
    }
}

// MARK: - Tai nghe

struct HeadphoneBanner: View {
    let info: HeadphoneInfo

    var body: some View {
        HStack(spacing: 14) {
            HeadphoneIcon(model: info.model, isConnected: info.isConnected)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 6) {
                Text(info.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Circle()
                        .fill(info.isConnected ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(info.isConnected ? "Đã kết nối" : "Đã ngắt kết nối")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                }

                if info.isConnected { batteryRow }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var batteryRow: some View {
        if info.left != nil || info.right != nil || info.caseLevel != nil {
            HStack(spacing: 5) {
                if let left = info.left { BatteryChip(label: "L", value: left) }
                if let right = info.right { BatteryChip(label: "R", value: right) }
                if let caseLevel = info.caseLevel { BatteryChip(label: "Hộp", value: caseLevel) }
            }
        } else if let level = info.main {
            BatteryChip(label: "Pin", value: level)
        } else {
            Text("Đang đọc pin…")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct BatteryChip: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Text("\(value)%").monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .foregroundStyle(value <= 20 ? Color.red : Color.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.12)))
    }
}

// MARK: - Hết giờ

struct TimerDoneBanner: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            BannerIcon(symbol: "bell.fill", tint: .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hết giờ")
                    .font(.system(size: 13.5, weight: .semibold))
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
}

/// Biểu tượng tròn dùng chung cho các banner một dòng (hết giờ, thông báo): vòng màu nhạt + biểu tượng cùng màu.
struct BannerIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 38, height: 38)
            .background(Circle().fill(tint.opacity(0.18)))
    }
}

// MARK: - Lời cảm ơn khi gỡ cài đặt

struct FarewellBanner: View {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.pink)
                .scaleEffect(shown ? 1 : 0.3)
            Text("Cảm ơn bạn đã sử dụng NotchIsland")
                .font(.system(size: 13, weight: .semibold))
            Text("Nếu có điều gì khiến bạn chưa hài lòng, hãy góp ý với mình qua fonght.dev@gmail.com")
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.6))
        }
        .opacity(shown ? 1 : 0)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) { shown = true } }
        }
    }
}

// MARK: - Lời chào lần chạy đầu

struct WelcomeBanner: View {
    private static let greetings = ["hello", "xin chào"]
    @State private var index = 0
    @State private var progress: CGFloat = 0
    @State private var showHint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if showHint {
                (Text("Nhấn biểu tượng ") + Text(Image(systemName: "capsule.fill")) + Text(" trên thanh menu\nđể vào Cài đặt và tùy chỉnh theo cá nhân"))
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                Text(Self.greetings[index])
                    .font(.custom("Snell Roundhand", size: 34))
                    .fixedSize()
                    .mask(alignment: .leading) {
                        GeometryReader { proxy in
                            Rectangle().frame(width: proxy.size.width * progress)
                        }
                    }
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { write() }
    }

    private func write() {
        progress = 0
        // Giảm chuyển động: chữ hiện đủ ngay, không "viết" từ trái sang phải.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.6)) { progress = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if index + 1 < Self.greetings.count {
                index += 1
                write()
            } else {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { showHint = true }
            }
        }
    }
}

// MARK: - Thông báo từ iPhone

struct NotificationBanner: View {
    let item: NotificationItem

    var body: some View {
        HStack(spacing: 12) {
            BannerIcon(symbol: "iphone", tint: .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "iPhone" : item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(item.body.isEmpty ? item.subtitle : item.body)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
}
