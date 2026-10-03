import SwiftUI

/// Nền của island theo `IslandSurface`: đen đặc, kính mờ, hoặc Liquid Glass.
/// Kích thước do nơi dùng quyết định (`.frame`), view này chỉ lấp đầy khung đó theo `shape`.
struct IslandBackground<S: Shape>: View {
    let shape: S
    let surface: IslandSurface

    var body: some View {
        switch surface.style {
        case .solid:
            shape.fill(Color.black)
        case .frosted:
            frosted
        case .glass:
            glass
        }
    }

    // MARK: - Kính mờ (mọi macOS 13+)

    private var frosted: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(surface.tint.opacity(surface.tintStrength)))
            .overlay(GlassRim(shape: shape))
    }

    // MARK: - Liquid Glass (macOS 26+, build bằng Xcode 26 / Swift 6.2+)

    @ViewBuilder
    private var glass: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(glassStyle, in: shape)
                .overlay(GlassRim(shape: shape))
        } else {
            frosted
        }
        #else
        frosted
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var glassStyle: Glass {
        let base: Glass = surface.isClear ? .clear : .regular
        return base.tint(surface.tint.opacity(surface.tintStrength))
    }
    #endif
}
