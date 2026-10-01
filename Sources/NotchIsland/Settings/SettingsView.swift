import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    /// Hiện thử một HUD thật trên đảo.
    let onPreviewOnIsland: (HUDEvent) -> Void


    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var screens = ScreenOption.connected()

    @State private var previewKind: HUDEvent.Kind = .volume
    @State private var previewValue: Double = 0.65

    var body: some View {
        Form {
            Section("Hiển thị") {
                Toggle("Nhạc đang phát", isOn: $settings.showNowPlaying)
                Toggle("Ảnh bìa độ phân giải cao (tra iTunes, gửi tên bài tới Apple)", isOn: $settings.hdArtwork)
                    .disabled(!settings.showNowPlaying)
                Toggle("Thông báo cắm / rút sạc", isOn: $settings.showBatteryAlerts)
                Toggle("Tai nghe Bluetooth (thẻ 3D, pin)", isOn: $settings.showHeadphones)
                Toggle("Hoạt động: hẹn giờ, cuộc gọi, ghi âm", isOn: $settings.showLiveActivities)
                Toggle("HUD âm lượng, độ sáng, đèn bàn phím", isOn: $settings.showHUD)
            }

            if settings.showHUD {
                Section {
                    accessibilityStatus
                } header: {
                    Text("Phím điều khiển")
                } footer: {
                    Text("NotchIsland tự thay HUD âm lượng / độ sáng / đèn bàn phím của macOS khi có quyền Trợ năng – cấp quyền xong là áp dụng ngay, không cần mở lại app.")
                }
            }

            lockScreenSection


            hudAppearanceSection

            surfaceSection

            Section {
                Toggle("Rê chuột vào để mở (tắt: bấm vào đảo)", isOn: $settings.hoverToExpand)
            } header: {
                Text("Hành vi")
            } footer: {
                Text("Kích thước và bo góc đảo được cố định theo tỉ lệ chuẩn để luôn khớp với notch.")
            }

            Section("Màn hình") {
                Picker("Hiển thị đảo trên", selection: $settings.displayID) {
                    Text("Tự động (ưu tiên màn hình có notch)").tag(0)
                    ForEach(screenChoices) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            }

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
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 820)
        .onAppear {
            screens = ScreenOption.connected()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: - Màn hình khoá

    private var lockScreenSection: some View {
        Section {
            Toggle("Hiện thẻ giữa màn hình khoá", isOn: $settings.showOnLockScreen)
            Toggle("Hiện thông báo trên màn hình khoá", isOn: $settings.lockScreenNotifications)
                .disabled(!settings.showOnLockScreen)
        } header: {
            Text("Màn hình khoá (thử nghiệm)")
        } footer: {
            Text("Thẻ gồm nhạc, cuộc gọi / hẹn giờ đang diễn ra và (nếu bật) thông báo; dùng API riêng tư của Apple nên có thể không chạy trên mọi bản macOS. Đọc thông báo cần cấp quyền Toàn bộ ổ đĩa cho app (hoặc cho Terminal nếu chạy bằng swift run). Lưu ý: ai đứng trước máy đang khoá cũng đọc được thông báo hiện trên thẻ.")
        }
    }

    // MARK: - Nền đảo

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
            Text("Nền đảo")
        } footer: {
            Text(surfaceFooter)
        }
    }

    private var surfaceFooter: String {
        if settings.islandStyle == .glass && !IslandSurface.supportsLiquidGlass {
            return "Liquid Glass cần macOS 26+ và build bằng Xcode 26 (Swift 6.2+). Bản hiện tại chưa đáp ứng nên đang dùng kính mờ thay thế."
        }
        return "Trên máy có notch thật, đảo vẫn đen khi thu gọn để liền với notch; kính chỉ hiện khi đảo nở ra. Tăng độ đậm màu phủ nếu chữ khó đọc trên hình nền sáng."
    }

    // MARK: - Giao diện HUD

    private var hudAppearanceSection: some View {
        Section {
            preview

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
                Button("Hiện thử trên đảo") {
                    onPreviewOnIsland(HUDEvent(kind: previewKind, value: previewValue))
                }
                Spacer()
                Button("Về mặc định", role: .destructive) { settings.resetAppearance() }
            }
        } header: {
            Text("Giao diện HUD")
        } footer: {
            Text("Áp dụng cho HUD âm lượng, độ sáng và đèn bàn phím.")
        }
    }

    /// Bản xem trước: vẽ đúng HUD thật trong khung đảo đen có bo góc theo cài đặt.
    private var preview: some View {
        let notch = CGSize(width: 150, height: 32)
        let appearance = settings.hudAppearance
        let width = notch.width + IslandMetrics.compactWingWidth * 2 + IslandMetrics.hudExtraWidth
        let height = notch.height + appearance.extraHeight

        let shape = NotchShape(earRadius: IslandMetrics.earRadius, bottomRadius: IslandMetrics.collapsedBottomRadius)

        return ZStack(alignment: .top) {
            IslandBackground(shape: shape, surface: settings.islandSurface)
                .frame(width: width + IslandMetrics.earRadius * 2, height: height)

            HUDView(
                event: HUDEvent(kind: previewKind, value: previewValue),
                notchSize: notch,
                appearance: appearance
            )
            .frame(width: width, height: height, alignment: .top)
        }
        .frame(maxWidth: .infinity, minHeight: 32 + 30 + 8, alignment: .top)
        .padding(.vertical, 6)
        // Nền màu sặc sỡ phía sau để thấy rõ hiệu ứng kính / kính mờ khi xem trước.
        .background(
            LinearGradient(
                colors: [.pink, .orange, .yellow, .mint, .blue],
                startPoint: .leading,
                endPoint: .trailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        )
        .animation(.easeOut(duration: 0.15), value: appearance.extraHeight)
    }

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
