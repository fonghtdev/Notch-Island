import AppKit
import CoreMedia
import ScreenCaptureKit

/// Màu bốn cạnh màn hình, mỗi cạnh chia thành vài đoạn (trái→phải, trên→dưới).
struct AmbientColors: Equatable {
    struct RGB: Equatable {
        var r = 0.0, g = 0.0, b = 0.0
        func mixed(with other: RGB, _ t: Double) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }
    }

    var top: [RGB]
    var bottom: [RGB]
    var left: [RGB]
    var right: [RGB]

    static let topSegments = 10
    static let sideSegments = 6

    /// Chuyển dần từ màu cũ sang màu mới để ánh sáng không nhấp nháy theo từng khung hình.
    func mixed(with other: AmbientColors, _ t: Double) -> AmbientColors {
        func mix(_ a: [RGB], _ b: [RGB]) -> [RGB] { zip(a, b).map { $0.mixed(with: $1, t) } }
        return AmbientColors(top: mix(top, other.top), bottom: mix(bottom, other.bottom),
                             left: mix(left, other.left), right: mix(right, other.right))
    }
}

/// Chụp màn hình ở độ phân giải rất nhỏ (64 điểm ngang, ~10 khung/giây) rồi lấy màu từng cạnh – nền cho Ambient light.
/// Dùng ScreenCaptureKit nên cần quyền Ghi màn hình; cửa sổ của chính NotchIsland bị loại ra để ánh sáng không tự chụp lại mình.
final class AmbientLightService: NSObject, SCStreamOutput, SCStreamDelegate {
    var onColors: ((AmbientColors) -> Void)?
    var onStop: (() -> Void)?

    private var stream: SCStream?
    private let queue = DispatchQueue(label: "notchisland.ambient", qos: .utility)
    private var smoothed: AmbientColors?

    private static let width = 64
    private static let framesPerSecond: Int32 = 10

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// false nếu chưa có quyền (đã hiện hộp thoại xin quyền) hoặc không bắt đầu được.
    func start(displayID: Int) async -> Bool {
        guard stream == nil else { return true }
        guard Self.hasPermission else {
            CGRequestScreenCaptureAccess()
            return false
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { Int($0.displayID) == displayID }) ?? content.displays.first
            else { return false }
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }

            let config = SCStreamConfiguration()
            config.width = Self.width
            config.height = max(1, Self.width * display.height / max(display.width, 1))
            config.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.queueDepth = 3

            let stream = SCStream(
                filter: SCContentFilter(display: display, excludingApplications: own, exceptingWindows: []),
                configuration: config, delegate: self
            )
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()
            self.stream = stream
            return true
        } catch {
            NSLog("NotchIsland: Ambient light không bắt đầu được – \(error.localizedDescription)")
            return false
        }
    }

    func stop() {
        let current = stream
        stream = nil
        smoothed = nil
        Task { try? await current?.stopCapture() }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        DispatchQueue.main.async { [weak self] in self?.onStop?() }
    }

    // MARK: - Lấy màu

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, CMSampleBufferIsValid(buffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = CMSampleBufferGetImageBuffer(buffer)
        else { return }

        let fresh = Self.edgeColors(of: pixels)
        let mixed = smoothed.map { $0.mixed(with: fresh, 0.45) } ?? fresh
        smoothed = mixed
        DispatchQueue.main.async { [weak self] in self?.onColors?(mixed) }
    }

    /// Trung bình màu một dải dày ~1/8 ảnh dọc theo mỗi cạnh.
    static func edgeColors(of pixels: CVPixelBuffer) -> AmbientColors {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let w = CVPixelBufferGetWidth(pixels), h = CVPixelBufferGetHeight(pixels)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(pixels)?.assumingMemoryBound(to: UInt8.self) else {
            return AmbientColors(top: [], bottom: [], left: [], right: [])
        }
        let depth = max(2, min(w, h) / 8)

        func average(xs: Range<Int>, ys: Range<Int>) -> AmbientColors.RGB {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for y in ys {
                for x in xs {
                    let p = base + y * stride + x * 4   // BGRA
                    b += Double(p[0]); g += Double(p[1]); r += Double(p[2]); n += 1
                }
            }
            return n == 0 ? .init() : .init(r: r / n / 255, g: g / n / 255, b: b / n / 255)
        }
        func slices(_ count: Int, of total: Int) -> [Range<Int>] {
            (0..<count).map { i in (i * total / count)..<max((i + 1) * total / count, i * total / count + 1) }
        }

        let columns = slices(AmbientColors.topSegments, of: w)
        let rows = slices(AmbientColors.sideSegments, of: h)
        return AmbientColors(
            top: columns.map { average(xs: $0, ys: 0..<depth) },
            bottom: columns.map { average(xs: $0, ys: (h - depth)..<h) },
            left: rows.map { average(xs: 0..<depth, ys: $0) },
            right: rows.map { average(xs: (w - depth)..<w, ys: $0) }
        )
    }
}
