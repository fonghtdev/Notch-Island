import SwiftUI

/// Các mảnh dựng nên giao diện Liquid Glass kiểu Control Center của macOS 26: viền "khối kính" có chiều sâu,
/// viên thuốc bằng kính thật, và nhóm kính để các viên thuốc gần nhau hoà vào nhau.
/// Không phải macOS 26 / không dùng kiểu Liquid Glass thì mọi thứ tự lùi về nền trắng mờ như trước.

// MARK: - Môi trường

private struct IslandGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// true khi island đang vẽ bằng Liquid Glass thật (đã chọn kiểu này VÀ máy hỗ trợ).
    var islandGlass: Bool {
        get { self[IslandGlassKey.self] }
        set { self[IslandGlassKey.self] = newValue }
    }
}

// MARK: - Viền khối kính

/// Viền kính có chiều sâu: mép trong tối dần (ánh sáng bị bẻ cong ở rìa), vệt sáng sắc ở mép ngoài.
/// Đỉnh island dính mép màn hình nên không có vệt sáng ở đó.
struct GlassRim<S: Shape>: View {
    let shape: S

    var body: some View {
        ZStack {
            shape
                .stroke(Color.black.opacity(0.22), lineWidth: 5)
                .blur(radius: 3)
                .clipShape(shape)
            // Quầng sáng mềm sát đáy, bên trong mép: tạo độ dày của khối kính như viên thuốc trong Control Center.
            shape
                .stroke(Color.white.opacity(0.16), lineWidth: 6)
                .blur(radius: 4)
                .clipShape(shape)
                .mask(LinearGradient(colors: [.clear, .white], startPoint: .center, endPoint: .bottom))
            shape.stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.18), location: 0.3),
                        .init(color: .white.opacity(0.05), location: 0.62),
                        .init(color: .white.opacity(0.6), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.6
            )
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Viên thuốc kính

private struct GlassPillModifier<S: Shape>: ViewModifier {
    @Environment(\.islandGlass) private var glass
    let shape: S
    let fallbackOpacity: Double
    let hovering: Bool
    let interactive: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if glass, #available(macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            plain(content)
        }
        #else
        plain(content)
        #endif
    }

    private func plain(_ content: Content) -> some View {
        content.background(shape.fill(.white.opacity(fallbackOpacity + (hovering ? 0.12 : 0))))
    }
}

extension View {
    /// Nền viên thuốc / nút: kính thật khi island đang dùng Liquid Glass, không thì nền trắng mờ.
    func glassPill<S: Shape>(
        _ shape: S = Capsule(), fallbackOpacity: Double = 0.1, hovering: Bool = false, interactive: Bool = true
    ) -> some View {
        modifier(GlassPillModifier(shape: shape, fallbackOpacity: fallbackOpacity, hovering: hovering, interactive: interactive))
    }
}

// MARK: - Nhóm kính

/// Gom các viên thuốc kính gần nhau vào một vùng lấy mẫu chung (kính không lấy mẫu kính khác) để chúng hoà vào nhau.
struct GlassGroup<Content: View>: View {
    @Environment(\.islandGlass) private var glass
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if glass, #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
