<div align="center">

# NotchIsland

**Dynamic Island miễn phí cho notch MacBook.**
Nhạc, cuộc gọi, hẹn giờ, âm lượng, pin, tai nghe, camera – gói gọn trong một viên thuốc ngay dưới camera.

[![Release](https://img.shields.io/github/v/release/fonghtdev/Notch-Island?label=release&color=7c4dff)](https://github.com/fonghtdev/Notch-Island/releases/latest)
![macOS](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)
![Dependencies](https://img.shields.io/badge/dependencies-0-brightgreen)

[**Tải bản mới nhất**](https://github.com/fonghtdev/Notch-Island/releases/latest) · [Hỗ trợ & hướng dẫn](https://fonghtdev.github.io/Notch-Island/) · [Báo lỗi](https://github.com/fonghtdev/Notch-Island/issues/new)

</div>

---

## Điểm nổi bật

| | |
|---|---|
| 🎵 **Đang phát** | Nhạc từ mọi nguồn (YouTube, Spotify, Apple Music, VLC…) kèm ảnh bìa độ phân giải cao, thanh tiến trình kéo để tua, bấm vào bài để mở đúng tab / app đang phát. |
| 📞 **Cuộc gọi** | Nhận Zalo, Messenger, Discord, Teams, Meet, FaceTime, **cuộc gọi iPhone**… với tên người gọi, đồng hồ khớp app gốc, nút **tắt mic · tắt tiếng · bật/tắt camera · kết thúc**, trả lời / từ chối cuộc gọi đến. |
| 🔊 **HUD** | Thay HUD âm lượng, độ sáng, đèn bàn phím của macOS; tuỳ chỉnh kiểu thanh / vạch / vòng, màu và bo góc. |
| 🔋 **Sạc & tai nghe** | Thẻ cắm / rút sạc, AirPods / Beats với biểu tượng chuẩn Apple và pin từng tai. |
| ⏱ **Hoạt động** | Hẹn giờ, bấm giờ (cả của app Đồng hồ), ghi âm có nút tạm dừng / dừng, nhận biết app đang dùng micro / camera. |
| 📷 **Gương camera** | Xem trước camera ngay trên đảo, lật gương như Photo Booth. |
| 🔒 **Màn hình khoá** | Thẻ nhạc, cuộc gọi và (tuỳ chọn) thông báo ngay trên màn hình khoá *(thử nghiệm)*. |
| 🎨 **Nền đảo** | Đen liền khối với notch, kính mờ, hoặc **Liquid Glass** (macOS 26). |

Ngoài ra: tự nhận diện notch thật (máy không notch sẽ tạo notch giả), click xuyên qua khi chuột không ở trên đảo, có mặt ở mọi Space và khi app khác full-screen, tự cập nhật, báo lỗi ngay trong app, gỡ cài đặt sạch bằng một nút.

## Cài đặt

1. Tải `NotchIsland-x.y.z.dmg` ở trang [Releases](https://github.com/fonghtdev/Notch-Island/releases/latest).
2. Kéo **NotchIsland** vào **Applications**, eject ổ đĩa rồi mở app từ Applications.
3. Lần đầu mở, app tự bật *Mở cùng macOS*, chiếu lời chào và xin quyền **Trợ năng**.

> **macOS báo “không thể xác minh”?** Bản phát hành ký ad-hoc, chưa notarize. Chỉ cần làm một lần:
> *Cài đặt hệ thống → Quyền riêng tư & Bảo mật → kéo xuống → **Vẫn mở**.*
> Hoặc: `xattr -dr com.apple.quarantine /Applications/NotchIsland.app`

Các bản cập nhật sau do app tự tải (menu bar → *Kiểm tra cập nhật…*) nên không gặp lại cảnh báo này.

## Sử dụng

- **Mở đảo:** rê chuột (hoặc bấm, tuỳ chọn) vào notch. Khi có nhạc, nút **☰** ở góc trên trái mở màn hình chính: pin, hẹn giờ, bấm giờ, camera.
- **Menu bar:** hẹn giờ, bấm giờ, Cài đặt (⌘,), hỗ trợ. Giữ **Option** khi mở menu để hiện mục *Nâng cao* (demo, chẩn đoán nhạc / đồng hồ / cuộc gọi).
- **Cài đặt:** bật tắt từng tính năng, giao diện HUD, nền đảo, màn hình hiển thị, cập nhật, báo lỗi, gỡ cài đặt.

### Quyền cần cấp

| Quyền | Để làm gì | Bắt buộc |
|---|---|---|
| **Trợ năng** | Thay HUD âm lượng / độ sáng; đọc người gọi và bấm nút trong app gọi; điều khiển ghi âm | Khuyến nghị |
| **Automation** | Chuyển tới đúng tab trình duyệt, điều khiển Music / Spotify | Tuỳ chọn |
| **Camera** | Gương camera trên đảo | Tuỳ chọn |
| **Toàn bộ ổ đĩa** | Đọc thông báo để hiện trên màn hình khoá | Tuỳ chọn, mặc định tắt |

Bản ký ad-hoc có thể bị macOS “quên” quyền Trợ năng sau khi cập nhật; app tự nhắc cấp lại một lần.

## Build từ mã nguồn

Yêu cầu: macOS 13+, Xcode 15+ (hoặc Command Line Tools, Swift 5.9+), `cmake` (`brew install cmake`). Liquid Glass cần macOS 26 + Xcode 26.

```bash
./scripts/fetch-adapter.sh     # tải + build adapter đọc Now Playing (một lần)
swift run                      # chạy nhanh khi phát triển (đứng ở thư mục gốc)
./run.sh install               # hoặc: build + chép vào /Applications + chạy

./scripts/build-app.sh         # đóng gói build/NotchIsland.app (nhúng adapter)
VERSION=1.0.2 ./scripts/make-dmg.sh   # ra dist/NotchIsland-1.0.2.dmg
```

Chạy `swift run` thì quyền Trợ năng / Toàn bộ ổ đĩa cấp cho **Terminal**, và các tính năng cần Info.plist (gương camera, mở cùng macOS) chỉ dùng được từ gói `.app`.

## Kiến trúc

Luồng một chiều, theo **3C – Cover · Clean · Clear** (đủ trường hợp biên, mỗi lớp một việc, tên rõ nghĩa):

```
Services ──callback──▶ IslandViewModel ──@Published──▶ SwiftUI
                              ▲
        WindowController ─hover┘
```

```
Sources/NotchIsland/
├── App/        AppDelegate (menu bar, lắp ráp), Onboarding, Uninstaller
├── Core/       IslandViewModel (trạng thái trung tâm), IslandMetrics (mọi kích thước), AppSettings, Models
├── Services/   NowPlaying · HUD · Activity (hẹn giờ, micro/camera, cuộc gọi, iPhone/FaceTime)
│               Headphones · Lock · Update · BatteryService
├── Window/     Panel trong suốt cố định, theo dõi chuột, thẻ màn hình khoá (SkyLight)
├── Settings/   Cửa sổ Cài đặt (SwiftUI)
└── UI/         Island, Compact, Expanded, HUD, Banner, ActivityRow, CameraCard…
```

<details>
<summary><b>Quyết định kỹ thuật</b></summary>

- **Panel cố định kích thước tối đa**, chỉ hình đảo bên trong đổi size → animation mượt, không resize `NSWindow` mỗi frame. `ignoresMouseEvents` bật tắt theo vị trí chuột để click xuyên qua.
- **Now Playing theo provider.** `MediaRemote` là API riêng tư, bị khoá với app bên thứ ba từ macOS 15.4. Nguồn chính là [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) chạy qua `/usr/bin/perl`; thiếu thì tự lùi về distributed notifications của Music / Spotify.
- **Cuộc gọi.** Micro đang mở được đọc từ CoreAudio process objects; tiến trình phụ (vd. `ZaloCall`, helper của trình duyệt) quy về app chính. Người gọi, đồng hồ và nút điều khiển đọc qua Trợ năng; cuộc gọi iPhone / FaceTime đọc từ `TelephonyUtilities` (riêng tư, gọi qua ObjC runtime có kiểm tra `responds(to:)`).
- **HUD.** Âm lượng qua CoreAudio (công khai); độ sáng và đèn bàn phím qua `DisplayServices` / `CoreBrightness` nạp bằng `dlopen`. Phím bắt bằng `CGEventTap`.
- **Màn hình khoá.** Chuyển cửa sổ thẻ vào một Space tầng 400 của SkyLight để vẽ đè lên màn hình khoá.
- **Tự cập nhật** không dùng Sparkle: hỏi `releases/latest`, tải DMG bằng `URLSession` (không dính quarantine), thay app rồi mở lại.
- **Không thêm phụ thuộc ngoài**; mọi API riêng tư đều qua `dlopen` / ObjC runtime và có đường lùi.

</details>

## Phát hành

```bash
git tag -a v1.0.2 -m "v1.0.2" && git push origin v1.0.2
```

GitHub Actions (`.github/workflows/release.yml`) build bản **universal** (Apple Silicon + Intel), đóng gói DMG + ZIP và đăng lên Releases. Biến / secret tuỳ chọn:

| Tên | Tác dụng |
|---|---|
| `RELEASE_REPO` | Kho công khai chứa Releases (mô hình 2 kho, mã nguồn kín) |
| `RELEASES_TOKEN` | Token để đăng sang kho khác |
| `SUPPORT_URL` | Trang hỗ trợ riêng |
| `SIGN_IDENTITY`, `MACOS_CERT_*`, `NOTARY_*` | Ký Developer ID + notarize (hết cảnh báo Gatekeeper) |

## Quyền riêng tư

Không thu thập dữ liệu, không có máy chủ riêng. Các kết nối ra ngoài duy nhất: hỏi GitHub Releases để kiểm tra bản mới (chỉ gửi số phiên bản) và, nếu bật, tra ảnh bìa trên iTunes Search (chỉ gửi tên bài + nghệ sĩ). Báo lỗi chỉ mở form GitHub điền sẵn nội dung bạn viết cùng thông tin chẩn đoán (phiên bản, macOS, chip, trạng thái quyền). Camera chỉ chạy khi bạn mở khung xem trước và không lưu hình.

## Trạng thái & giới hạn

- Nhiều tính năng dựa trên API riêng tư của Apple (cuộc gọi iPhone, đồng hồ hệ thống, độ sáng, màn hình khoá, đọc thông báo) và có thể thay đổi giữa các bản macOS. Nếu một phần không chạy, các phần còn lại vẫn hoạt động; mục *Nâng cao → Chẩn đoán…* giúp tìm nguyên nhân.
- Nút điều khiển trong app gọi phụ thuộc việc app đó lộ nút ra Trợ năng; Zalo, Messenger và các app khác có thể cần chỉnh theo từng phiên bản.
- Cuộc gọi trong trình duyệt chỉ có nút khi trang lộ được nút ra hệ thống.
- Đảo chỉ hiện trên một màn hình (chọn trong Cài đặt). HUD độ sáng chỉ dành cho màn hình tích hợp.

## Lộ trình

Lịch sử Clipboard · kệ kéo-thả file · lời bài hát đồng bộ · lịch + nút Join · giám sát hệ thống · bản tiếng Anh.

## Ghi công

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3) – đọc Now Playing trên macOS 15.4+.
- Tác giả: **Phong** ([@fonghtdev](https://github.com/fonghtdev)) · liên hệ: fonght.dev@gmail.com
