import Foundation
import ObjectiveC
import SwiftUI

/// Đọc hẹn giờ / bấm giờ của app **Đồng hồ** của macOS (THỬ NGHIỆM).
///
/// macOS không có API công khai cho việc này. App Đồng hồ dùng framework riêng tư `MobileTimer`
/// (`MTTimerManager`, `MTStopwatchManager`…); ở đây gọi chúng qua ObjC runtime, mọi bước đều kiểm tra
/// `responds(to:)` nên sai tên hàm chỉ làm hoạt động không hiện chứ không làm app lỗi.
/// Nếu không thấy gì: menu → "Chẩn đoán Đồng hồ…" liệt kê lớp / hàm thật của máy bạn để chỉnh lại cho khớp.
final class SystemClockMonitor {
    var onChange: (([LiveActivity]) -> Void)?

    private static let frameworkPaths = [
        "/System/iOSSupport/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer",
        "/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer",
    ]
    static let clockBundleID = "com.apple.clock"

    private let queue = DispatchQueue(label: "notchisland.clock", qos: .utility)
    private var source: DispatchSourceTimer?
    private var loaded = false
    private var loadLog: [String] = []
    private var timerManager: AnyObject?
    private var stopwatchManager: AnyObject?
    private var last: [LiveActivity] = []

    func start() {
        guard source == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 1.5)
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        source = timer
    }

    func stop() {
        source?.cancel()
        source = nil
        queue.async { [weak self] in
            guard let self, !self.last.isEmpty else { return }
            self.last = []
            DispatchQueue.main.async { self.onChange?([]) }
        }
    }

    // MARK: - Nạp framework

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        for path in Self.frameworkPaths {
            if dlopen(path, RTLD_NOW) != nil {
                loadLog.append("dlopen OK: \(path)")
            } else if let error = dlerror() {
                loadLog.append("dlopen lỗi: \(String(cString: error))")
            }
        }
        timerManager = Self.makeManager(className: "MTTimerManager", log: &loadLog)
        stopwatchManager = Self.makeManager(className: "MTStopwatchManager", log: &loadLog)
    }

    private static func makeManager(className: String, log: inout [String]) -> AnyObject? {
        guard let cls = NSClassFromString(className) as? NSObject.Type else {
            log.append("\(className): không có lớp")
            return nil
        }
        for selectorName in ["sharedManager", "sharedInstance", "defaultManager"] {
            let selector = NSSelectorFromString(selectorName)
            if (cls as AnyObject).responds(to: selector),
               let object = (cls as AnyObject).perform(selector)?.takeUnretainedValue() {
                log.append("\(className): dùng +\(selectorName)")
                return object
            }
        }
        log.append("\(className): dùng init()")
        return cls.init()
    }

    // MARK: - Đọc dữ liệu

    private func poll() {
        loadIfNeeded()
        var list: [LiveActivity] = []

        for (index, timer) in Self.objects(from: timerManager, selectors: ["timers", "currentTimer", "nextTimer"]).enumerated() {
            if let activity = Self.timerActivity(timer, index: index) { list.append(activity) }
        }
        for (index, watch) in Self.objects(from: stopwatchManager, selectors: ["currentStopwatch", "stopwatch", "stopwatches"]).enumerated() {
            if let activity = Self.stopwatchActivity(watch, index: index) { list.append(activity) }
        }

        guard list != last else { return }
        last = list
        DispatchQueue.main.async { [weak self] in self?.onChange?(list) }
    }

    /// Gọi lần lượt các hàm trả về đối tượng / mảng (có thể bọc trong "future"), gom thành danh sách.
    private static func objects(from manager: AnyObject?, selectors: [String]) -> [AnyObject] {
        guard let manager else { return [] }
        for name in selectors {
            let selector = NSSelectorFromString(name)
            guard manager.responds(to: selector),
                  let raw = manager.perform(selector)?.takeUnretainedValue(),
                  let value = resolve(raw)
            else { continue }
            if let array = value as? [AnyObject], !array.isEmpty { return array }
            if !(value is NSArray) { return [value] }
        }
        return []
    }

    /// Một số hàm trả về "future" (`NAFuture`): lấy kết quả với hạn 0,4 giây.
    private static func resolve(_ object: AnyObject) -> AnyObject? {
        let selector = NSSelectorFromString("resultWithTimeout:error:")
        guard object.responds(to: selector), let nsObject = object as? NSObject else { return object }
        let imp = nsObject.method(for: selector)
        typealias Function = @convention(c) (AnyObject, Selector, Double, UnsafeMutablePointer<AnyObject?>?) -> Unmanaged<AnyObject>?
        let function = unsafeBitCast(imp, to: Function.self)
        return function(object, selector, 0.4, nil)?.takeUnretainedValue()
    }

    private static func number(_ object: AnyObject, _ key: String) -> Double? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return ((object as? NSObject)?.value(forKey: key) as? NSNumber)?.doubleValue
    }

    private static func date(_ object: AnyObject, _ key: String) -> Date? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return (object as? NSObject)?.value(forKey: key) as? Date
    }

    private static func string(_ object: AnyObject, _ key: String) -> String? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return (object as? NSObject)?.value(forKey: key) as? String
    }

    /// `MTTimerState`: 1 dừng, 2 đang chạy, 3 tạm dừng, 4 đang reo (theo thông tin đã biết – kiểm tra bằng chẩn đoán).
    private static func timerActivity(_ timer: AnyObject, index: Int) -> LiveActivity? {
        let state = Int(number(timer, "state") ?? 0)
        guard state == 2 || state == 3 else { return nil }

        let remaining = number(timer, "remainingTime")
        let title = string(timer, "title").flatMap { $0.isEmpty ? nil : $0 } ?? "Hẹn giờ"
        let endsAt = date(timer, "fireDate") ?? remaining.map { Date().addingTimeInterval($0) }
        guard let endsAt else { return nil }

        let paused = state == 3
        return LiveActivity(
            id: "clock.timer.\(index)", kind: .timer, title: "Hẹn giờ",
            subtitle: paused ? "\(title) · đang tạm dừng · Đồng hồ" : "\(title) · Đồng hồ",
            symbolName: "timer", tint: .orange, bundleIdentifier: clockBundleID,
            startedAt: nil, endsAt: paused ? nil : endsAt, pausedRemaining: paused ? (remaining ?? 0) : nil
        )
    }

    private static func stopwatchActivity(_ watch: AnyObject, index: Int) -> LiveActivity? {
        let state = Int(number(watch, "state") ?? -1)
        let start = date(watch, "startDate")
        let elapsed = number(watch, "currentInterval") ?? number(watch, "elapsedTime")

        let paused = state == 3
        let running = state == 2 || (state == -1 && start != nil)
        guard running || paused else { return nil }

        var activity = LiveActivity(
            id: "clock.stopwatch.\(index)", kind: .stopwatch, title: "Bấm giờ", subtitle: "Đồng hồ",
            symbolName: "stopwatch", tint: .yellow, bundleIdentifier: clockBundleID,
            startedAt: nil, endsAt: nil, pausedRemaining: nil
        )
        if paused {
            activity.pausedElapsed = elapsed ?? 0
        } else if let start {
            activity.startedAt = start
        } else if let elapsed {
            activity.startedAt = Date().addingTimeInterval(-elapsed)
        } else {
            return nil
        }
        return activity
    }

    // MARK: - Chẩn đoán

    func diagnose(completion: @escaping (String) -> Void) {
        queue.async { [self] in
            loadIfNeeded()
            var lines = ["== Nạp framework =="] + loadLog

            func methods(of cls: AnyClass, meta: Bool) -> [String] {
                let target: AnyClass? = meta ? object_getClass(cls) : cls
                guard let target else { return [] }
                var count: UInt32 = 0
                guard let list = class_copyMethodList(target, &count) else { return [] }
                defer { free(list) }
                return (0..<Int(count)).map { NSStringFromSelector(method_getName(list[$0])) }.sorted()
            }

            var classCount: UInt32 = 0
            var matched: [String] = []
            if let all = objc_copyClassList(&classCount) {
                for i in 0..<Int(classCount) {
                    let name = NSStringFromClass(all[i])
                    if name.hasPrefix("MTTimer") || name.hasPrefix("MTStopwatch") || name.hasPrefix("MTAlarm") { matched.append(name) }
                }
            }
            lines.append("\n== Lớp MobileTimer tìm thấy (\(matched.count)) ==")
            lines.append(matched.sorted().joined(separator: ", "))

            for name in ["MTTimerManager", "MTStopwatchManager", "MTTimer", "MTStopwatch"] {
                guard let cls = NSClassFromString(name) else { lines.append("\n\(name): KHÔNG có"); continue }
                lines.append("\n== \(name) ==")
                lines.append("Hàm lớp: " + methods(of: cls, meta: true).joined(separator: " "))
                lines.append("Hàm đối tượng: " + methods(of: cls, meta: false).joined(separator: " "))
            }

            lines.append("\n== Giá trị đọc được ==")
            let timers = Self.objects(from: timerManager, selectors: ["timers", "currentTimer", "nextTimer"])
            lines.append("Hẹn giờ: \(timers.count)")
            for timer in timers {
                let keys = ["state", "remainingTime", "duration", "fireDate", "title"]
                lines.append(keys.map { key -> String in
                    if let n = Self.number(timer, key) { return "\(key)=\(n)" }
                    if let d = Self.date(timer, key) { return "\(key)=\(d)" }
                    if let s = Self.string(timer, key) { return "\(key)=\(s)" }
                    return "\(key)=∅"
                }.joined(separator: "  "))
            }
            let watches = Self.objects(from: stopwatchManager, selectors: ["currentStopwatch", "stopwatch", "stopwatches"])
            lines.append("Bấm giờ: \(watches.count)")
            for watch in watches {
                let keys = ["state", "startDate", "currentInterval", "elapsedTime"]
                lines.append(keys.map { key -> String in
                    if let n = Self.number(watch, key) { return "\(key)=\(n)" }
                    if let d = Self.date(watch, key) { return "\(key)=\(d)" }
                    return "\(key)=∅"
                }.joined(separator: "  "))
            }
            let text = lines.joined(separator: "\n")
            DispatchQueue.main.async { completion(text) }
        }
    }
}
