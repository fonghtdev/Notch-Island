import SwiftUI

/// Gốc của UI: vẽ hình island và chọn nội dung theo `IslandMode`.
struct IslandRootView: View {
    @ObservedObject var viewModel: IslandViewModel

    var body: some View {
        let size = viewModel.contentSize
        let ear = viewModel.earRadius
        let isExpanded = viewModel.mode == .expanded

        ZStack(alignment: .top) {
            background(ear: ear)
                .frame(width: size.width + ear * 2, height: size.height)
                .shadow(color: .black.opacity(isExpanded ? 0.45 : 0), radius: 18, y: 8)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.handleTap() }

            content
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(viewModel.mode == .expanded ? IslandMetrics.spring : IslandMetrics.closeSpring, value: viewModel.mode)
        // Đang mở mà nội dung đổi (nhạc bắt đầu / hết, thêm hẹn giờ…) → island co giãn mượt theo.
        .animation(IslandMetrics.spring, value: viewModel.expandedLayout)
        .animation(IslandMetrics.spring, value: viewModel.geometry)
        .environment(\.colorScheme, .dark)
        .environment(\.islandGlass, viewModel.settings.islandStyle == .glass && IslandSurface.supportsLiquidGlass)
    }

    /// Nội dung các chế độ nhỏ: hiện nhanh, tắt nhanh – kích thước island mới là thứ chuyển động.
    private static let fade = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.04)),
        removal: .opacity.animation(.easeOut(duration: 0.1))
    )

    /// Nền island. Trên máy có notch thật, lúc thu gọn luôn đen để liền khối với notch;
    /// kính chỉ hiện khi island nở ra. Máy không có notch thì kính ở mọi trạng thái.
    private func background(ear: CGFloat) -> some View {
        let shape = NotchShape(earRadius: ear, bottomRadius: viewModel.bottomRadius)
        let surface = viewModel.settings.islandSurface
        let staysBlack = viewModel.mode == .collapsed && viewModel.geometry.hasPhysicalNotch
        let isSolid = surface.style == .solid

        return ZStack {
            shape.fill(Color.black)
                .opacity(isSolid || staysBlack ? 1 : 0)

            if !isSolid {
                IslandBackground(shape: shape, surface: surface)
                    .opacity(staysBlack ? 0 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: staysBlack)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.mode {
        case .collapsed:
            Color.clear
        case .compact:
            CompactView(viewModel: viewModel)
                .transition(Self.fade)
        case .banner:
            BannerView(viewModel: viewModel)
                .transition(Self.fade)
        case .hud:
            if let hud = viewModel.hud {
                HUDView(
                    event: hud,
                    notchSize: viewModel.geometry.notchSize,
                    appearance: viewModel.settings.hudAppearance
                )
                .transition(Self.fade)
            }
        case .expanded:
            ExpandedView(viewModel: viewModel)
                .transition(.asymmetric(
                    // Vào: chờ island nở ra một chút rồi mới hiện chữ. Ra: biến mất ngay để không còn nội dung "treo" trong lúc thu.
                    insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)).animation(.easeOut(duration: 0.22).delay(0.05)),
                    removal: .opacity.animation(.easeOut(duration: 0.1))
                ))
        }
    }
}
