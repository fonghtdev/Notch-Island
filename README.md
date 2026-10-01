# NotchIsland

Dynamic Island cho macOS – mã nguồn mở, viết bằng Swift + SwiftUI, không phụ thuộc thư viện ngoài.
Một bản thay thế tự xây cho Alcove.

## Tính năng (v0.10)

| Trạng thái | Khi nào | Hiển thị |
|---|---|---|
| **Collapsed** | Không có gì | Đảo trùng khít notch, "tàng hình" |
| **Compact** | Đang phát nhạc, hoặc có hoạt động đang diễn ra (hẹn giờ, cuộc gọi, ghi âm…) | Hai cánh nhỏ: ảnh bìa + sóng nhạc, hoặc biểu tượng + đồng hồ của hoạt động |
| **Banner** | Cắm/rút sạc, tai nghe Bluetooth kết nối/ngắt, hết giờ | Thẻ nở xuống dưới notch (vòng pin động + thời gian còn lại + công suất bộ sạc; biểu tượng tai nghe chuẩn Apple + pin từng tai) |
| **HUD** | Đổi âm lượng / độ sáng màn hình / đèn bàn phím | Hai cánh nở ra + thanh (hoặc vạch / vòng) giá trị, tự tắt sau ~1,6 giây |
| **Expanded** | Rê chuột (hoặc bấm) vào notch | Thẻ Now Playing (ảnh bìa, thanh tiến trình **kéo để tua**, ⏮ ⏯ ⏭; **bấm vào bài để mở đúng tab/app đang phát**) + hàng hoạt động bên dưới; khi rảnh: nút hẹn giờ nhanh + vòng pin |

- **Now Playing từ mọi nguồn**: YouTube/SoundCloud trên Chrome-Safari-Arc, Apple Music, Spotify, VLC, Podcasts… kèm ảnh bìa thật; màu nhấn lấy từ ảnh bìa.
- Tự nhận diện notch thật (MacBook 2021+); màn rời/máy không notch → tạo notch giả.
- Click xuyên qua khi chuột không nằm trên đảo – không cản thanh menu.
- Có mặt ở mọi Space và cả khi app khác full-screen.
- Animation spring, hình đảo có "tai" cong ngược như Dynamic Island.
- **Tua bài**: bấm hoặc kéo trên thanh tiến trình (qua lệnh `seek` của adapter; nguồn dự phòng dùng AppleScript).
- **HUD âm lượng, độ sáng màn hình, đèn bàn phím**: hiện trên đảo. **Mặc định đã thay HUD của macOS** (lần đầu chạy sẽ xin quyền Trợ năng, xem bên dưới).
- **Bấm để mở nguồn**: bấm ảnh bìa / tên bài trong thẻ mở rộng → chuyển tới đúng tab YouTube (Chrome, Brave, Edge, Arc, Safari) hoặc đưa Spotify/Music lên trước. Lần đầu macOS hỏi quyền Automation cho trình duyệt.
- **Hoạt động đang diễn ra (live activities)**: hẹn giờ (menu bar → *Hẹn giờ*, hoặc nút trên thẻ khi rảnh), và tự nhận **app đang dùng micro / camera** – Discord, Meet, Zoom, Teams, FaceTime → "cuộc gọi" có đồng hồ đếm lên; Voice Memos, QuickTime, OBS → "đang ghi âm". Thu gọn: biểu tượng + đồng hồ ở hai cánh; rê chuột: hàng đầy đủ (bấm để mở app; hẹn giờ có nút tạm dừng / dừng).
- **Tai nghe Bluetooth**: khi kết nối/ngắt hiện thẻ có biểu tượng chuẩn Apple (SF Symbols: AirPods, AirPods Pro, AirPods Max, Beats; hãng khác dùng biểu tượng chung), trạng thái kết nối và pin từng tai + hộp sạc (AirPods) hoặc pin chung.
- **Thẻ cắm/rút sạc mới**: viên pin nằm ngang chạy đầy, tia chớp nhấp nháy khi sạc, % lớn và thời gian còn lại ("Đầy sau 1 giờ 20 phút" / "Dùng được 3 giờ 5 phút").
- **Màn hình khoá (thử nghiệm)**: khi khoá máy, thẻ hiện giữa màn hình gồm nhạc đang phát, cuộc gọi / hẹn giờ, và (tuỳ chọn) thông báo. Xem mục giới hạn bên dưới.
- **Tuỳ chỉnh giao diện HUD** (Cài đặt → Giao diện HUD, có xem trước trực tiếp): kiểu *Thanh / Vạch (16 nấc) / Vòng*, bo góc *Tròn / Bo nhẹ / Vuông*, độ dày, hiện/ẩn số %, **màu riêng cho từng loại** (âm lượng, độ sáng, đèn bàn phím).
- **Hình dạng đảo cố định**: một tỉ lệ chuẩn duy nhất (thẻ mở 440×172, bo góc 10/26), không cần chỉnh.
- **Nền đảo** (Cài đặt → Nền đảo): *Đen* (mặc định, liền với notch) / *Kính mờ* (Material, macOS 13+) / **Liquid Glass** (`glassEffect` của macOS 26, có chế độ Clear), kèm màu phủ và độ đậm để chữ vẫn dễ đọc trên hình nền sáng. Bản xem trước hiện trên nền nhiều màu để thấy hiệu ứng kính.
- **Cài đặt** (menu bar → *Cài đặt…*, ⌘,): bật/tắt từng tính năng, rê chuột hay bấm để mở, chọn màn hình hiển thị, mở cùng macOS. Lưu tự động bằng UserDefaults.
- Icon trên thanh menu: demo (sạc, HUD), nguồn nhạc đang dùng, Cài đặt, thoát.

**Thay đổi v0.10**
- Đã **gỡ hoàn toàn Face ID / PAM** (app tự xoá dữ liệu khuôn mặt và khoá cũ khi khởi động).
- Sửa "Micro đang bật" báo sai (dịch vụ nền `com.apple.CoreSpeech` bị lọc; chỉ tính app người dùng thấy được).
- Hẹn giờ + **bấm giờ** (menu bar → *Hẹn giờ* / *Bấm giờ*, hoặc nút trên thẻ khi rảnh); đọc thử hẹn giờ / bấm giờ của **app Đồng hồ** hệ thống qua framework riêng tư (thử nghiệm – menu *Chẩn đoán Đồng hồ…* để kiểm tra).
- Ghi âm (Voice Memos…): nút **tạm dừng / tiếp tục / dừng** trên đảo, bấm nút của app qua Trợ năng (cần cấp quyền *Trợ năng* cho NotchIsland).
- Tai nghe: biểu tượng chuẩn Apple (SF Symbols) cho AirPods / AirPods Pro / AirPods Max / Beats, biểu tượng chung cho tai nghe hãng khác.
- Hover / unhover mượt hơn: thu lại gần như tức thì, không nảy; thẻ cắm / rút sạc thiết kế lại (vòng pin, công suất bộ sạc); mọi thứ ở hai cánh căn giữa theo chiều dọc.

## Yêu cầu

- macOS 13 Ventura trở lên
- Xcode 15+ (hoặc Command Line Tools có Swift 5.9+). Muốn có **Liquid Glass**: macOS 26 + Xcode 26 (Swift 6.2+)
- `cmake` để build adapter đọc Now Playing: `brew install cmake`

## Chạy

```bash
# 1. Tải + build adapter đọc Now Playing (một lần)
./scripts/fetch-adapter.sh

# 2a. Chạy nhanh khi phát triển (đứng ở thư mục gốc dự án để tìm thấy Vendor/)
swift run

# 2b. Hoặc đóng gói thành .app (tự nhúng adapter; cần cho "Mở cùng macOS")
./scripts/build-app.sh
open build/NotchIsland.app
```

Không có adapter thì app vẫn chạy, nhưng tự lùi về nguồn dự phòng (chỉ Music + Spotify). Menu bar cho biết đang dùng nguồn nào.

**Không thấy nhạc?** Menu bar → *Chẩn đoán nhạc…*: hiện adapter có được tìm thấy không, số dòng đã nhận, lỗi (stderr) của adapter và kết quả lệnh `get` thực tế, kèm nút *Sao chép*. Nguyên nhân thường gặp: chạy `swift run` không đứng ở thư mục gốc dự án nên không thấy `Vendor/`, hoặc chưa chạy `fetch-adapter.sh`.

Mở bằng Xcode: `open Package.swift` → chọn scheme **NotchIsland** → Run.

Nếu chạy ở nguồn dự phòng, lần đầu bấm nút điều khiển macOS sẽ hỏi quyền **Automation** cho Music/Spotify – chọn Allow.

### Quyền cho HUD thay thế

Cần vì HUD thay thế được bật mặc định (tắt ở *Cài đặt → Thay HUD mặc định của macOS*). App bắt phím âm lượng/độ sáng/đèn bàn phím bằng `CGEventTap` nên macOS đòi quyền **Trợ năng** (System Settings → Privacy & Security → Accessibility). Khi chạy bằng `swift run`, quyền này cấp cho **ứng dụng Terminal** đang chạy lệnh (không phải cho NotchIsland); khi chạy từ `NotchIsland.app` thì cấp cho chính app. Cấp xong không cần khởi động lại, app tự nhận trong vài giây.
Không bật tuỳ chọn này thì HUD của ta chỉ hiện khi **âm lượng** đổi (HUD hệ thống vẫn hiện song song), còn độ sáng không có HUD riêng.

## Kiến trúc (3C: Cover – Clean – Clear)

```
Sources/NotchIsland/
├── App/        Entry, AppDelegate           → khởi động, lắp ráp, menu bar
├── Core/       Metrics, Geometry, Models,   → dữ liệu + trạng thái, KHÔNG đụng AppKit view
│               AppSettings, HUDAppearance, ColorHex, IslandViewModel
├── Services/   BatteryService,              → nói chuyện với hệ thống, đẩy callback về main
│   ├ NowPlaying/  Provider protocol, MediaRemoteAdapter, DistributedNotification (dự phòng),
│   │              ArtworkProcessor, NowPlayingService (tự fallback)
│   ├ Activity/    TimerService, CaptureMonitor (micro/camera), ActivityCenter
│   ├ Headphones/  HeadphoneMonitor (CoreAudio + system_profiler)
│   ├ Lock/        LockStateMonitor, NotificationReader (SQLite của usernoted)
│   ├ SourceOpener (AppleScript mở đúng tab)
│   └ HUD/         VolumeController (CoreAudio), BrightnessController (DisplayServices),
│                  KeyboardBacklightController (CoreBrightness), MediaKeyTap (CGEventTap), HUDService
├── Settings/   SettingsView, WindowController → cửa sổ Cài đặt (SwiftUI)
├── Window/     NotchPanel, WindowController → cửa sổ trong suốt, theo dõi chuột
│               LockScreenController, SkyLightSpace → thẻ trên màn hình khoá
└── UI/         NotchShape, RootView,        → SwiftUI thuần, chỉ đọc ViewModel
                CompactView, ExpandedView, HUDView, BannerView, ActivityRow,
                HeadphoneIcon, LockScreenView
```

Luồng dữ liệu một chiều:

```
Services ──callback──▶ IslandViewModel ──@Published──▶ SwiftUI Views
                             ▲
WindowController ──hover─────┘  (setExpanded)
```

- **Cover** – xử lý đủ các trường hợp biên: không có notch, Mac để bàn không pin, nhiều player cùng lúc, đổi màn hình, full-screen.
- **Clean** – mỗi lớp một việc; mọi con số nằm trong `IslandMetrics`; `mode` và `contentSize` được *suy ra* từ state, không lưu trùng.
- **Clear** – tên rõ nghĩa, chú thích tiếng Việt ở những chỗ "vì sao".

### Vài quyết định kỹ thuật

- **Panel cố định kích thước tối đa**, chỉ hình đảo bên trong đổi size → animation mượt, không phải resize `NSWindow` mỗi frame.
- **Click-through động**: `ignoresMouseEvents` bật/tắt theo vị trí chuột so với `islandRect()`. Global monitor cho sự kiện chuột không cần quyền Accessibility; thêm timer 5 Hz làm lưới an toàn.
- **Now Playing theo kiến trúc provider.** `MediaRemote.framework` là API riêng tư và bị Apple khoá với app bên thứ ba từ macOS 15.4. Nguồn chính dùng [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3): chạy `/usr/bin/perl` – tiến trình hệ thống vẫn được phép – để đọc MediaRemote, nhận JSON từng dòng. Nếu adapter thiếu hoặc bị Apple vá, `NowPlayingService` tự chuyển sang provider dự phòng dùng distributed notifications của Music/Spotify (API công khai).
- **Pin qua IOKit Power Sources** – API công khai, nhận thông báo tức thì khi cắm/rút.
- **HUD**: âm lượng đọc/ghi bằng CoreAudio (công khai) và *lắng nghe* thay đổi từ mọi nguồn. Độ sáng không có API công khai nên nạp `DisplayServices.framework` (riêng tư) lúc chạy bằng `dlopen`; nếu thiếu thì app không chặn phím độ sáng. Chế độ thay thế nuốt phím media rồi tự chỉnh, phím Shift+Option cho bước nhỏ 1/64 như macOS.
- **Đèn nền bàn phím**: `KeyboardBrightnessClient` (CoreBrightness, riêng tư) gọi qua IMP lúc chạy, có kiểm tra class/selector; trên Apple Silicon chỉ setter `setBrightness:fadeSpeed:commit:forKeyboard:` có tác dụng. Đây là phần **thử nghiệm**, chưa kiểm chứng trên mọi đời máy. Phím đèn nền là mã 21/22/23 cùng loại sự kiện với phím âm lượng.
- **Tuỳ chỉnh giao diện**: `AppSettings` → `HUDAppearance` (dữ liệu thuần) → `HUDView` / `LevelSlider` / bản xem trước; màu lưu dạng hex `#RRGGBB` trong UserDefaults.
- **Liquid Glass**: `IslandBackground` gọi `.glassEffect(_:in:)` với hình `NotchShape` tuỳ biến. Mã được bọc trong `#if compiler(>=6.2)` + `#available(macOS 26.0, *)`: build bằng bộ công cụ cũ hoặc chạy trên macOS cũ thì tự dùng kính mờ (Material). Trên máy có notch thật, đảo vẫn đen lúc thu gọn (kính chỉ hiện khi nở ra) để liền khối với notch; `IslandSurface.supportsLiquidGlass` cho biết máy có dùng được Liquid Glass hay không.
- **Micro/camera theo app**: CoreAudio "process objects" (macOS 14.2+) cho biết tiến trình nào đang MỞ micro kèm bundle ID (tiến trình phụ `.helper` được đưa về app chính); camera dùng CoreMediaIO nên chỉ biết "đang bật", không biết app nào. Trình duyệt mở micro được coi là cuộc họp (không phân biệt được Meet với trang web khác).
- **Tai nghe**: danh sách thiết bị âm thanh CoreAudio có `transport type = Bluetooth` → biết kết nối/ngắt tức thì, không cần quyền Bluetooth. Pin lấy từ `system_profiler SPBluetoothDataType -json` (chạy nền lúc kết nối và mỗi 60 giây).
- **Màn hình khoá**: `SkyLightSpace` nạp SkyLight (riêng tư) bằng `dlopen`, tạo một Space có tầng tuyệt đối 400 và chuyển cửa sổ thẻ vào đó để vẽ đè lên màn hình khoá. Chỉ thẻ này được chuyển (đảo chính không đụng tới). Thẻ tự ẩn khi không có nội dung để không chắn ô mật khẩu.
- **Thông báo**: không có API công khai; `NotificationReader` sao chép file SQLite của `usernoted` sang thư mục tạm rồi đọc (cần quyền Toàn bộ ổ đĩa). Mặc định TẮT.
- **Kích thước cố định**: không còn scale/bo góc tuỳ chỉnh, nội dung bố cục thẳng theo `IslandMetrics`. Khi đang giữ chuột (kéo thanh tiến trình) đảo không tự thu lại.

## Giới hạn hiện tại

- **Màn hình khoá, đọc thông báo, micro/camera theo app, tai nghe, mở đúng tab đều là tính năng dựa trên API riêng tư / không chính thức và CHƯA được kiểm chứng trên máy thật** (mã chưa từng được biên dịch trong môi trường phát triển). Nếu một phần không chạy, các phần còn lại vẫn hoạt động.
- Thẻ màn hình khoá chưa chắc nhận được click trên mọi bản macOS; đọc thông báo có thể hỏng khi Apple đổi định dạng cơ sở dữ liệu.
- Micro/camera theo app cần macOS 14.2+ (bản cũ hơn: chỉ còn hẹn giờ).
- Hẹn giờ là của chính app; macOS không cho đọc hẹn giờ của ứng dụng Đồng hồ / Siri.
- Đã bỏ trang "điều khiển nhanh" (3 thanh trượt); đổi âm lượng/độ sáng dùng phím như bình thường, HUD hiện trên đảo.
- Đồng hồ hệ thống: đọc bằng framework riêng tư nên có thể không chạy trên mọi bản macOS; dùng *Chẩn đoán Đồng hồ…* để kiểm tra.
- Cách đọc MediaRemote là một "lỗ hổng" mà Apple có thể vá ở bản macOS sau; khi đó app chỉ còn nguồn dự phòng (Music + Spotify).
- Ảnh bìa đôi khi tải chậm hoặc không có (do adapter/nguồn phát).
- Nếu một phím không phản hồi, chạy với `NOTCHISLAND_DEBUG_KEYS=1 swift run` để xem mã phím trong log.
- HUD độ sáng chỉ dành cho màn hình tích hợp của MacBook, dựa vào API riêng tư nên có thể hỏng ở bản macOS sau; phím độ sáng của một số bàn phím ngoài có thể không bị bắt.
- Đảo chỉ hiện trên **một** màn hình (chọn trong Cài đặt), chưa hiện đồng thời trên nhiều màn.
- Liquid Glass render trong cửa sổ không phải cửa sổ chính (panel của đảo không bao giờ nhận focus) nên có thể trông phẳng / ít hiệu ứng hơn kính của cửa sổ đang hoạt động.

## Lộ trình gợi ý

1. Lời bài hát / chọn thiết bị âm thanh.
2. Sự kiện lịch sắp tới (EventKit).
3. "Shelf" kéo-thả file tạm vào đảo, AirDrop nhanh.
4. HUD độ sáng bàn phím, HUD cho màn hình ngoài (DDC).
5. Hỗ trợ đảo trên từng màn hình cùng lúc.

## v0.11 – gọn hơn, nhiều chuyển động hơn

- Thẻ mở rộng **co giãn theo nội dung**: chỉ nở to (440×148/172) khi có nhạc; chỉ có hẹn giờ / ghi âm / cuộc gọi thì thu còn 348 pt; rảnh thì một hàng nhỏ 300×88 (pin + 5′ 10′ 25′ + bấm giờ), bỏ dòng "Không có gì đang phát".
- Hàng hoạt động: đồng hồ + nút gom vào một viên thuốc bên phải, biểu tượng có vòng sáng lan khi đang ghi âm / gọi.
- Banner cắm / rút sạc tối giản: tia chớp | camera | phần trăm đếm lên, thanh pin mảnh có vệt sáng khi đang sạc, một dòng chữ.
- Chuyển động chung (`UI/Motion.swift`): các phần tử hiện lần lượt, đổi biểu tượng pause/play kiểu replace, hover nhấn nhẹ.

## Chạy nhanh (một lệnh)

```bash
cd NotchIsland && ./run.sh            # build + chạy
./run.sh install                      # build + chép vào /Applications + chạy
```

## Phát hành cho người dùng (tải về là chạy)

1. Đẩy code lên GitHub, rồi gắn tag: `git tag v1.0.0 && git push origin v1.0.0`.
2. GitHub Actions (`.github/workflows/release.yml`) tự build bản **universal** (Apple Silicon + Intel), đóng gói `NotchIsland-1.0.0.dmg` và `.zip`, rồi đăng lên mục **Releases**.
3. Người dùng tải DMG, kéo NotchIsland vào Applications và mở. Không cần Terminal, Xcode hay cmake.

Build thủ công cùng kết quả: `VERSION=1.0.0 ./scripts/make-dmg.sh` (ra thư mục `dist/`).

### Cảnh báo của macOS (Gatekeeper)

- **Không có Apple Developer ID (mặc định, miễn phí):** lần đầu mở, macOS báo "không thể xác minh". Người dùng chỉ cần **chuột phải → Open → Open** (macOS 15 trở lên: *System Settings → Privacy & Security → Open Anyway*), một lần duy nhất. Mỗi bản cập nhật có thể phải cấp lại quyền Trợ năng.
- **Có Apple Developer ID (99 USD/năm):** thêm các secret `MACOS_CERT_P12`, `MACOS_CERT_PASSWORD` (chứng chỉ Developer ID Application, base64), `SIGN_IDENTITY`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_PASSWORD` (app-specific password) vào Settings → Secrets của repo. Workflow sẽ tự ký, notarize và staple → mở là chạy, không còn cảnh báo.

> Menu trên thanh menu bar chỉ gồm Hẹn giờ, Bấm giờ, Cài đặt, Thoát. Giữ phím **Option** khi mở menu để hiện mục **Nâng cao** (demo hiệu ứng, chẩn đoán nhạc / Đồng hồ – hữu ích khi báo lỗi).

### Lần chạy đầu tiên (tự cấu hình)

Lần mở đầu tiên NotchIsland tự bật **Mở cùng macOS** và hiện một hộp chào xin quyền **Trợ năng** (một lần duy nhất). Người dùng bật NotchIsland trong danh sách là HUD thay thế có hiệu lực ngay, không cần mở lại app. Nếu mở app thẳng từ ổ DMG, app nhắc kéo vào Applications trước. macOS không cho app tự cấp quyền Trợ năng cho chính nó, đó là bước duy nhất người dùng phải bấm.

### Ảnh bìa độ phân giải cao

Ảnh bìa mà player gửi qua MediaRemote thường chỉ vài trăm pixel. NotchIsland tra thêm trên iTunes Search API (chỉ gửi tên bài + nghệ sĩ tới Apple) và dùng ảnh 1200×1200 khi tên bài và nghệ sĩ khớp rõ ràng; không khớp thì giữ ảnh gốc, hiển thị đúng tỉ lệ (vuông hoặc ngang). Tắt trong Cài đặt → Hiển thị nếu không muốn.
