import AppKit
import Combine
import SwiftUI

/// Thẻ hiện giữa màn hình khoá: nhạc đang phát, hoạt động (cuộc gọi Discord, hẹn giờ…), thông báo.
/// Chỉ hiện khi Mac đang khoá VÀ có nội dung; nằm trong Space riêng của `SkyLightSpace` để vẽ đè lên màn hình khoá.
@MainActor
final class LockScreenController {
    private let viewModel: IslandViewModel
    private let panel: NotchPanel
    private let host: IslandHostingView<LockScreenView>
    private var cancellables = Set<AnyCancellable>()

    private static let width: CGFloat = LockScreenView.width
    /// Tâm thẻ cách đỉnh màn hình bao nhiêu phần chiều cao: nằm giữa đáy đồng hồ lớn (~26%) và đỉnh avatar (~87%).
    private static let centerFraction: CGFloat = 0.565
    /// Khoảng thở tối thiểu bên dưới đồng hồ (phần chiều cao màn hình).
    private static let minTopFraction: CGFloat = 0.30

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200))
        host = IslandHostingView(rootView: LockScreenView(viewModel: viewModel))
        panel.contentView = host
        // Khác island chính: thẻ này phải bấm được (nút phát/dừng…) và không được bắt chuột khi đang ẩn.
        panel.ignoresMouseEvents = false

        viewModel.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private var shouldShow: Bool {
        viewModel.isLocked && viewModel.settings.showOnLockScreen && viewModel.hasLockScreenContent
    }

    private func refresh() {
        guard shouldShow else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        guard let screen = NotchGeometry.preferredScreen(displayID: viewModel.settings.displayID) else { return }

        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        let height = min(max(fitting.height, 60), screen.frame.height * 0.7)
        // Căn giữa khoảng trống giữa đồng hồ và avatar; thẻ quá cao thì đẩy xuống vừa đủ để không đè đồng hồ.
        let topOffset = max(
            screen.frame.height * Self.centerFraction - height / 2,
            screen.frame.height * Self.minTopFraction
        )
        let frame = NSRect(
            x: screen.frame.midX - Self.width / 2,
            y: screen.frame.maxY - topOffset - height,
            width: Self.width,
            height: height
        )
        panel.setFrame(frame, display: true)

        panel.orderFrontRegardless()
        // Phải chuyển vào Space riêng SAU khi cửa sổ đã hiện.
        SkyLightSpace.shared.attach(panel)
    }
}
