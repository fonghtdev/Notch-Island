import AppKit
import Combine

/// Lắp ráp các thành phần (composition root): Settings + ViewModel + Window + menu bar.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var settings: AppSettings?
    private var viewModel: IslandViewModel?
    private var windowController: NotchWindowController?
    private var lockScreenController: LockScreenController?
    private var settingsWindow: SettingsWindowController?
    private var updater: UpdateService?
    private let updateItem = NSMenuItem(title: "Kiểm tra cập nhật…", action: nil, keyEquivalent: "")
    private var statusItem: NSStatusItem?
    /// Mục "Nâng cao" (demo, chẩn đoán): chỉ hiện khi giữ phím Option lúc mở menu.
    private let advancedItem = NSMenuItem(title: "Nâng cao", action: nil, keyEquivalent: "")
    private let providerItem = NSMenuItem(title: "Nguồn nhạc: —", action: nil, keyEquivalent: "")
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Onboarding.ensureInstalledLocation() else {
            NSApp.terminate(nil)
            return
        }
        LegacyCleanup.run()
        let settings = AppSettings()
        let viewModel = IslandViewModel(settings: settings)
        let windowController = NotchWindowController(viewModel: viewModel)
        windowController.show()
        let lockScreenController = LockScreenController(viewModel: viewModel)
        let updater = UpdateService(settings: settings)

        self.lockScreenController = lockScreenController
        self.settings = settings
        self.viewModel = viewModel
        self.windowController = windowController
        self.updater = updater
        self.settingsWindow = SettingsWindowController(settings: settings, updater: updater) { [weak viewModel] event in
            viewModel?.showHUD(event)
        }
        Uninstaller.showFarewell = { [weak viewModel] in viewModel?.show(.farewell) }
        setupStatusItem()
        let firstRun = !UserDefaults.standard.bool(forKey: "didOnboard.v1")
        if firstRun {
            // Lần đầu: lời chào trên đảo trước, xong mới hỏi quyền và mở Cài đặt (đầu trang có "Bắt đầu nhanh").
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { viewModel.show(.welcome) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9 + IslandMetrics.welcomeDuration) { [weak self] in
                Onboarding.runIfNeeded()
                self?.openSettings()
            }
        } else {
            Onboarding.runIfNeeded()
        }
        // Toggle đã bật từ trước (hoặc bản cũ) mà chưa có quyền → hỏi một lần.
        if settings.showOnLockScreen && settings.lockScreenNotifications { Onboarding.askFullDiskAccess() }
        updater.startAutomaticChecks()
        updater.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.refreshUpdateItem(state) }
            .store(in: &cancellables)

        viewModel.$nowPlayingProvider
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in self?.providerItem.title = "Nguồn nhạc: \(name)" }
            .store(in: &cancellables)
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "NotchIsland")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(makeTimerMenu())
        menu.addItem(makeStopwatchMenu())
        menu.addItem(.separator())
        menu.addItem(makeItem("Cài đặt…", #selector(openSettings), key: ","))
        updateItem.target = self
        updateItem.action = #selector(checkForUpdates)
        menu.addItem(updateItem)
        menu.addItem(makeItem("Hỗ trợ…", #selector(openSupport)))

        advancedItem.submenu = makeAdvancedMenu()
        advancedItem.isHidden = true
        menu.addItem(advancedItem)

        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let versionItem = NSMenuItem(title: "NotchIsland \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(makeItem("Thoát NotchIsland", #selector(quit), key: "q"))

        item.menu = menu
        statusItem = item
    }

    private func refreshUpdateItem(_ state: UpdateService.State) {
        switch state {
        case .available(let release): updateItem.title = "⬆︎ Cập nhật lên \(release.version)…"
        case .checking: updateItem.title = "Đang kiểm tra cập nhật…"
        case .downloading(let value): updateItem.title = "Đang tải bản mới… \(Int((value * 100).rounded()))%"
        case .installing: updateItem.title = "Đang cài đặt…"
        default: updateItem.title = "Kiểm tra cập nhật…"
        }
    }

    @objc private func checkForUpdates() {
        guard let updater else { return }
        if updater.availableRelease != nil {
            updater.install()
            return
        }
        Task { @MainActor in
            await updater.check(userInitiated: true)
            switch updater.state {
            case .upToDate:
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Bạn đang dùng bản mới nhất"
                alert.informativeText = "NotchIsland \(AppInfo.version)"
                alert.runModal()
            case .failed(let message):
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Không kiểm tra được cập nhật"
                alert.informativeText = message
                alert.runModal()
            default: break
            }
        }
    }

    @objc private func openSupport() {
        if let url = AppInfo.supportURL { NSWorkspace.shared.open(url) } else { openSettings() }
    }

    /// Công cụ cho người phát triển / báo lỗi; người dùng thường không thấy.
    private func makeAdvancedMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem("Demo: cắm sạc", #selector(demoCharging)))
        menu.addItem(makeItem("Demo: rút sạc", #selector(demoUnplugged)))
        menu.addItem(makeItem("Demo: tai nghe (AirPods)", #selector(demoEarbuds)))
        menu.addItem(makeItem("Demo: tai nghe (chụp tai)", #selector(demoOverEar)))
        menu.addItem(makeItem("Demo: thẻ màn hình khoá (8 giây)", #selector(demoLockScreen)))
        menu.addItem(makeItem("Demo: lời chào lần đầu", #selector(demoWelcome)))
        menu.addItem(makeItem("Demo: HUD âm lượng", #selector(demoVolumeHUD)))
        menu.addItem(makeItem("Demo: HUD độ sáng", #selector(demoBrightnessHUD)))
        menu.addItem(makeItem("Demo: HUD đèn bàn phím", #selector(demoKeyboardHUD)))
        menu.addItem(.separator())
        providerItem.isEnabled = false
        menu.addItem(providerItem)
        menu.addItem(makeItem("Chẩn đoán nhạc…", #selector(diagnoseMusic)))
        menu.addItem(makeItem("Chẩn đoán Đồng hồ…", #selector(diagnoseClock)))
        menu.addItem(makeItem("Chẩn đoán cuộc gọi…", #selector(diagnoseCalls)))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem?.menu else { return }
        advancedItem.isHidden = !NSEvent.modifierFlags.contains(.option)
    }

    private func makeTimerMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Hẹn giờ", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for minutes in [1, 5, 10, 15, 25, 45, 60] {
            let item = NSMenuItem(title: "\(minutes) phút", action: #selector(startTimer(_:)), keyEquivalent: "")
            item.target = self
            item.tag = minutes
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        submenu.addItem(makeItem("Tạm dừng / tiếp tục", #selector(pauseTimer)))
        submenu.addItem(makeItem("Huỷ hẹn giờ", #selector(cancelTimer)))
        parent.submenu = submenu
        return parent
    }

    private func makeStopwatchMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Bấm giờ", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(makeItem("Bắt đầu", #selector(startStopwatch)))
        submenu.addItem(makeItem("Tạm dừng / tiếp tục", #selector(pauseStopwatch)))
        submenu.addItem(makeItem("Đặt lại", #selector(resetStopwatch)))
        parent.submenu = submenu
        return parent
    }

    private func makeItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func demoCharging() {
        guard let viewModel else { return }
        var info = viewModel.battery
        info.isPluggedIn = true
        info.isCharging = true
        info.minutesRemaining = info.minutesRemaining ?? 82
        viewModel.show(.charging(info))
    }

    @objc private func demoUnplugged() {
        guard let viewModel else { return }
        var info = viewModel.battery
        info.isPluggedIn = false
        info.isCharging = false
        info.minutesRemaining = info.minutesRemaining ?? 315
        viewModel.show(.unplugged(info))
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        viewModel?.startTimer(minutes: sender.tag)
    }

    @objc private func pauseTimer() {
        viewModel?.toggleTimerPause()
    }

    @objc private func cancelTimer() {
        viewModel?.cancelTimer()
    }

    @objc private func demoEarbuds() {
        viewModel?.show(.headphones(HeadphoneInfo(
            name: "AirPods Pro", shape: .earbuds, left: 86, right: 91, caseLevel: 64
        )))
    }

    @objc private func demoOverEar() {
        viewModel?.show(.headphones(HeadphoneInfo(name: "AirPods Max", shape: .overEar, main: 72)))
    }

    @objc private func demoLockScreen() {
        viewModel?.previewLockScreen()
    }

    @objc private func demoWelcome() {
        viewModel?.show(.welcome)
    }

    @objc private func demoVolumeHUD() {
        viewModel?.showHUD(HUDEvent(kind: .volume, value: 0.6))
    }

    @objc private func demoBrightnessHUD() {
        viewModel?.showHUD(HUDEvent(kind: .brightness, value: 0.75))
    }

    @objc private func demoKeyboardHUD() {
        viewModel?.showHUD(HUDEvent(kind: .keyboard, value: 0.5))
    }

    @objc private func startStopwatch() { viewModel?.startStopwatch() }
    @objc private func pauseStopwatch() { viewModel?.toggleStopwatchPause() }
    @objc private func resetStopwatch() { viewModel?.resetStopwatch() }

    @objc private func diagnoseClock() {
        viewModel?.diagnoseClock { [weak self] report in
            self?.showReport(
                title: "Chẩn đoán Đồng hồ", report: report,
                hint: "Đặt một hẹn giờ / bấm giờ trong app Đồng hồ rồi bấm lại mục này, sau đó gửi nội dung này cho người hỗ trợ."
            )
        }
    }

    @objc private func diagnoseCalls() {
        viewModel?.diagnoseCalls { [weak self] report in
            self?.showReport(
                title: "Chẩn đoán cuộc gọi", report: report,
                hint: "Đang trong một cuộc gọi (Zalo, Messenger, Discord…) thì bấm mục này, rồi gửi nội dung cho người hỗ trợ."
            )
        }
    }

    @objc private func diagnoseMusic() {
        viewModel?.diagnoseNowPlaying { [weak self] report in
            self?.showReport(title: "Chẩn đoán nhạc", report: report)
        }
    }

    /// Hiện báo cáo trong hộp thoại cuộn được, có nút sao chép để dán cho người hỗ trợ.
    private func showReport(title: String, report: String,
                            hint: String = "Phát một bài (vd. YouTube) rồi bấm lại mục này nếu chưa thấy gì.") {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 580, height: 300)
        if let textView = scroll.documentView as? NSTextView {
            textView.string = report
            textView.isEditable = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = hint
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Sao chép")
        alert.addButton(withTitle: "Đóng")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        }
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
