import AppKit
import CoreImage
import SwiftUI

/// Giải mã ảnh bìa (base64) và tính màu chủ đạo. Có cache 1 phần tử vì
/// adapter gửi lại cùng ảnh bìa ở mỗi lần cập nhật.
final class ArtworkProcessor {
    struct Result {
        let id: Int
        let image: NSImage
        let accent: Color?
    }

    private var cache: Result?
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// Gọi được từ background thread.
    func process(base64: String?) -> Result? {
        guard let base64, !base64.isEmpty else { return nil }
        let id = base64.hashValue
        if let cache, cache.id == id { return cache }

        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              let image = NSImage(data: data)
        else { return nil }

        let result = Result(id: id, image: enhanced(image), accent: accentColor(of: image))
        cache = result
        return result
    }

    /// Ảnh bìa nhỏ (vd. 300 px) mà hiện to trên màn Retina thì bị nhoè: phóng bằng Lanczos lên tối thiểu 720 px
    /// rồi làm nét nhẹ – rõ hơn nhiều so với phóng nội suy mặc định. Ảnh đã đủ lớn thì giữ nguyên.
    private func enhanced(_ image: NSImage) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = CGFloat(cgImage.width)
        let target: CGFloat = 720
        guard width > 0, width < target else { return image }

        let scale = target / width
        let input = CIImage(cgImage: cgImage)
        guard let lanczos = CIFilter(name: "CILanczosScaleTransform", parameters: [
            kCIInputImageKey: input,
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0,
        ])?.outputImage else { return image }

        var output = lanczos
        if let sharp = CIFilter(name: "CISharpenLuminance", parameters: [
            kCIInputImageKey: lanczos,
            kCIInputSharpnessKey: 0.45,
        ])?.outputImage {
            output = sharp
        }

        let extent = lanczos.extent
        guard let rendered = context.createCGImage(
            output, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else { return image }
        return NSImage(cgImage: rendered, size: NSSize(width: extent.width, height: extent.height))
    }

    /// Lấy màu trung bình (CIAreaAverage) rồi đẩy độ sáng/độ bão hoà lên để nổi trên nền đen.
    private func accentColor(of image: NSImage) -> Color? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: input,
            kCIInputExtentKey: CIVector(cgRect: input.extent),
        ]), let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        let average = NSColor(
            srgbRed: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let boosted = NSColor(
            hue: hue,
            saturation: min(saturation * 1.3, 1),
            brightness: max(brightness, 0.8),
            alpha: 1
        )
        return Color(nsColor: boosted)
    }
}
