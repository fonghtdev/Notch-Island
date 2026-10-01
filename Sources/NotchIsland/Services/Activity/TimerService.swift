import Foundation

/// Hẹn giờ của chính app (macOS không cho app khác đọc hẹn giờ của ứng dụng Đồng hồ).
/// Chạy trên main thread.
final class TimerService {
    struct State: Equatable {
        var label: String
        var endsAt: Date
        /// Khác nil → đang tạm dừng, đây là số giây còn lại.
        var pausedRemaining: TimeInterval?
    }

    var onChange: ((State?) -> Void)?
    /// Hết giờ (tham số: nhãn, vd. "10 phút").
    var onFinish: ((String) -> Void)?

    private(set) var state: State? {
        didSet { if state != oldValue { onChange?(state) } }
    }
    private var ticker: Timer?

    func start(minutes: Int) {
        let seconds = TimeInterval(max(1, minutes) * 60)
        state = State(label: "\(minutes) phút", endsAt: Date().addingTimeInterval(seconds), pausedRemaining: nil)
        startTicker()
    }

    func togglePause() {
        guard var current = state else { return }
        if let remaining = current.pausedRemaining {
            current.endsAt = Date().addingTimeInterval(remaining)
            current.pausedRemaining = nil
        } else {
            current.pausedRemaining = max(0, current.endsAt.timeIntervalSinceNow)
        }
        state = current
    }

    func cancel() {
        ticker?.invalidate()
        ticker = nil
        state = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let current = state, current.pausedRemaining == nil, current.endsAt <= Date() else { return }
        ticker?.invalidate()
        ticker = nil
        state = nil
        onFinish?(current.label)
    }
}
