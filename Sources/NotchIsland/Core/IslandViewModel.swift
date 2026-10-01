import Foundation
import Combine
import CoreGraphics
import AppKit

/// Nguồn sự thật duy nhất cho UI. Mọi thay đổi @Published đều diễn ra trên main thread
/// (các service tự đẩy callback về main).
final class IslandViewModel: ObservableObject {
    @Published private(set) var geometry: NotchGeometry
    @Published private(set) var isExpanded = false
    @Published private(set) var transient: TransientActivity?
    @Published private(set) var nowPlaying: NowPlayingInfo?
    /// Đang giữ thông tin bài cũ trong lúc chờ bài mới (chuyển bài): UI làm mờ nhẹ thay vì biến mất.
    @Published private(set) var isNowPlayingStale = false
    @Published private(set) var battery: BatteryInfo = .unknown
    @Published private(set) var hud: HUDEvent?
    /// Nguồn "Đang phát" đang dùng (MediaRemote hoặc dự phòng).
    @Published private(set) var nowPlayingProvider = "—"
    /// Hoạt động đang diễn ra (hẹn giờ, cuộc gọi, ghi âm…), đã xếp theo ưu tiên.
    @Published private(set) var activities: [LiveActivity] = []
    /// Tai nghe Bluetooth đang kết nối (nil: không có).
    @Published private(set) var headphones: HeadphoneInfo?
    @Published private(set) var notifications: [NotificationItem] = []
    @Published private(set) var isLocked = false

    let settings: AppSettings

    private let batteryService: BatteryService
    private let nowPlayingService: NowPlayingService
    private let hudService: HUDService
    private let activityCenter: ActivityCenter
    private let headphoneMonitor: HeadphoneMonitor
    private let lockMonitor: LockStateMonitor
    private let notificationReader: NotificationReader
    private var transientWork: DispatchWorkItem?
    private var hudWork: DispatchWorkItem?
    private var nowPlayingClearWork: DispatchWorkItem?
    private let hdArtwork = HDArtworkService()
    /// Khoảng chờ trước khi coi là hết nhạc thật (giữa hai bài, player báo "không có gì" trong chốc lát).
    private static let nowPlayingGrace: TimeInterval = 6
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AppSettings = AppSettings(),
        geometry: NotchGeometry = .placeholder,
        batteryService: BatteryService = BatteryService(),
        nowPlayingService: NowPlayingService = NowPlayingService(),
        hudService: HUDService = HUDService(),
        activityCenter: ActivityCenter = ActivityCenter(),
        headphoneMonitor: HeadphoneMonitor = HeadphoneMonitor(),
        lockMonitor: LockStateMonitor = LockStateMonitor(),
        notificationReader: NotificationReader = NotificationReader()
    ) {
        self.settings = settings
        self.geometry = geometry
        self.batteryService = batteryService
        self.nowPlayingService = nowPlayingService
        self.hudService = hudService
        self.activityCenter = activityCenter
        self.headphoneMonitor = headphoneMonitor
        self.lockMonitor = lockMonitor
        self.notificationReader = notificationReader
        bindServices()
        observeSettings()
    }

    // MARK: - Trạng thái suy ra

    /// Dữ liệu sau khi áp công tắc trong Cài đặt.
    var visibleNowPlaying: NowPlayingInfo? { settings.showNowPlaying ? nowPlaying : nil }
    var visibleTransient: TransientActivity? {
        guard let transient else { return nil }
        switch transient {
        case .charging, .unplugged: return settings.showBatteryAlerts ? transient : nil
        case .headphones: return settings.showHeadphones ? transient : nil
        case .timerFinished: return settings.showLiveActivities ? transient : nil
        case .farewell, .welcome: return transient
        }
    }
    var visibleActivities: [LiveActivity] { settings.showLiveActivities ? activities : [] }
    var primaryActivity: LiveActivity? { visibleActivities.first }
    var visibleNotifications: [NotificationItem] { settings.lockScreenNotifications ? notifications : [] }

    /// Có gì để hiện trên màn hình khoá không (nếu không thì ẩn hẳn thẻ, khỏi chắn ô mật khẩu).
    var hasLockScreenContent: Bool {
        visibleNowPlaying != nil || !visibleActivities.isEmpty || !visibleNotifications.isEmpty
    }

    /// Kiểu nội dung của thẻ mở rộng → quyết định kích thước: chỉ nở to khi có nhạc.
    enum ExpandedLayout: Equatable {
        case media(withActivity: Bool)
        case activities(Int)
        case idle
    }

    var expandedLayout: ExpandedLayout {
        let count = visibleActivities.count
        if visibleNowPlaying != nil { return .media(withActivity: count > 0) }
        if count > 0 { return .activities(min(count, 2)) }
        return .idle
    }

    var mode: IslandMode {
        if isExpanded { return .expanded }
        if hud != nil { return .hud }
        if visibleTransient != nil { return .banner }
        if !visibleActivities.isEmpty || visibleNowPlaying?.isPlaying == true { return .compact }
        return .collapsed
    }

    /// Kích thước thật trên màn hình của phần thân đảo (chưa gồm hai "tai" cong ở trên).
    /// Tỉ lệ cố định, không chỉnh được (xem IslandMetrics).
    var contentSize: CGSize {
        let notch = geometry.notchSize
        let wing = IslandMetrics.compactWingWidth
        switch mode {
        case .collapsed:
            return notch
        case .compact:
            return CGSize(width: notch.width + wing * 2, height: notch.height)
        case .hud:
            return CGSize(
                width: notch.width + IslandMetrics.hudWingWidth * 2,
                height: notch.height + settings.hudAppearance.extraHeight
            )
        case .banner:
            var extra = IslandMetrics.bannerExtraHeight
            switch visibleTransient {
            case .headphones?: extra = IslandMetrics.headphoneExtraHeight
            case .charging?, .unplugged?: extra = IslandMetrics.powerExtraHeight
            case .farewell?: extra = IslandMetrics.farewellExtraHeight
            case .welcome?: extra = IslandMetrics.welcomeExtraHeight
            default: break
            }
            return CGSize(
                width: max(IslandMetrics.bannerWidth, notch.width + wing * 2 + 40),
                height: notch.height + extra
            )
        case .expanded:
            let minWidth = notch.width + wing * 2
            switch expandedLayout {
            case .media(let withActivity):
                return CGSize(
                    width: max(IslandMetrics.expandedSize.width, minWidth),
                    height: withActivity ? IslandMetrics.expandedSize.height : IslandMetrics.mediaOnlyHeight
                )
            case .activities(let rows):
                let n = CGFloat(rows)
                let body = n * IslandMetrics.activityRowHeight + (n - 1) * IslandMetrics.activityRowSpacing
                return CGSize(
                    width: max(IslandMetrics.activityWidth, minWidth),
                    height: notch.height + 10 + body + 14
                )
            case .idle:
                return CGSize(
                    width: max(IslandMetrics.idleSize.width, minWidth),
                    height: max(IslandMetrics.idleSize.height, notch.height + 56)
                )
            }
        }
    }

    var bottomRadius: CGFloat {
        switch mode {
        case .expanded: return IslandMetrics.expandedBottomRadius
        case .banner: return IslandMetrics.bannerBottomRadius
        case .collapsed, .compact, .hud: return IslandMetrics.collapsedBottomRadius
        }
    }

    // MARK: - Intent

    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        // Lời chào / lời cảm ơn: rê chuột hay bấm vào cũng không mở đảo, để thẻ không bị ngắt giữa chừng.
        if expanded, transient == .welcome || transient == .farewell { return }
        isExpanded = expanded
    }

    /// Bấm vào đảo: chỉ có tác dụng khi đã tắt "rê chuột để mở".
    func handleTap() {
        guard !settings.hoverToExpand else { return }
        setExpanded(!isExpanded)
    }

    func updateGeometry(_ newValue: NotchGeometry) {
        guard newValue != geometry else { return }
        geometry = newValue
    }

    // MARK: Điều khiển nhanh (âm lượng / độ sáng / đèn bàn phím)

    func supports(_ kind: HUDEvent.Kind) -> Bool {
        hudService.isSupported(kind)
    }

    func level(of kind: HUDEvent.Kind) -> Double? {
        hudService.level(of: kind)
    }

    func setLevel(_ value: Double, for kind: HUDEvent.Kind) {
        hudService.setLevel(value, for: kind)
    }

    func send(_ command: MediaCommand) {
        nowPlayingService.send(command)
    }

    func seek(to seconds: TimeInterval) {
        nowPlayingService.seek(to: seconds)
    }

    /// Bấm vào phần nhạc → mở tab / app đang phát.
    func openSource() {
        guard let playing = visibleNowPlaying else { return }
        SourceOpener.open(playing)
    }

    /// Bấm vào một hoạt động → đưa app của nó lên trước.
    func open(_ activity: LiveActivity) {
        guard let bundle = activity.bundleIdentifier else { return }
        SourceOpener.activate(bundleID: bundle)
    }

    func startTimer(minutes: Int) { activityCenter.startTimer(minutes: minutes) }
    func toggleTimerPause() { activityCenter.toggleTimerPause() }
    func cancelTimer() { activityCenter.cancelTimer() }

    func startStopwatch() { activityCenter.startStopwatch() }
    func toggleStopwatchPause() { activityCenter.toggleStopwatchPause() }
    func resetStopwatch() { activityCenter.resetStopwatch() }

    func diagnoseClock(completion: @escaping (String) -> Void) {
        activityCenter.diagnoseClock(completion: completion)
    }

    func diagnoseCalls(completion: @escaping (String) -> Void) {
        activityCenter.diagnoseCalls(completion: completion)
    }

    /// Tắt mic / tắt tiếng / kết thúc cuộc gọi bằng cách bấm nút của chính app gọi (Trợ năng). Quét cây có thể chậm → luồng nền.
    func performCall(_ action: CallControl.Action, _ activity: LiveActivity) {
        guard let bundle = activity.bundleIdentifier else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let pressed = CallControl.perform(action, bundleID: bundle)
            DispatchQueue.main.async {
                if pressed { self?.activityCenter.callActionDone(action, activityID: activity.id) } else { NSSound.beep() }
            }
        }
    }

    /// Tạm dừng / tiếp tục bản ghi của app khác bằng cách bấm nút của app đó (cần quyền Trợ năng).
    func toggleRecordingPause(_ activity: LiveActivity) {
        guard let bundle = activity.bundleIdentifier else { return }
        let resuming = activity.isPaused
        switch RecorderControl.perform(.pauseResume, bundleID: bundle) {
        case .pressed:
            if resuming {
                activityCenter.clearRecordingPause(id: activity.id, resumed: true)
            } else {
                activityCenter.markRecordingPaused(activity)
            }
        case .needsPermission, .notFound:
            NSSound.beep()
        }
    }

    func stopRecording(_ activity: LiveActivity) {
        guard let bundle = activity.bundleIdentifier else { return }
        if case .pressed = RecorderControl.perform(.stop, bundleID: bundle) {
            activityCenter.clearRecordingPause(id: activity.id, resumed: false)
        } else {
            NSSound.beep()
        }
    }

    func dismissNotification(_ id: Int64) { notificationReader.dismiss(id) }

    /// Chỉ để thử giao diện màn hình khoá mà không cần khoá máy thật.
    func previewLockScreen(seconds: TimeInterval = 8) {
        // Thẻ chỉ hiện khi có nội dung: không có nhạc/hoạt động thì bật tạm một hẹn giờ 1 phút.
        if !hasLockScreenContent { activityCenter.startTimer(minutes: 1) }
        setLocked(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.setLocked(false) }
    }

    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
    }

    func diagnoseNowPlaying(completion: @escaping (String) -> Void) {
        nowPlayingService.diagnose(completion: completion)
    }

    func show(_ activity: TransientActivity) {
        transientWork?.cancel()
        transient = activity
        let work = DispatchWorkItem { [weak self] in self?.transient = nil }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + activity.duration, execute: work)
    }

    func showHUD(_ event: HUDEvent) {
        guard settings.showHUD else { return }
        hudWork?.cancel()
        hud = event
        let work = DispatchWorkItem { [weak self] in self?.hud = nil }
        hudWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandMetrics.hudDuration, execute: work)
    }

    // MARK: - Services & cài đặt

    private func bindServices() {
        batteryService.onChange = { [weak self] old, new in
            self?.handleBattery(old: old, new: new)
        }
        nowPlayingService.onChange = { [weak self] info in
            guard let self else { return }
            self.nowPlayingClearWork?.cancel()
            self.nowPlayingClearWork = nil
            if var info {
                if self.isNowPlayingStale { self.isNowPlayingStale = false }
                // Bài mới luôn bắt đầu từ 0:00: nếu nguồn còn báo vị trí của bài cũ thì đặt lại.
                if let previous = self.nowPlaying, previous.title != info.title || previous.bundleIdentifier != info.bundleIdentifier {
                    let now = Date()
                    if let oldPos = previous.currentElapsed(at: now), oldPos > 3,
                       let newPos = info.currentElapsed(at: now), abs(newPos - oldPos) < 2 {
                        info.elapsed = 0
                        info.timestamp = now
                        info.receivedAt = now
                    }
                }
                // Bấm tạm dừng / phát tiếp: giữ nguyên số đang hiện thay vì nhảy theo vị trí player báo trễ
                // (tránh "17 → 18 → 17" khi pause). Chỉ ghim khi lệch dưới 1,2 giây; tua thật thì vẫn theo player.
                if let previous = self.nowPlaying,
                   previous.title == info.title, previous.bundleIdentifier == info.bundleIdentifier,
                   !(previous.isPlaying && info.isPlaying) {
                    let now = Date()
                    if let shown = previous.currentElapsed(at: now),
                       let reported = info.currentElapsed(at: now),
                       abs(reported - shown) < 1.2 {
                        info.elapsed = shown
                        info.timestamp = now
                        info.receivedAt = now
                    }
                }
                // Ảnh bìa độ phân giải cao (nếu đã có thì dùng ngay, chưa có thì tải rồi thay vào).
                if self.settings.hdArtwork {
                    let key = HDArtworkService.key(title: info.title, artist: info.artist)
                    if let hd = self.hdArtwork.cached(key) {
                        info.artwork = hd
                        info.artworkID = key.hashValue
                    } else {
                        self.hdArtwork.fetch(title: info.title, artist: info.artist) { [weak self] image in
                            self?.applyHDArtwork(image, key: key)
                        }
                    }
                }
                if info != self.nowPlaying { self.nowPlaying = info }
            } else if self.nowPlaying != nil {
                // Chuyển bài: giữ bài cũ (mờ) một lúc, bài mới tới thì thay ngay; quá hạn mới coi là hết nhạc.
                self.isNowPlayingStale = true
                let work = DispatchWorkItem { [weak self] in
                    self?.nowPlaying = nil
                    self?.isNowPlayingStale = false
                }
                self.nowPlayingClearWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.nowPlayingGrace, execute: work)
            }
        }
        nowPlayingService.onProviderChange = { [weak self] name in
            self?.nowPlayingProvider = name
        }
        hudService.onEvent = { [weak self] event in
            self?.showHUD(event)
        }
        activityCenter.onChange = { [weak self] list in
            guard let self, list != self.activities else { return }
            self.activities = list
        }
        activityCenter.onTimerFinished = { [weak self] label in
            guard let self, self.settings.showLiveActivities else { return }
            self.show(.timerFinished(label))
            NSSound(named: "Glass")?.play()
        }
        headphoneMonitor.onConnect = { [weak self] info in self?.show(.headphones(info)) }
        headphoneMonitor.onDisconnect = { [weak self] info in self?.show(.headphones(info)) }
        headphoneMonitor.onUpdate = { [weak self] info in
            guard let self, info != self.headphones else { return }
            self.headphones = info
        }
        lockMonitor.onChange = { [weak self] locked in self?.setLocked(locked) }
        notificationReader.onChange = { [weak self] list in self?.notifications = list }

        batteryService.start()
        nowPlayingService.start()
        hudService.start()
        activityCenter.start()
        headphoneMonitor.start()
        lockMonitor.start()
    }

    private func applyHDArtwork(_ image: NSImage, key: String) {
        guard var current = nowPlaying,
              HDArtworkService.key(title: current.title, artist: current.artist) == key
        else { return }
        current.artwork = image
        current.artworkID = key.hashValue
        nowPlaying = current
    }

    private func observeSettings() {
        // Đợi giá trị mới ghi xong (objectWillChange phát TRƯỚC khi đổi) rồi mới áp dụng.
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.settingsChanged() }
            .store(in: &cancellables)
        applyHUDInterception()
        applyServiceToggles()
    }

    private func settingsChanged() {
        objectWillChange.send()
        applyHUDInterception()
        applyServiceToggles()
    }

    private func applyServiceToggles() {
        activityCenter.setEnabled(settings.showLiveActivities)
        notificationReader.setEnabled(settings.lockScreenNotifications)
    }

    private func applyHUDInterception() {
        hudService.keyboardControlEnabled = true
        hudService.keyboardShortcutEnabled = settings.keyboardShortcut
        hudService.setIntercepting(settings.showHUD)
    }

    private func handleBattery(old: BatteryInfo?, new: BatteryInfo) {
        battery = new
        // Chỉ bật hiệu ứng khi trạng thái cắm/rút thực sự thay đổi (bỏ qua lần đọc đầu tiên).
        guard new.hasBattery, let old, old.isPluggedIn != new.isPluggedIn else { return }
        show(new.isPluggedIn ? .charging(new) : .unplugged(new))
    }
}
