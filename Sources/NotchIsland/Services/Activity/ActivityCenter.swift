import AppKit
import SwiftUI

/// Gom mọi "live activity" thành một danh sách đã xếp ưu tiên:
/// hẹn giờ / bấm giờ của app, hẹn giờ / bấm giờ của app Đồng hồ (hệ thống), micro / camera của app khác.
final class ActivityCenter {
    var onChange: (([LiveActivity]) -> Void)?
    var onTimerFinished: ((String) -> Void)?

    private let timer = TimerService()
    private let stopwatch = StopwatchService()
    private let capture = CaptureMonitor()
    private let clock = SystemClockMonitor()
    private let phone = PhoneCallMonitor()

    private var timerActivity: LiveActivity?
    private var stopwatchActivity: LiveActivity?
    private var captureActivities: [LiveActivity] = []
    private var clockActivities: [LiveActivity] = []
    private var phoneActivities: [LiveActivity] = []
    private var captureEnabled = false

    /// Bản ghi âm đã bị bấm tạm dừng từ island. Khi tạm dừng app ghi âm có thể nhả micro (hoạt động biến mất khỏi
    /// CoreAudio), nên giữ lại một hàng "đã tạm dừng" để còn bấm tiếp tục được.
    private struct PausedRecording {
        var activity: LiveActivity
        var elapsed: TimeInterval
    }
    private var pausedRecordings: [String: PausedRecording] = [:]

    func start() {
        timer.onChange = { [weak self] state in
            self?.timerActivity = state.map(Self.activity(from:))
            self?.publish()
        }
        timer.onFinish = { [weak self] label in self?.onTimerFinished?(label) }
        stopwatch.onChange = { [weak self] state in
            self?.stopwatchActivity = state.map(Self.activity(from:))
            self?.publish()
        }
        capture.onChange = { [weak self] list in
            self?.captureActivities = list
            self?.publish()
        }
        clock.onChange = { [weak self] list in
            self?.clockActivities = list
            self?.publish()
        }
        phone.onChange = { [weak self] list in
            self?.phoneActivities = list
            self?.publish()
        }
    }

    /// Bật/tắt theo công tắc "Hoạt động đang diễn ra" trong Cài đặt.
    func setEnabled(_ enabled: Bool) {
        guard enabled != captureEnabled else { return }
        captureEnabled = enabled
        if enabled {
            capture.start()
            clock.start()
            phone.start()
        } else {
            capture.stop()
            clock.stop()
            phone.stop()
            captureActivities = []
            clockActivities = []
            phoneActivities = []
            pausedRecordings = [:]
            publish()
        }
    }

    func startTimer(minutes: Int) { timer.start(minutes: minutes) }
    func toggleTimerPause() { timer.togglePause() }
    func cancelTimer() { timer.cancel() }

    func startStopwatch() { stopwatch.start() }
    func toggleStopwatchPause() { stopwatch.togglePause() }
    func resetStopwatch() { stopwatch.reset() }

    func diagnoseClock(completion: @escaping (String) -> Void) { clock.diagnose(completion: completion) }
    func diagnoseCalls(completion: @escaping (String) -> Void) {
        capture.diagnose { [phone] report in completion(phone.diagnose() + "\n\n" + report) }
    }

    func callActionDone(_ action: CallControl.Action, activityID: String) {
        capture.didPerform(action, activityID: activityID)
    }

    /// Cuộc gọi điện thoại / FaceTime: điều khiển thẳng qua hệ thống, không cần Trợ năng.
    func performPhone(_ action: CallControl.Action, id: String) -> Bool { phone.perform(action, id: id) }

    // MARK: - Ghi âm tạm dừng

    func markRecordingPaused(_ activity: LiveActivity) {
        let elapsed = activity.pausedElapsed ?? Date().timeIntervalSince(activity.startedAt ?? Date())
        pausedRecordings[activity.id] = PausedRecording(activity: activity, elapsed: max(0, elapsed))
        publish()
        // Phòng khi người dùng tự dừng bản ghi ở app: không để hàng "tạm dừng" treo mãi.
        DispatchQueue.main.asyncAfter(deadline: .now() + 900) { [weak self] in
            guard let self, self.pausedRecordings.removeValue(forKey: activity.id) != nil else { return }
            self.publish()
        }
    }

    /// Tiếp tục (hoặc dừng hẳn) – bỏ trạng thái tạm dừng; thời gian đã ghi được nối tiếp.
    func clearRecordingPause(id: String, resumed: Bool) {
        guard let paused = pausedRecordings.removeValue(forKey: id) else { return }
        if resumed { capture.seed(id: id, startedAt: Date().addingTimeInterval(-paused.elapsed)) }
        publish()
    }

    // MARK: - Gộp danh sách

    private func publish() {
        var all: [LiveActivity] = []

        for activity in captureActivities {
            if let paused = pausedRecordings[activity.id] {
                all.append(Self.pausedVersion(of: activity, elapsed: paused.elapsed))
            } else {
                all.append(activity)
            }
        }
        // Bản ghi đã tạm dừng mà micro đã được nhả.
        for (id, paused) in pausedRecordings where !captureActivities.contains(where: { $0.id == id }) {
            let appAlive = paused.activity.bundleIdentifier.map {
                !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
            } ?? false
            if appAlive {
                all.append(Self.pausedVersion(of: paused.activity, elapsed: paused.elapsed))
            } else {
                pausedRecordings[id] = nil
            }
        }

        all.append(contentsOf: clockActivities)
        // Cuộc gọi iPhone / FaceTime đã có hàng riêng: bỏ hàng FaceTime suy ra từ micro để khỏi trùng.
        all.append(contentsOf: phoneActivities)
        if !phoneActivities.isEmpty { all.removeAll { $0.bundleIdentifier == "com.apple.FaceTime" && $0.id.hasPrefix("mic:") } }
        if let timerActivity { all.append(timerActivity) }
        if let stopwatchActivity { all.append(stopwatchActivity) }
        all.sort { ($0.kind, $0.id) < ($1.kind, $1.id) }
        onChange?(all)
    }

    private static func pausedVersion(of activity: LiveActivity, elapsed: TimeInterval) -> LiveActivity {
        var copy = activity
        copy.startedAt = nil
        copy.pausedElapsed = elapsed
        copy.title = "Ghi âm đã tạm dừng"
        copy.symbolName = "pause.circle.fill"
        return copy
    }

    private static func activity(from state: TimerService.State) -> LiveActivity {
        LiveActivity(
            id: "timer", kind: .timer, title: "Hẹn giờ",
            subtitle: state.pausedRemaining == nil ? state.label : "\(state.label) · đang tạm dừng",
            symbolName: "timer", tint: .orange, bundleIdentifier: nil,
            startedAt: nil, endsAt: state.endsAt, pausedRemaining: state.pausedRemaining
        )
    }

    private static func activity(from state: StopwatchService.State) -> LiveActivity {
        var activity = LiveActivity(
            id: "stopwatch", kind: .stopwatch, title: "Bấm giờ",
            subtitle: state.pausedElapsed == nil ? "Đang chạy" : "Đang tạm dừng",
            symbolName: "stopwatch", tint: .yellow, bundleIdentifier: nil,
            startedAt: state.pausedElapsed == nil ? state.startedAt : nil, endsAt: nil, pausedRemaining: nil
        )
        activity.pausedElapsed = state.pausedElapsed
        return activity
    }
}
