import Foundation

/// Bấm giờ của chính app (đếm lên). Chạy trên main thread.
final class StopwatchService {
    struct State: Equatable {
        var startedAt: Date
        /// Khác nil → đang tạm dừng, đây là số giây đã trôi.
        var pausedElapsed: TimeInterval?
    }

    var onChange: ((State?) -> Void)?

    private(set) var state: State? {
        didSet { if state != oldValue { onChange?(state) } }
    }

    func start() {
        state = State(startedAt: Date(), pausedElapsed: nil)
    }

    func togglePause() {
        guard var current = state else { return }
        if let elapsed = current.pausedElapsed {
            current.startedAt = Date().addingTimeInterval(-elapsed)
            current.pausedElapsed = nil
        } else {
            current.pausedElapsed = Date().timeIntervalSince(current.startedAt)
        }
        state = current
    }

    func reset() { state = nil }
}
