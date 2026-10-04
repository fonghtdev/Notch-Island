import Darwin
import Foundation

struct SystemStats: Equatable {
    var cpu: Double              // 0...1
    var memoryUsed: UInt64
    var memoryTotal: UInt64
    var diskFree: UInt64
    var diskTotal: UInt64
    var netDown: Double          // byte/giây
    var netUp: Double
}

/// CPU, RAM, ổ đĩa, mạng của máy – chỉ chạy khi trang Thống kê đang hiện (`start` / `stop`), cập nhật mỗi giây.
/// Toàn bộ là API công khai (Mach host statistics, getifaddrs, URLResourceValues).
final class SystemStatsMonitor: ObservableObject {
    @Published private(set) var stats: SystemStats?

    private var timer: Timer?
    private var lastTicks: [UInt32]?
    private var lastNet: (counters: [String: (down: UInt32, up: UInt32)], at: Date)?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        sample()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastTicks = nil
        lastNet = nil
        stats = nil
    }

    // MARK: - Phép tính thuần (có kiểm tra ở scripts/check-stats.sh)

    /// Tỉ lệ CPU bận giữa hai lần đọc `cpu_ticks` [user, system, idle, nice].
    static func cpuUsage(from old: [UInt32], to new: [UInt32]) -> Double {
        guard old.count == 4, new.count == 4 else { return 0 }
        let delta = zip(new, old).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? (total - delta[2]) / total : 0
    }

    /// Bộ đếm byte của giao diện mạng là 32 bit và quay vòng về 0 sau 4 GB: phép trừ modulo cho đúng khi quay vòng.
    static func counterDelta(from old: UInt32, to new: UInt32) -> UInt64 {
        UInt64(new &- old)
    }

    // MARK: - Đọc hệ thống

    private func sample() {
        var cpu = 0.0
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks { cpu = Self.cpuUsage(from: last, to: ticks) }
            lastTicks = ticks
        }
        let (down, up) = networkRates()
        let memory = Self.memory()
        let disk = Self.disk()
        stats = SystemStats(cpu: cpu, memoryUsed: memory.used, memoryTotal: memory.total,
                            diskFree: disk.free, diskTotal: disk.total, netDown: down, netUp: up)
    }

    private static func cpuTicks() -> [UInt32]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
    }

    /// "Đang dùng" như Activity Monitor: active + wired + nén.
    private static func memory() -> (used: UInt64, total: UInt64) {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else { return (0, total) }
        let pages = UInt64(info.active_count) + UInt64(info.wire_count) + UInt64(info.compressor_page_count)
        return (min(pages * UInt64(vm_kernel_page_size), total), total)
    }

    private static func disk() -> (free: UInt64, total: UInt64) {
        let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        )
        return (UInt64(max(values?.volumeAvailableCapacityForImportantUsage ?? 0, 0)), UInt64(max(values?.volumeTotalCapacity ?? 0, 0)))
    }

    /// Tổng tốc độ tải xuống / lên của các giao diện Wi-Fi + Ethernet (`en*`), byte/giây.
    private func networkRates() -> (down: Double, up: Double) {
        var counters: [String: (down: UInt32, up: UInt32)] = [:]
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK), let data = entry.ifa_data else { continue }
            let name = String(cString: entry.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let link = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = (link.ifi_ibytes, link.ifi_obytes)
        }

        let now = Date()
        defer { lastNet = (counters, now) }
        guard let last = lastNet else { return (0, 0) }
        let seconds = max(now.timeIntervalSince(last.at), 0.1)
        var down: UInt64 = 0, up: UInt64 = 0
        for (name, current) in counters {
            guard let old = last.counters[name] else { continue }
            down += Self.counterDelta(from: old.down, to: current.down)
            up += Self.counterDelta(from: old.up, to: current.up)
        }
        return (Double(down) / seconds, Double(up) / seconds)
    }
}
