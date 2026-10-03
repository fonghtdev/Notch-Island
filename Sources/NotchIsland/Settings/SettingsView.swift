import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Hiện thử một HUD thật trên island.
    let onPreviewOnIsland: (HUDEvent) -> Void
    @ObservedObject var updater: UpdateService
    @State private var feedback = ""

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var screens = ScreenOption.connected()

    @State private var previewKind: HUDEvent.Kind = .volume
    @State private var previewValue: Double = 0.65

    var body: some View {
        Form {
            guideSection

            Section("Hiển thị") {
                Toggle("Nhạc đang phát", isOn: $settings.showNowPlaying)
                Toggle("Ảnh bìa độ phân giải cao (tra iTunes, gửi tên bài tới Apple)", isOn: $settings.hdArtwork)
                    .disabled(!settings.showNowPlaying)
                Toggle("Thông báo cắm / rút sạc", isOn: $settings.showBatteryAlerts)
                Toggle("Tai nghe Bluetooth (thẻ 3D, pin)", isOn: $settings.showHeadphones)
                Toggle("Hoạt động: hẹn giờ, cuộc gọi, ghi âm", isOn: $settings.showLiveActivities)
                Toggle("HUD âm lượng, độ sáng, đèn bàn phím", isOn: $settings.showHUD)
                Toggle("Thông báo trên màn hình khoá (cần quyền Toàn bộ ổ đĩa)", isOn: $settings.lockScreenNotifications)
                    .disabled(!settings.showOnLockScreen)
                    .onChange(of: settings.lockScreenNotifications) { on in
                        if on { Onboarding.askFullDiskAccess() }
                    }
            }

            if settings.showHUD {
                Section {
                    accessibilityStatus
                    Toggle("Phím tắt chỉnh đèn bàn phím", isOn: $settings.keyboardShortcut)
                    if settings.keyboardShortcut {
                        keyboardShortcutGuide
                    }
                } header: {
                    Text("Phím điều khiển")
                } footer: {
                    Text("NotchIsland tự thay HUD âm lượng / độ sáng / đèn bàn phím của macOS khi có quyền Trợ năng – cấp quyền xong là áp dụng ngay, không cần mở lại app. Phím tắt đèn bàn phím dành cho máy không có phím đèn riêng; nếu macOS hỏi quyền Giám sát đầu vào (Input Monitoring) thì hãy cho phép.")
                }
            }

            lockScreenSection


            hudAppearanceSection

            surfaceSection

            Section {
                Toggle("Rê chuột vào để mở (tắt: bấm vào island)", isOn: $settings.hoverToExpand)
            } header: {
                Text("Hành vi")
            } footer: {
                Text("Kích thước và bo góc island được cố định theo tỉ lệ chuẩn để luôn khớp với notch.")
            }

            Section("Màn hình") {
                Picker("Hiển thị island trên", selection: $settings.displayID) {
                    Text("Tự động (ưu tiên màn hình có notch)").tag(0)
                    ForEach(screenChoices) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

            updateSection

            supportSection

            Section {
                Toggle("Mở cùng macOS", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Hệ thống")
            } footer: {
                Text("Chỉ hoạt động khi chạy từ gói NotchIsland.app (./scripts/build-app.sh), không áp dụng với swift run.")
            }

            Section {
                Button(role: .destructive) { Uninstaller.confirmAndRun() } label: {
                    Label("Gỡ NotchIsland khỏi máy…", systemImage: "trash")
                }
            } footer: {
                Text("Xoá app, cài đặt, dữ liệu tạm và các quyền đã cấp. Có hỏi xác nhận trước.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .onAppear {
            screens = ScreenOption.connected()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Cập nhật

    private var updateSection: some View {
        Section {
            LabeledContent("Phiên bản", value: "\(AppInfo.version) (\(AppInfo.build))")
            Toggle("Tự kiểm tra cập nhật", isOn: $settings.autoCheckUpdates)
                .disabled(!AppInfo.hasRepo)
            updateRow
        } header: {
            Text("Cập nhật")
        } footer: {
            Text(AppInfo.hasRepo
                 ? "App hỏi GitHub Releases khoảng 6 giờ một lần, chỉ gửi số phiên bản. Bản mới được tải, thay thế và mở lại tự động khi bạn đồng ý."
                 : "Bản build cục bộ chưa gắn kho phát hành nên không tự cập nhật. Bản tải từ trang Releases thì có.")
        }
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updater.state {
        case .idle, .upToDate:
            HStack {
                if updater.state == .upToDate {
                    Label("Bạn đang dùng bản mới nhất", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("Kiểm tra ngay") { Task { await updater.check(userInitiated: true) } }
                    .disabled(!AppInfo.hasRepo)
            }
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang kiểm tra…").foregroundStyle(.secondary)
            }
        case .available(let release):
            VStack(alignment: .leading, spacing: 8) {
                Label("Có bản mới \(release.version)", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
                if !release.notes.isEmpty {
                    Text(release.notes).font(.caption).foregroundStyle(.secondary).lineLimit(6)
                }
                HStack {
                    Button("Cập nhật & khởi động lại") { updater.install() }
                        .buttonStyle(.borderedProminent)
                    if let page = release.pageURL {
                        Link("Xem chi tiết", destination: page)
                    }
                }
            }
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                Text("Đang tải bản mới… \(Int((fraction * 100).rounded()))%")
                ProgressView(value: fraction)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang cài đặt, app sẽ tự mở lại…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.caption).foregroundStyle(.red)
                Button("Thử lại") { Task { await updater.check(userInitiated: true) } }
                    .disabled(!AppInfo.hasRepo)
            }
        }
    }

    // MARK: - Hướng dẫn

    private var guideSection: some View {
        Section {
            guideRow("capsule.fill", "island nằm ngay notch", "Rê chuột vào notch (hoặc bấm, tuỳ mục Hành vi) để mở rộng: nhạc, hẹn giờ, hoạt động.")
            guideRow("menubar.rectangle", "Biểu tượng trên thanh menu", "Bấm biểu tượng viên thuốc để đặt hẹn giờ, bấm giờ, mở Cài đặt hoặc thoát.")
            guideRow("music.note", "Nhạc", "Phát nhạc ở Music, Spotify hoặc trình duyệt – bài hát tự hiện trên island, bấm thanh tiến trình để tua.")
            guideRow("speaker.wave.2.fill", "Âm lượng, độ sáng", "Dùng phím như bình thường; HUD hiện trên island. Cần cấp quyền Trợ năng (xem mục Phím điều khiển).")
            guideRow("headphones", "Tai nghe, sạc", "Kết nối tai nghe Bluetooth hoặc cắm sạc, island tự báo.")
        } header: {
            Text("Bắt đầu nhanh")
        } footer: {
            Text("App không có cửa sổ chính – mọi thứ nằm ở notch và menu bar. Gặp lỗi? Kéo xuống mục Hỗ trợ.")
        }
    }

    private func guideRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Hỗ trợ

    private var supportSection: some View {
        Section {
            if let support = AppInfo.supportURL {
                Link(destination: support) { Label("Trang hỗ trợ & hướng dẫn", systemImage: "questionmark.circle") }
            }
            if let releases = AppInfo.releasesURL {
                Link(destination: releases) { Label("Tất cả phiên bản", systemImage: "shippingbox") }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Báo lỗi / góp ý").font(.subheadline.weight(.semibold))
                TextEditor(text: $feedback)
                    .font(.body)
                    .frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                Button {
                    if let url = AppInfo.reportURL(message: feedback) { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Gửi báo lỗi", systemImage: "paperplane")
                }
                .disabled(!AppInfo.hasRepo || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Hỗ trợ")
        } footer: {
            Text("Mô tả lỗi rồi bấm Gửi: trình duyệt mở form GitHub đã điền sẵn nội dung và thông tin chẩn đoán (chỉ gồm phiên bản app, macOS, chip, trạng thái quyền – không có dữ liệu cá nhân). Bạn chỉ cần bấm \"Submit new issue\" (cần tài khoản GitHub).")
        }
    }

    // MARK: - Hướng dẫn phím tắt đèn bàn phím

    private var keyboardShortcutGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cách chỉnh đèn bàn phím")
                .font(.subheadline.weight(.semibold))
            shortcutRow(keys: ["fn", "1"], action: "Giảm đèn bàn phím")
            shortcutRow(keys: ["fn", "2"], action: "Tăng đèn bàn phím")
            Text("Giữ phím để tăng / giảm liên tục; HUD hiện trên island. Máy không có đèn bàn phím thì phím được trả về cho macOS. Cũng chỉnh được bằng thanh trượt trong Trung tâm điều khiển.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func shortcutRow(keys: [String], action: String) -> some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in KeyCap(label: key) }
            Text(action).foregroundStyle(.secondary).padding(.leading, 4)
        }
    }

    // MARK: - Màn hình khoá

    private var lockScreenSection: some View {
        Section {
            Toggle("Hiện thẻ giữa màn hình khoá", isOn: $settings.showOnLockScreen)
        } header: {
            Text("Màn hình khoá (thử nghiệm)")
        } footer: {
            Text("Thẻ gồm nhạc, cuộc gọi / hẹn giờ đang diễn ra và (nếu bật) thông báo; dùng API riêng tư của Apple nên có thể không chạy trên mọi bản macOS. Đọc thông báo cần cấp quyền Toàn bộ ổ đĩa cho app (hoặc cho Terminal nếu chạy bằng swift run). Lưu ý: ai đứng trước máy đang khoá cũng đọc được thông báo hiện trên thẻ.")
        }
    }

    // MARK: - Nền island

    private var surfaceSection: some View {
        Section {
            Picker("Kiểu nền", selection: $settings.islandStyle) {
                ForEach(IslandBackgroundStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if settings.islandStyle != .solid {
                Toggle("Kính trong (Clear)", isOn: $settings.glassClear)
                    .disabled(settings.islandStyle != .glass || !IslandSurface.supportsLiquidGlass)

                ColorPicker("Màu phủ kính", selection: $settings.glassTint, supportsOpacity: false)
                slider("Độ đậm màu phủ", value: $settings.glassTintStrength,
                       range: AppSettings.glassTintStrengthRange,
                       display: "\(Int((settings.glassTintStrength * 100).rounded()))%")
            }
        } header: {
            Text("Nền island")
        } footer: {
            Text(surfaceFooter)
        }
    }

    private var surfaceFooter: String {
        if settings.islandStyle == .glass && !IslandSurface.supportsLiquidGlass {
            return "Liquid Glass cần macOS 26+ và build bằng Xcode 26 (Swift 6.2+). Bản hiện tại chưa đáp ứng nên đang dùng kính mờ thay thế."
        }
        return "Trên máy có notch thật, island vẫn đen khi thu gọn để liền với notch; kính chỉ hiện khi island nở ra. Tăng độ đậm màu phủ nếu chữ khó đọc trên hình nền sáng."
    }

    // MARK: - Giao diện HUD

    private var hudAppearanceSection: some View {
        Section {
            Picker("Xem trước", selection: $previewKind) {
                Text("Âm lượng").tag(HUDEvent.Kind.volume)
                Text("Độ sáng").tag(HUDEvent.Kind.brightness)
                Text("Đèn phím").tag(HUDEvent.Kind.keyboard)
            }
            .pickerStyle(.segmented)

            slider("Mức xem trước", value: $previewValue, range: 0...1, display: "\(Int((previewValue * 100).rounded()))")

            Picker("Kiểu", selection: $settings.hudStyle) {
                ForEach(HUDStyle.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Bo góc thanh", selection: $settings.hudCorner) {
                ForEach(HUDCorner.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            slider("Độ dày", value: $settings.hudBarHeight,
                   range: AppSettings.barHeightRange, display: "\(Int(settings.hudBarHeight))")

            Toggle("Hiện số %", isOn: $settings.hudShowsPercent)
                .disabled(settings.hudStyle == .ring)

            ColorPicker("Màu âm lượng", selection: $settings.volumeColor, supportsOpacity: false)
            ColorPicker("Màu độ sáng màn hình", selection: $settings.brightnessColor, supportsOpacity: false)
            ColorPicker("Màu đèn bàn phím", selection: $settings.keyboardColor, supportsOpacity: false)

            HStack {
                Button("Hiện thử trên island") {
                    onPreviewOnIsland(HUDEvent(kind: previewKind, value: previewValue))
                }
                Spacer()
                Button("Về mặc định", role: .destructive) { settings.resetAppearance() }
            }
        } header: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Giao diện HUD")
                preview
            }
        } footer: {
            Text("Áp dụng cho HUD âm lượng, độ sáng và đèn bàn phím.")
        }
    }

    /// Bản xem trước: vẽ đúng HUD thật trong khung island đen có bo góc theo cài đặt.
    private var preview: some View {
        let notch = CGSize(width: 150, height: 32)
        let appearance = settings.hudAppearance
        let width = notch.width + IslandMetrics.hudWingWidth * 2
        let height = notch.height + appearance.extraHeight

        let shape = NotchShape(earRadius: IslandMetrics.earRadius, bottomRadius: IslandMetrics.collapsedBottomRadius)

        // Khung xem trước cao cố định (đủ cho HUD cao nhất) → hàng trong Form không đổi chiều cao khi đổi kiểu HUD.
        return ZStack(alignment: .top) {
            // Nền màu sặc sỡ phía sau để thấy rõ hiệu ứng kính / kính mờ khi xem trước.
            LinearGradient(
                colors: [.pink, .orange, .yellow, .mint, .blue],
                startPoint: .leading,
                endPoint: .trailing
            )

            ZStack(alignment: .top) {
                IslandBackground(shape: shape, surface: settings.islandSurface)
                    .frame(width: width + IslandMetrics.earRadius * 2, height: height)

                HUDView(
                    event: HUDEvent(kind: previewKind, value: previewValue),
                    notchSize: notch,
                    appearance: appearance
                )
                .frame(width: width, height: height, alignment: .top)
            }
            .frame(width: width + IslandMetrics.earRadius * 2, height: height, alignment: .top)
            .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.previewHeight, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .textCase(nil)
    }

    private static let previewHeight: CGFloat = 96

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, display: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(display).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: - Khác

    /// Danh sách màn hình; nếu màn đã chọn đang bị rút ra thì vẫn giữ một dòng để Picker không trống.
    private var screenChoices: [ScreenOption] {
        var list = screens
        if settings.displayID != 0, !list.contains(where: { $0.id == settings.displayID }) {
            list.append(ScreenOption(id: settings.displayID, title: "Màn hình đã chọn (đang ngắt kết nối)"))
        }
        return list
    }

    private var accessibilityStatus: some View {
        TimelineView(.periodic(from: .now, by: 1.5)) { _ in
            let granted = AXIsProcessTrusted()
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(granted ? "Đã có quyền Trợ năng – đang thay HUD macOS" : "Chưa có quyền Trợ năng")
                Spacer()
                if !granted {
                    Button("Cấp quyền") {
                        MediaKeyTap.requestPermission()
                    }
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            launchError = nil
        } catch {
            launchError = "Không đổi được: \(error.localizedDescription)"
        }
        launchAtLogin = service.status == .enabled
    }
}

/// Hình phím bàn phím nhỏ trong phần hướng dẫn.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 26)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.tertiary, lineWidth: 1))
            )
    }
}

struct ScreenOption: Identifiable, Equatable {
    let id: Int
    let title: String

    static func connected() -> [ScreenOption] {
        NSScreen.screens.map { screen in
            let notch = screen.safeAreaInsets.top > 0 ? " – có notch" : ""
            return ScreenOption(id: screen.displayID, title: screen.localizedName + notch)
        }
    }
}
