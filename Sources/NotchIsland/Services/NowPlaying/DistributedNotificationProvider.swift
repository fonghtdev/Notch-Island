import Foundation

/// Nguồn dự phòng: chỉ Apple Music + Spotify, qua distributed notifications (API công khai).
/// Dùng khi không có adapter, hoặc Apple vá mất cách đọc MediaRemote.
final class DistributedNotificationProvider: NSObject, NowPlayingProvider {
    let name = "Music & Spotify (dự phòng)"
    var onChange: ((NowPlayingInfo?) -> Void)?
    var onFailure: (() -> Void)?

    private enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var notification: Notification.Name {
            switch self {
            case .music: return Notification.Name("com.apple.Music.playerInfo")
            case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }

        var durationKey: String { self == .music ? "Total Time" : "Duration" }
        var appName: String { self == .music ? "Music" : "Spotify" }
    }

    private let center = DistributedNotificationCenter.default()
    private var states: [Player: NowPlayingInfo] = [:]
    private var lastActive: Player?

    var diagnostics: String {
        "Chỉ nhận Music và Spotify qua thông báo hệ thống (không có YouTube). Đã nhận dữ liệu từ \(states.count) player."
    }

    func start() {
        center.addObserver(self, selector: #selector(handleMusic(_:)), name: Player.music.notification, object: nil)
        center.addObserver(self, selector: #selector(handleSpotify(_:)), name: Player.spotify.notification, object: nil)
    }

    func stop() {
        center.removeObserver(self)
    }

    deinit {
        center.removeObserver(self)
    }

    @objc private func handleMusic(_ notification: Notification) {
        update(.music, userInfo: notification.userInfo)
    }

    @objc private func handleSpotify(_ notification: Notification) {
        update(.spotify, userInfo: notification.userInfo)
    }

    private func update(_ player: Player, userInfo: [AnyHashable: Any]?) {
        let info = Self.parse(userInfo, player: player)
        states[player] = info
        if info?.isPlaying == true { lastActive = player }

        let resolved = resolve()
        DispatchQueue.main.async { [weak self] in self?.onChange?(resolved) }
    }

    /// Ưu tiên player vừa phát gần nhất → player khác đang phát → player đang tạm dừng.
    private func resolve() -> NowPlayingInfo? {
        if let lastActive, let info = states[lastActive], info.isPlaying { return info }
        if let playing = states.values.first(where: { $0.isPlaying }) { return playing }
        if let lastActive, let info = states[lastActive] { return info }
        return states.values.first
    }

    private static func parse(_ userInfo: [AnyHashable: Any]?, player: Player) -> NowPlayingInfo? {
        guard let userInfo else { return nil }
        let state = userInfo["Player State"] as? String ?? "Stopped"
        guard state != "Stopped" else { return nil }

        let durationMs = (userInfo[player.durationKey] as? NSNumber)?.doubleValue
        return NowPlayingInfo(
            bundleIdentifier: player.rawValue,
            title: userInfo["Name"] as? String ?? "Không rõ bài hát",
            artist: userInfo["Artist"] as? String ?? "",
            album: userInfo["Album"] as? String ?? "",
            isPlaying: state == "Playing",
            duration: durationMs.map { $0 / 1000 },
            accent: AppCatalog.accent(for: player.rawValue)
        )
    }

    // MARK: - Điều khiển qua AppleScript (cần quyền Automation)

    func send(_ command: MediaCommand) {
        guard let player = lastActive ?? states.keys.first else { return }
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        }
        run(player: player, action: verb)
    }

    func seek(to seconds: TimeInterval) {
        guard let player = lastActive ?? states.keys.first else { return }
        // Cả Music lẫn Spotify đều nhận `player position` tính bằng giây.
        run(player: player, action: "set player position to \(max(0, seconds))")
    }

    private func run(player: Player, action: String) {
        let script = """
        if application "\(player.appName)" is running then
            tell application "\(player.appName)" to \(action)
        end if
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            NSLog("NotchIsland: AppleScript lỗi – \(error)")
        }
    }
}
