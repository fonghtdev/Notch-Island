import Foundation
import SQLite3

/// Đọc thông báo mới từ cơ sở dữ liệu của Trung tâm thông báo macOS (THỬ NGHIỆM).
///
/// macOS không có API công khai cho app khác đọc thông báo. Cách duy nhất là mở file SQLite của `usernoted`,
/// việc này cần quyền **Toàn bộ ổ đĩa** (Full Disk Access). Định dạng file là nội bộ của Apple nên có thể đổi
/// giữa các bản macOS – khi không đọc được thì bỏ qua lặng lẽ.
/// Chỉ thăm dò khi người dùng bật; lần đầu chỉ lấy mốc, không đẩy thông báo cũ.
final class NotificationReader {
    var onChange: (([NotificationItem]) -> Void)?

    private let queue = DispatchQueue(label: "notchisland.notifications", qos: .utility)
    private var timer: Timer?
    private var items: [NotificationItem] = []
    private var lastID: Int64?
    private var isFetching = false
    private var loggedError = false

    private static let maxItems = 5
    private static let maxAge: TimeInterval = 15 * 60

    func setEnabled(_ enabled: Bool) {
        if enabled {
            guard timer == nil else { return }
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            poll()
        } else {
            timer?.invalidate()
            timer = nil
            lastID = nil
            if !items.isEmpty {
                items = []
                onChange?([])
            }
        }
    }

    func dismiss(_ id: Int64) {
        items.removeAll { $0.id == id }
        onChange?(items)
    }

    // MARK: - Thăm dò

    private func poll() {
        guard !isFetching else { return }
        isFetching = true
        let baseline = lastID
        queue.async { [weak self] in
            let result = Self.fetch(after: baseline)
            DispatchQueue.main.async { self?.apply(result) }
        }
    }

    private struct FetchResult {
        var fresh: [NotificationItem] = []
        var maxID: Int64?
        var error: String?
    }

    private func apply(_ result: FetchResult) {
        isFetching = false
        if let error = result.error {
            if !loggedError { NSLog("NotchIsland: không đọc được thông báo – \(error)") }
            loggedError = true
            return
        }
        loggedError = false
        if let maxID = result.maxID { lastID = max(lastID ?? maxID, maxID) }

        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        var merged = (result.fresh + items).filter { $0.date > cutoff }
        merged.sort { $0.id > $1.id }
        merged = Array(merged.prefix(Self.maxItems))
        guard merged != items else { return }
        items = merged
        onChange?(items)
    }

    // MARK: - SQLite

    private static func databaseURL() -> URL? {
        var candidates = [
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db"),
        ]
        var buffer = [CChar](repeating: 0, count: 1024)
        if confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 {
            candidates.append(
                URL(fileURLWithPath: String(cString: buffer)).appendingPathComponent("com.apple.notificationcenter/db2/db")
            )
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Có đọc được DB thông báo không (chính là phép thử quyền Toàn bộ ổ đĩa; lần thử này cũng khiến macOS liệt kê app trong danh sách).
    static var hasAccess: Bool {
        guard let url = databaseURL() else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 1)) != nil
    }

    private static func fetch(after baseline: Int64?) -> FetchResult {
        guard let source = databaseURL() else { return FetchResult(error: "không thấy cơ sở dữ liệu thông báo") }

        // Sao chép db + wal + shm sang thư mục tạm rồi mở bản sao: tránh tranh chấp khoá với usernoted.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("notchisland-nc", isDirectory: true)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for suffix in ["", "-wal", "-shm"] {
            let from = URL(fileURLWithPath: source.path + suffix)
            let to = directory.appendingPathComponent("db" + suffix)
            try? fileManager.removeItem(at: to)
            if fileManager.fileExists(atPath: from.path) {
                do { try fileManager.copyItem(at: from, to: to) } catch {
                    return FetchResult(error: "không đọc được (cần quyền Toàn bộ ổ đĩa): \(error.localizedDescription)")
                }
            }
        }

        var db: OpaquePointer?
        let path = directory.appendingPathComponent("db").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return FetchResult(error: "không mở được cơ sở dữ liệu")
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT r.rec_id, a.identifier, r.data
        FROM record r JOIN app a ON a.app_id = r.app_id
        ORDER BY r.rec_id DESC LIMIT 25
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return FetchResult(error: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var rows: [NotificationItem] = []
        var maxID: Int64?
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            maxID = max(maxID ?? id, id)

            // Lần đầu (chưa có mốc) chỉ ghi nhận mốc.
            guard let baseline, id > baseline else { continue }

            let bundle = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let count = Int(sqlite3_column_bytes(statement, 2))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 2) else { continue }
            let data = Data(bytes: bytes, count: count)

            if let item = parse(id: id, bundle: bundle, data: data) { rows.append(item) }
        }
        return FetchResult(fresh: rows, maxID: maxID, error: nil)
    }

    private static func parse(id: Int64, bundle: String, data: Data) -> NotificationItem? {
        guard bundle != Bundle.main.bundleIdentifier,
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let request = plist["req"] as? [String: Any]
        else { return nil }

        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        guard !(title.isEmpty && body.isEmpty) else { return nil }

        let date = (plist["date"] as? Double).map { Date(timeIntervalSinceReferenceDate: $0) } ?? Date()
        return NotificationItem(id: id, bundleIdentifier: bundle, title: title, subtitle: subtitle, body: body, date: date)
    }
}
