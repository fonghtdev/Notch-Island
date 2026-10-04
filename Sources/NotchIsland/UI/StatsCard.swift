import SwiftUI

/// Trang Thống kê trong menu ☰ của island: CPU, RAM, ổ đĩa, mạng. Chỉ đọc số liệu khi trang đang hiện.
struct StatsCard: View {
    @StateObject private var monitor = SystemStatsMonitor()

    var body: some View {
        let stats = monitor.stats
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                StatTile(symbol: "cpu", title: "CPU", value: stats.map { "\(Int(($0.cpu * 100).rounded()))%" } ?? "–",
                         fraction: stats?.cpu)
                StatTile(symbol: "memorychip", title: "RAM", value: stats.map { Self.bytes($0.memoryUsed) } ?? "–",
                         detail: stats.map { "/ \(Self.bytes($0.memoryTotal))" },
                         fraction: stats.map { Double($0.memoryUsed) / Double(max($0.memoryTotal, 1)) })
                StatTile(symbol: "internaldrive", title: "Ổ đĩa", value: stats.map { Self.bytes($0.diskFree) } ?? "–",
                         detail: "trống",
                         fraction: stats.map { 1 - Double($0.diskFree) / Double(max($0.diskTotal, 1)) })
                StatTile(symbol: "arrow.up.arrow.down", title: "Mạng", value: stats.map { "↓ \(Self.rate($0.netDown))" } ?? "–",
                         detail: stats.map { "↑ \(Self.rate($0.netUp))" })
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    private static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
}

private struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    var detail: String?
    var fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail ?? " ")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            bar
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPill(RoundedRectangle(cornerRadius: 14, style: .continuous), fallbackOpacity: 0.08, interactive: false)
    }

    /// Thanh mảnh; tiles không có tỉ lệ (mạng) vẫn chừa chỗ để các ô đều nhau.
    private var bar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(fraction == nil ? 0 : 0.15))
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.85))
                    .frame(width: proxy.size.width * CGFloat(min(max(fraction ?? 0, 0), 1)))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .frame(height: 3)
    }
}
