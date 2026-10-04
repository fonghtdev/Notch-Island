import SwiftUI

/// Nội dung thẻ trên màn hình khoá: nhạc, hoạt động đang diễn ra, thông báo.
struct LockScreenView: View {
    /// Thẻ dọc (kiểu trình phát nhạc trên điện thoại): hẹp và cao.
    static let width: CGFloat = 360

    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        VStack(spacing: 12) {
            if let playing = viewModel.visibleNowPlaying {
                LockNowPlayingCard(
                    info: playing,
                    onCommand: viewModel.send, onSeek: viewModel.seek, onOpen: viewModel.openSource
                )
            }

            ForEach(viewModel.visibleActivities) { activity in
                ActivityRow(activity: activity, viewModel: viewModel)
            }

            if !viewModel.visibleNotifications.isEmpty {
                VStack(spacing: 8) {
                    ForEach(viewModel.visibleNotifications) { item in
                        NotificationRow(item: item) { viewModel.dismissNotification(item.id) }
                    }
                }
                .padding(.top, viewModel.visibleNowPlaying == nil && viewModel.visibleActivities.isEmpty ? 0 : 4)
            }
        }
        .padding(22)
        .frame(width: LockScreenView.width)
        .background(cardBackground)
        .animation(.easeInOut(duration: 0.4), value: viewModel.visibleNowPlaying?.artworkID)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environment(\.islandGlass, viewModel.settings.islandStyle != .frosted && IslandSurface.supportsLiquidGlass)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension LockScreenView {
    /// Nền Liquid Glass (mặc định, giống tuỳ chọn trong Cài đặt); máy chưa hỗ trợ tự lùi về kính mờ.
    /// Người dùng chọn "Kính mờ" thì theo; "Đen" thì thẻ vẫn dùng kính để đọc được trên hình nền.
    var cardBackground: some View {
        let settings = viewModel.settings
        let style: IslandBackgroundStyle = settings.islandStyle == .solid ? .glass : settings.islandStyle
        let surface = IslandSurface(
            style: style, isClear: settings.glassClear,
            tint: settings.glassTint, tintStrength: settings.glassTintStrength
        )
        let shape = RoundedRectangle(cornerRadius: 30, style: .continuous)

        return ZStack {
            IslandBackground(shape: shape, surface: surface)
            // Ánh màu chủ đạo của ảnh bìa, rất nhẹ: thẻ đổi sắc theo bài nhưng vẫn là kính.
            LinearGradient(
                colors: [(viewModel.visibleNowPlaying?.accent ?? .clear).opacity(0.22), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .clipShape(shape)
            .allowsHitTesting(false)
        }
    }
}

struct NotificationRow: View {
    let item: NotificationItem
    let onDismiss: () -> Void

    /// "Vừa xong" / "5 phút" / "2 giờ": gọn, không có giây.
    static func age(of date: Date, at now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        switch minutes {
        case 0: return "Vừa xong"
        case 1..<60: return "\(minutes) phút"
        default: return "\(minutes / 60) giờ"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let icon = AppCatalog.icon(for: item.bundleIdentifier) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "bell.fill").foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.title.isEmpty ? AppCatalog.name(for: item.bundleIdentifier) : item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(Self.age(of: item.date, at: context.date))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                }
                if !item.body.isEmpty {
                    Text(item.body)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
    }
}

// MARK: - Thẻ nhạc dọc cho màn hình khoá

/// Bố cục kiểu trình phát trên điện thoại: tên bài + nghệ sĩ ở trên, ảnh bìa vuông lớn ở giữa,
/// thanh tiến trình, rồi ba nút lùi / phát-dừng / tới.
struct LockNowPlayingCard: View {
    let info: NowPlayingInfo
    let onCommand: (MediaCommand) -> Void
    let onSeek: (TimeInterval) -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        MarqueeText(text: info.title, font: .system(size: 19, weight: .bold))
                        MarqueeText(text: info.artist.isEmpty ? info.appName : info.artist,
                                    font: .system(size: 14.5))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    EqualizerBars(isAnimating: info.isPlaying, color: .white.opacity(0.9), maxHeight: 16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            artwork

            ProgressRow(info: info, onSeek: onSeek)

            HStack(spacing: 30) {
                ControlButton(symbol: "backward.fill", label: "Bài trước", size: 22, diameter: 48) { onCommand(.previous) }
                Button { onCommand(.playPause) } label: {
                    Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .symbolSwap()
                        .foregroundStyle(.black)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(.white))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(info.isPlaying ? "Tạm dừng" : "Phát")
                .animation(.easeInOut(duration: 0.2), value: info.isPlaying)
                ControlButton(symbol: "forward.fill", label: "Bài tiếp", size: 22, diameter: 48) { onCommand(.next) }
            }
        }
    }

    /// Ảnh bìa theo đúng tỉ lệ gốc: vuông (album) hoặc chữ nhật ngang (video). Lúc tạm dừng thu nhỏ nhẹ như Spotify.
    private var artwork: some View {
        let aspect = max(info.artwork.map { $0.size.width / max($0.size.height, 1) } ?? 1, 0.5)
        let landscape = aspect > 1.2
        let width: CGFloat = landscape ? 316 : 264
        let height: CGFloat = landscape ? width / min(aspect, 2.0) : width
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return ZStack {
            if let image = info.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [info.accent, info.accent.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .id(info.artworkID)
        .transition(.opacity)
        .shadow(color: info.accent.opacity(0.5), radius: 24, y: 10)
        .scaleEffect(info.isPlaying ? 1 : 0.92)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: info.isPlaying)
        .animation(.easeInOut(duration: 0.35), value: info.artworkID)
    }
}
