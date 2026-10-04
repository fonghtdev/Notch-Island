import SwiftUI

/// Một hàng "hoạt động đang diễn ra" (hẹn giờ, cuộc gọi, ghi âm…) trong thẻ mở rộng / màn hình khoá.
/// Bấm vào hàng → mở app tương ứng. Hẹn giờ có thêm nút tạm dừng và dừng.
struct ActivityRow: View {
    let activity: LiveActivity
    var extraCount = 0
    @ObservedObject var viewModel: IslandViewModel

    /// Hoạt động "đang thu / đang gọi" có vòng sáng lan nhẹ quanh biểu tượng.
    private var pulses: Bool {
        guard !activity.isPaused else { return false }
        switch activity.kind {
        case .call, .recording, .microphone, .camera: return true
        case .timer, .stopwatch: return false
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(activity.tint.opacity(0.2))
                PulseRing(tint: activity.tint, isActive: pulses)
                Image(systemName: activity.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activity.tint)
                    .symbolSwap()
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(extraCount > 0 ? "\(activity.subtitle) · +\(extraCount)" : activity.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Đồng hồ + nút gom vào một viên thuốc: gọn, dễ nhìn, không bị kéo giãn ra hai mép.
            HStack(spacing: 2) {
                TimelineView(.periodic(from: activity.tickAnchor, by: 1)) { context in
                    if let text = activity.clockText(at: context.date) {
                        Text(text)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(activity.tint)
                            .opacity(activity.isPaused ? 0.5 : 1)
                            .fixedSize()
                            .padding(.leading, 10)
                            .padding(.trailing, hasControls ? 2 : 10)
                    }
                }
                controlButtons
            }
            .frame(height: 30)
            .glassPill(Capsule(), fallbackOpacity: 0.08, interactive: false)
            .layoutPriority(1)
            .animation(.easeInOut(duration: 0.2), value: activity.isPaused)
        }
        .frame(height: IslandMetrics.activityRowHeight)
        .contentShape(Rectangle())
        .onTapGesture { viewModel.open(activity) }
    }

    private var hasControls: Bool { activity.controls != .none }

    @ViewBuilder
    private var controlButtons: some View {
        let pauseSymbol = activity.isPaused ? "play.fill" : "pause.fill"
        switch activity.controls {
        case .timer:
            ControlButton(symbol: pauseSymbol, size: 10, diameter: 26) { viewModel.toggleTimerPause() }
            ControlButton(symbol: "xmark", size: 10, diameter: 26) { viewModel.cancelTimer() }
        case .stopwatch:
            ControlButton(symbol: pauseSymbol, size: 10, diameter: 26) { viewModel.toggleStopwatchPause() }
            ControlButton(symbol: "xmark", size: 10, diameter: 26) { viewModel.resetStopwatch() }
        case .recording:
            ControlButton(symbol: pauseSymbol, size: 10, diameter: 26) { viewModel.toggleRecordingPause(activity) }
            ControlButton(symbol: "stop.fill", size: 10, diameter: 26) { viewModel.stopRecording(activity) }
        case .call:
            let state = activity.call
            if state?.ringing == true {
                ControlButton(symbol: "phone.fill", size: 10, diameter: 26, tint: .green) { viewModel.performCall(.answer, activity) }
            } else {
                ControlButton(symbol: state?.muted == true ? "mic.slash.fill" : "mic.fill", size: 10, diameter: 26,
                              tint: state?.muted == true ? .orange : nil) { viewModel.performCall(.mute, activity) }
                // Chỉ app có nút "tắt tiếng" (vd. Discord) / nút camera (gọi video) mới hiện các nút này.
                if let deafened = state?.deafened {
                    ControlButton(symbol: deafened ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 10, diameter: 26,
                                  tint: deafened ? .orange : nil) { viewModel.performCall(.deafen, activity) }
                }
                if let camera = state?.camera {
                    ControlButton(symbol: camera ? "video.fill" : "video.slash.fill", size: 10, diameter: 26,
                                  tint: camera ? nil : .orange) { viewModel.performCall(.camera, activity) }
                }
            }
            ControlButton(symbol: "phone.down.fill", size: 10, diameter: 26, tint: .red) { viewModel.performCall(.end, activity) }
        case .none:
            EmptyView()
        }
    }
}

/// Nội dung nhỏ trên cánh island: đồng hồ của hoạt động chính.
struct ActivityWing: View {
    let activity: LiveActivity

    var body: some View {
        TimelineView(.periodic(from: activity.tickAnchor, by: 1)) { context in
            if let text = activity.clockText(at: context.date) {
                Text(text)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(activity.tint)
                    .opacity(activity.isPaused ? 0.5 : 1)
            } else {
                Image(systemName: activity.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activity.tint)
            }
        }
    }
}
