import AppKit
import Combine
import SwiftUI

/// Ambient light: ánh sáng mềm toả vào từ viền màn hình theo màu nội dung đang hiển thị (kiểu Ambilight / YouTube ambient mode,
/// nhưng cho mọi trang và mọi app). Cửa sổ trong suốt, click xuyên qua, nằm dưới island.
@MainActor
final class AmbientLightController {
    private let settings: AppSettings
    private let viewModel: IslandViewModel
    private let service = AmbientLightService()
    private let model = AmbientModel()
    private var panel: NotchPanel?
    private var running = false
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings, viewModel: IslandViewModel) {
        self.settings = settings
        self.viewModel = viewModel

        service.onColors = { [weak self] colors in self?.model.colors = colors }
        // Hệ thống dừng luồng chụp (đổi màn hình, mất quyền…): tắt công tắc để người dùng thấy và bật lại.
        service.onStop = { [weak self] in self?.stop() }

        // Đổi cài đặt, khoá / mở máy, đổi màn hình → xét lại. (Merge, không combineLatest: không cần cả ba cùng phát trước.)
        Publishers.Merge3(
            settings.objectWillChange.map { _ in () },
            viewModel.$isLocked.map { _ in () },
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in () }
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
        refresh()
    }

    private func refresh() {
        model.intensity = settings.ambientIntensity
        // Khoá màn hình thì dừng chụp (không có gì để chiếu, và đỡ tốn pin).
        let wanted = settings.ambientLight && !viewModel.isLocked
        if wanted { start() } else { stop() }
    }

    private func start() {
        guard !running, let screen = NotchGeometry.preferredScreen(displayID: settings.displayID) else { return }
        running = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()

        Task { [weak self] in
            guard let self else { return }
            let started = await self.service.start(displayID: screen.displayID)
            if started, !self.running {   // người dùng đã tắt trong lúc đang khởi động
                self.service.stop()
            } else if !started {
                // Chưa có quyền Ghi màn hình: tắt công tắc (macOS vừa hiện hộp thoại xin quyền).
                self.stop()
                if !AmbientLightService.hasPermission {
                    self.settings.ambientLight = false
                    Self.explainPermission()
                }
            }
        }
    }

    private func stop() {
        guard running else { return }
        running = false
        service.stop()
        panel?.orderOut(nil)
        model.colors = nil
    }

    /// macOS chỉ áp dụng quyền Ghi màn hình sau khi mở lại app, nên nói rõ hai bước.
    private static func explainPermission() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Cần quyền Ghi màn hình"
        alert.informativeText = "Để lấy màu nội dung màn hình, hãy bật NotchIsland trong danh sách Ghi màn hình, rồi thoát và mở lại app, sau đó bật lại Ambient light. Hình không được lưu hay gửi đi."
        alert.addButton(withTitle: "Mở Cài đặt hệ thống")
        alert.addButton(withTitle: "Để sau")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func makePanel() -> NotchPanel {
        let panel = NotchPanel(contentRect: .zero)
        // Trên thanh menu nhưng dưới island (island ở mainMenu + 3).
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: AmbientView(model: model))
        return panel
    }
}

final class AmbientModel: ObservableObject {
    @Published var colors: AmbientColors?
    @Published var intensity = 0.7
}

/// Bốn dải màu mờ dần từ mép vào trong, cộng sáng (plusLighter) lên nội dung bên dưới.
struct AmbientView: View {
    @ObservedObject var model: AmbientModel

    private static let thickness: CGFloat = 110

    var body: some View {
        ZStack {
            if let colors = model.colors {
                edge(colors.top, at: .top)
                edge(colors.bottom, at: .bottom)
                edge(colors.left, at: .leading)
                edge(colors.right, at: .trailing)
            }
        }
        .opacity(model.intensity)
        .animation(.linear(duration: 0.15), value: model.colors)
        .allowsHitTesting(false)
    }

    /// Một dải dọc theo cạnh `side`: màu chạy dọc cạnh, đậm ở mép và tan dần vào trong.
    private func edge(_ colors: [AmbientColors.RGB], at side: UnitPoint) -> some View {
        let vertical = side == .leading || side == .trailing
        let palette = colors.map { Color(red: $0.r, green: $0.g, blue: $0.b) }
        return Rectangle()
            .fill(LinearGradient(colors: palette.isEmpty ? [.clear] : palette,
                                 startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing))
            .saturation(1.4)
            .blur(radius: 24)
            .mask(LinearGradient(colors: [.white, .clear], startPoint: side, endPoint: UnitPoint(x: 1 - side.x, y: 1 - side.y)))
            .blendMode(.plusLighter)
            .frame(width: vertical ? Self.thickness : nil, height: vertical ? nil : Self.thickness)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: side.x == 1 ? .trailing : .leading,
                                                                                      vertical: side.y == 1 ? .bottom : .top))
    }
}
