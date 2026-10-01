import Foundation

/// Biết Mac đang khoá hay đã mở khoá, qua thông báo phân tán của hệ thống.
final class LockStateMonitor {
    var onChange: ((Bool) -> Void)?
    private var tokens: [NSObjectProtocol] = []

    func start() {
        guard tokens.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        tokens.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.onChange?(true) })
        tokens.append(center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in self?.onChange?(false) })
    }

    deinit {
        tokens.forEach { DistributedNotificationCenter.default().removeObserver($0) }
    }
}
