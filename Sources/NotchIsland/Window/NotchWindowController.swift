import AppKit
import Combine
import SwiftUI

/// Định vị panel, theo dõi chuột để mở/thu island và bật/tắt click-through.
@MainActor
final class NotchWindowController: NSObject {
    private let viewModel: IslandViewModel
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var pollTimer: Timer?
    private var collapseTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel
        let frame = NSRect(origin: .zero, size: IslandMetrics.panelSize)
        self.panel = NotchPanel(contentRect: frame)
        super.init()

        let host = IslandHostingView(rootView: IslandRootView(viewModel: viewModel))
        host.frame = frame
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Đổi màn hình hiển thị trong Cài đặt → đặt lại vị trí ngay.
        viewModel.settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
        startTrackingMouse()
    }

    // MARK: - Vị trí

    @objc private func screenParametersChanged() {
        reposition()
    }

    private func reposition() {
        guard let screen = NotchGeometry.preferredScreen(displayID: viewModel.settings.displayID) else { return }
        let geometry = NotchGeometry.measure(screen)
        viewModel.updateGeometry(geometry)

        let size = IslandMetrics.panelSize
        let origin = CGPoint(
            x: geometry.screenFrame.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// Hình chữ nhật của island theo toạ độ màn hình (gốc ở dưới-trái).
    private func islandRect() -> CGRect {
        let screen = viewModel.geometry.screenFrame
        let size = viewModel.contentSize
        let width = size.width + IslandMetrics.earRadius * 2
        // Đang mở thì vùng "còn ở trong" rộng hơn một chút (trễ hai chiều): thu lại ngay khi rời hẳn mà không nhấp nháy ở mép.
        let padding = viewModel.isExpanded ? IslandMetrics.hoverPadding + 6 : IslandMetrics.hoverPadding
        return CGRect(
            x: screen.midX - width / 2,
            y: screen.maxY - size.height,
            width: width,
            height: size.height
        ).insetBy(dx: -padding, dy: -padding)
    }

    // MARK: - Chuột

    private func startTrackingMouse() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]

        // Global monitor với sự kiện chuột KHÔNG cần quyền Accessibility.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.evaluateMouse()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.evaluateMouse()
            return event
        }) {
            monitors.append(local)
        }

        // Lưới an toàn: kiểm tra 5 lần/giây phòng khi sự kiện bị lỡ (vd. chuột rời màn hình).
        let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(pollMouse), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    @objc private func pollMouse() {
        evaluateMouse()
    }

    private func evaluateMouse() {
        // Đang giữ chuột (vd. kéo thanh tiến trình) khi island đã mở: giữ nguyên trạng thái,
        // kẻo kéo lệch ra ngoài là island tự thu lại và cướp mất thao tác.
        if viewModel.isExpanded, NSEvent.pressedMouseButtons != 0 { return }

        let inside = islandRect().contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside

        if inside {
            collapseTask?.cancel()
            collapseTask = nil
            if viewModel.settings.hoverToExpand {
                viewModel.setExpanded(true)
            }
        } else if viewModel.isExpanded, collapseTask == nil {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(IslandMetrics.collapseDelay * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.viewModel.setExpanded(false)
                self.collapseTask = nil
            }
        }
    }
}
