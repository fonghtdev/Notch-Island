import CoreVideo
import Foundation

var pb: CVPixelBuffer?
CVPixelBufferCreate(nil, 64, 36, kCVPixelFormatType_32BGRA, nil, &pb)
let buf = pb!
CVPixelBufferLockBaseAddress(buf, [])
let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
let stride = CVPixelBufferGetBytesPerRow(buf)
for y in 0..<36 { for x in 0..<64 {
    let p = base + y * stride + x * 4
    if x < 32 { p[0] = 0; p[1] = 0; p[2] = 255 } else { p[0] = 255; p[1] = 0; p[2] = 0 }   // BGRA: trái đỏ, phải xanh dương
    p[3] = 255
} }
CVPixelBufferUnlockBaseAddress(buf, [])

let c = AmbientLightService.edgeColors(of: buf)
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.01 }
assert(c.top.count == AmbientColors.topSegments && c.bottom.count == AmbientColors.topSegments)
assert(c.left.count == AmbientColors.sideSegments && c.right.count == AmbientColors.sideSegments)
// 10 đoạn ngang: 5 đoạn đầu đỏ, 5 đoạn cuối xanh
assert(c.top[0].r > 0.99 && close(c.top[0].b, 0) && c.top[9].b > 0.99 && close(c.top[9].r, 0))
assert(c.bottom[4].r > 0.99 && c.bottom[5].b > 0.99)
// cạnh trái toàn đỏ, cạnh phải toàn xanh
assert(c.left.allSatisfy { $0.r > 0.99 && close($0.b, 0) } && c.right.allSatisfy { $0.b > 0.99 && close($0.r, 0) })
// làm mượt: giữa đỏ và xanh ở t = 0.5
let mid = c.top[0].mixed(with: c.top[9], 0.5)
assert(close(mid.r, 0.5) && close(mid.b, 0.5))
print("OK: edgeColors + mixed đúng")
