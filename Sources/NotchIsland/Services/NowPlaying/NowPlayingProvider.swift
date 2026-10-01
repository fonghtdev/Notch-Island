import Foundation

/// Một nguồn cung cấp thông tin "Đang phát".
/// Quy ước: mọi callback đều được gọi trên main thread.
protocol NowPlayingProvider: AnyObject {
    /// Tên hiển thị để debug / hiện trong menu.
    var name: String { get }
    var onChange: ((NowPlayingInfo?) -> Void)? { get set }
    /// Provider không thể hoạt động nữa → service sẽ chuyển sang provider dự phòng.
    var onFailure: (() -> Void)? { get set }

    /// Tóm tắt trạng thái nội bộ để chẩn đoán khi không thấy nhạc.
    var diagnostics: String { get }

    func start()
    func stop()
    func send(_ command: MediaCommand)
    /// Tua tới vị trí `seconds` (tính từ đầu bài).
    func seek(to seconds: TimeInterval)
}
