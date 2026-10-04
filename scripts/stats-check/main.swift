import Foundation

// CPU: 30 tick bận (user 20 + system 10) trên 100 tick → 30%
assert(abs(SystemStatsMonitor.cpuUsage(from: [0, 0, 0, 0], to: [20, 10, 70, 0]) - 0.3) < 1e-9)
// toàn rảnh → 0; không có tick mới → 0 (không chia cho 0)
assert(SystemStatsMonitor.cpuUsage(from: [5, 5, 5, 5], to: [5, 5, 105, 5]) == 0)
assert(SystemStatsMonitor.cpuUsage(from: [1, 2, 3, 4], to: [1, 2, 3, 4]) == 0)
// bộ đếm 32 bit quay vòng: 4_294_967_290 → 10 là 16 byte, không phải số âm / khổng lồ
assert(SystemStatsMonitor.counterDelta(from: 4_294_967_290, to: 10) == 16)
assert(SystemStatsMonitor.counterDelta(from: 100, to: 600) == 500)

// Đọc thật: giá trị hợp lệ
let monitor = SystemStatsMonitor()
monitor.start()
Thread.sleep(forTimeInterval: 1.2)
RunLoop.current.run(until: Date().addingTimeInterval(0.2))
let s = monitor.stats
assert(s != nil && s!.memoryTotal > 0 && s!.memoryUsed > 0 && s!.memoryUsed <= s!.memoryTotal)
assert(s!.diskTotal > 0 && s!.diskFree <= s!.diskTotal && s!.cpu >= 0 && s!.cpu <= 1)
print("OK: thống kê – CPU \(Int(s!.cpu * 100))%, RAM \(s!.memoryUsed >> 20)/\(s!.memoryTotal >> 20) MB, ↓\(Int(s!.netDown)) ↑\(Int(s!.netUp)) B/s")
