import SwiftUI

/// Hai "cánh" hai bên notch, phần giữa bỏ trống vì bị camera che.
/// Trái: ảnh bìa nhạc (hoặc biểu tượng hoạt động nếu không có nhạc).
/// Phải: đồng hồ của hoạt động chính (hẹn giờ, cuộc gọi, ghi âm…) hoặc sóng nhạc.
struct CompactView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: IslandMetrics.compactWingWidth)
            Spacer(minLength: viewModel.geometry.notchSize.width)
            trailing
                .frame(width: IslandMetrics.compactWingWidth)
        }
        .padding(.horizontal, 2)
        // Căn giữa theo chiều dọc trong đúng chiều cao notch (khung cha căn mép trên nên phải chiếm đủ chiều cao).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var leading: some View {
        if let playing = viewModel.visibleNowPlaying {
            ArtworkBadge(info: playing, size: 22)
        } else if let activity = viewModel.primaryActivity {
            Image(systemName: activity.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(activity.tint)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if let activity = viewModel.primaryActivity {
            ActivityWing(activity: activity)
        } else if let playing = viewModel.visibleNowPlaying {
            EqualizerBars(isAnimating: playing.isPlaying, color: playing.accent)
        }
    }
}

/// Ảnh bìa thật nếu có; không thì ô gradient theo màu nhấn + nốt nhạc.
/// `showsAppIcon` gắn icon app nguồn (Chrome, Spotify…) ở góc dưới phải.
struct ArtworkBadge: View {
    let info: NowPlayingInfo
    let size: CGFloat
    var showsAppIcon = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)

        ZStack {
            if let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [info.accent, info.accent.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(alignment: .bottomTrailing) {
            if showsAppIcon, let icon = info.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: size * 0.38, height: size * 0.38)
                    .offset(x: size * 0.1, y: size * 0.1)
            }
        }
        .id(info.artworkID)
        .transition(.opacity)
    }
}

/// Cột sóng nhạc chuyển động liên tục khi đang phát.
struct EqualizerBars: View {
    let isAnimating: Bool
    let color: Color
    var barCount = 4
    var maxHeight: CGFloat = 14

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: maxHeight * level(index: index, time: time))
                }
            }
            .frame(height: maxHeight)
        }
    }

    private func level(index: Int, time: TimeInterval) -> CGFloat {
        guard isAnimating else { return 0.3 }
        let phase = time * (3.0 + Double(index) * 0.9) + Double(index) * 1.3
        return CGFloat(0.3 + 0.7 * abs(sin(phase)))
    }
}
