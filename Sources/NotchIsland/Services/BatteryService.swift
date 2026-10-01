import Foundation
import IOKit.ps

/// Theo dõi pin qua IOKit Power Sources – API công khai, không cần quyền gì.
final class BatteryService {
    var onChange: ((_ old: BatteryInfo?, _ new: BatteryInfo) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var last: BatteryInfo?

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue().refresh()
        }

        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            NSLog("NotchIsland: không đăng ký được thông báo nguồn điện")
            return
        }
        // Gắn vào main run loop → callback chạy trên main thread.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
        refresh()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    func refresh() {
        let current = Self.read()
        guard current != last else { return }
        let old = last
        last = current
        onChange?(old, current)
    }

    private static func adapterWatts() -> Int? {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
        return (details["Watts"] as? Int).flatMap { $0 > 0 ? $0 : nil }
    }

    static func read() -> BatteryInfo {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .unknown }

        let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue()
        let isPluggedIn = providing.map { ($0 as String) == "AC Power" } ?? true

        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery"
            else { continue }

            let current = description["Current Capacity"] as? Int ?? 0
            let maximum = description["Max Capacity"] as? Int ?? 100
            let level = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current

            let isCharging = description["Is Charging"] as? Bool ?? false
            // Đơn vị: phút; số âm / 0 nghĩa là hệ thống chưa ước tính xong.
            let minutesKey = isCharging ? "Time to Full Charge" : "Time to Empty"
            let minutes = (description[minutesKey] as? Int).flatMap { $0 > 0 ? $0 : nil }

            return BatteryInfo(
                level: min(max(level, 0), 100),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                hasBattery: true,
                minutesRemaining: minutes,
                adapterWatts: isPluggedIn ? adapterWatts() : nil
            )
        }
        // Mac để bàn (Mac mini, iMac, Studio) – không có pin.
        return BatteryInfo(level: 100, isCharging: false, isPluggedIn: isPluggedIn, hasBattery: false)
    }
}
