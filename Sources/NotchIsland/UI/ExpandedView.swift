import SwiftUI

/// Giao diện khi rê chuột vào đảo: nhạc (hoặc hoạt động / trạng thái rảnh), không có đồng hồ hay nút phụ.
struct ExpandedView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Hàng ngang notch: để trống cho camera. Đang chỉnh âm lượng / độ sáng / đèn phím thì hiện đúng HUD
            // của chế độ thu gọn ở đây (icon trái, vòng giá trị phải) ngay trên phần nhạc, không đè lên nội dung.
            topRow

            content
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    private var topRow: some View {
        let notch = viewModel.geometry.notchSize
        let appearance = viewModel.settings.hudAppearance

        return ZStack {
            Color.clear
            if let hud = viewModel.hud {
                HUDView(event: hud, notchSize: notch, appearance: appearance, inline: true)
                    .frame(width: notch.width + IslandMetrics.hudWingWidth * 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .frame(height: notch.height)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: viewModel.hud == nil)
    }

    @ViewBuilder
    private var content: some View {
        let activities = viewModel.visibleActivities

        Group {
            switch viewModel.expandedLayout {
            case .media(let withActivity):
                if let playing = viewModel.visibleNowPlaying {
                    VStack(spacing: 8) {
                        NowPlayingCard(
                            info: playing,
                            compact: withActivity,
                            onCommand: viewModel.send,
                            onSeek: viewModel.seek,
                            onOpen: viewModel.openSource
                        )
                        .reveal()
                        .opacity(viewModel.isNowPlayingStale ? 0.5 : 1)
                        .animation(.easeInOut(duration: 0.25), value: viewModel.isNowPlayingStale)
                        if let first = activities.first {
                            ActivityRow(activity: first, extraCount: activities.count - 1, viewModel: viewModel)
                                .reveal(delay: 0.06)
                        }
                    }
                }
            case .activities:
                VStack(spacing: IslandMetrics.activityRowSpacing) {
                    ForEach(Array(activities.prefix(2).enumerated()), id: \.element.id) { index, activity in
                        ActivityRow(activity: activity, viewModel: viewModel)
                            .reveal(delay: Double(index) * 0.06)
                    }
                }
            case .idle:
                IdleCard(
                    battery: viewModel.battery,
                    onStartTimer: viewModel.startTimer,
                    onStartStopwatch: viewModel.startStopwatch
                )
            }
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: viewModel.expandedLayout)
    }
}

// MARK: - Now Playing

/// `compact`: bản thu gọn để chừa chỗ cho một hàng hoạt động bên dưới.
/// Bấm vào ảnh bìa / tên bài → mở nguồn (tab YouTube, app Spotify…).
struct NowPlayingCard: View {
    let info: NowPlayingInfo
    var compact = false
    let onCommand: (MediaCommand) -> Void
    let onSeek: (TimeInterval) -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: compact ? 6 : 10) {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: compact ? 10 : 14) {
                        ArtworkBadge(info: info, size: compact ? 40 : 58, showsAppIcon: true)

                        VStack(alignment: .leading, spacing: 3) {
                            MarqueeText(text: info.title, font: .system(size: compact ? 13 : 15, weight: .semibold))
                            MarqueeText(text: info.artist.isEmpty ? info.appName : info.artist,
                                        font: .system(size: compact ? 11.5 : 13))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Mở \(info.appName)")

                if compact {
                    controls
                } else {
                    EqualizerBars(isAnimating: info.isPlaying, color: info.accent, maxHeight: 16)
                }
            }

            if compact {
                ProgressRow(info: info, onSeek: onSeek)
            } else {
                HStack(spacing: 12) {
                    ProgressRow(info: info, onSeek: onSeek)
                    controls
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 6) {
            ControlButton(symbol: "backward.fill", size: 14) { onCommand(.previous) }
            ControlButton(symbol: info.isPlaying ? "pause.fill" : "play.fill", size: compact ? 16 : 20) {
                onCommand(.playPause)
            }
            ControlButton(symbol: "forward.fill", size: 14) { onCommand(.next) }
        }
    }
}

/// Thanh tiến trình tự chạy theo thời gian thực (nội suy giữa các lần cập nhật).
/// Ẩn khi nguồn không báo thời lượng (vd. livestream).
struct ProgressRow: View {
    let info: NowPlayingInfo
    let onSeek: (TimeInterval) -> Void

    /// Tỉ lệ đang kéo dở (0...1). Có giá trị → thanh bám theo ngón/chuột, không theo player.
    @State private var dragFraction: Double?
    /// Sau khi thả: giữ thanh ở vị trí vừa tua cho tới khi player báo vị trí mới (tránh nhảy giật về chỗ cũ).
    @State private var heldFraction: Double?

    var body: some View {
        // Nhịp 0,2 giây: số giây nhảy đúng lúc, lệch tối đa 0,2 giây (như YouTube: 0:00 → 0:01 → 0:02…).
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            if let duration = info.duration, duration > 0,
               let elapsed = info.currentElapsed(at: context.date) {
                let fraction = dragFraction ?? heldFraction ?? min(max(elapsed / duration, 0), 1)

                HStack(spacing: 8) {
                    Text(Self.format(fraction * duration))
                    scrubber(fraction: fraction, duration: duration)
                    Text(Self.format(duration))
                }
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            } else {
                Text(info.appName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Player đã báo vị trí mới → thôi giữ.
        .onChange(of: info.elapsed) { _ in heldFraction = nil }
        .onChange(of: info.title) { _ in
            dragFraction = nil
            heldFraction = nil
        }
        // Phòng khi player không báo lại: tự nhả sau 1,5 giây.
        .task(id: heldFraction) {
            guard heldFraction != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { heldFraction = nil }
        }
    }

    /// Thanh kéo được. Vùng bấm cao 16pt dù nét vẽ chỉ 4pt, để dễ nhắm.
    private func scrubber(fraction: Double, duration: TimeInterval) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule()
                    .fill(info.accent)
                    .frame(width: width * CGFloat(fraction))
            }
            .frame(height: dragFraction == nil ? 4 : 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragFraction = min(max(Double(value.location.x / width), 0), 1)
                    }
                    .onEnded { value in
                        let target = min(max(Double(value.location.x / width), 0), 1)
                        dragFraction = nil
                        heldFraction = target
                        onSeek(target * duration)
                    }
            )
            .animation(.easeOut(duration: 0.12), value: dragFraction == nil)
        }
        .frame(height: 16)
    }

    /// Cắt xuống giây nguyên, y như thanh của YouTube: 0:00 cho tới đúng 1,0 giây rồi mới sang 0:01.
    static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "--:--" }
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    var diameter: CGFloat = 30
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .symbolSwap()
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(.white.opacity(isHovering ? 0.16 : 0)))
                .scaleEffect(isHovering ? 1.06 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .animation(.easeInOut(duration: 0.2), value: symbol)
    }
}

// MARK: - Rảnh

/// Không có nhạc, không có hoạt động: một hàng duy nhất, gọn – pin bên trái, hẹn giờ / bấm giờ nhanh bên phải.
struct IdleCard: View {
    let battery: BatteryInfo
    let onStartTimer: (Int) -> Void
    let onStartStopwatch: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if battery.hasBattery {
                BatteryPill(info: battery)
                    .reveal()
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(width: 1, height: 22)
                    .reveal(delay: 0.03)
            }

            HStack(spacing: 6) {
                ForEach(Array([5, 10, 25].enumerated()), id: \.element) { index, minutes in
                    TimerChip(minutes: minutes, action: onStartTimer)
                        .reveal(delay: 0.05 + Double(index) * 0.04)
                }
                StopwatchChip(action: onStartStopwatch)
                    .reveal(delay: 0.19)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Pin dạng viên thuốc: biểu tượng pin + phần trăm, đổi màu theo mức / đang sạc.
struct BatteryPill: View {
    let info: BatteryInfo

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: info.symbolName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(info.tint)
            Text("\(info.level)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .help(info.remainingText ?? "Pin")
    }
}

struct TimerChip: View {
    let minutes: Int
    let action: (Int) -> Void
    @State private var isHovering = false

    var body: some View {
        Button { action(minutes) } label: {
            Text("\(minutes)\u{2032}")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(minWidth: 28)
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
                .background(Capsule().fill(.white.opacity(isHovering ? 0.22 : 0.1)))
                .scaleEffect(isHovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("Hẹn giờ \(minutes) phút")
    }
}

struct StopwatchChip: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "stopwatch")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 24)
                .background(Capsule().fill(.white.opacity(isHovering ? 0.22 : 0.1)))
                .scaleEffect(isHovering ? 1.06 : 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help("Bấm giờ")
    }
}
