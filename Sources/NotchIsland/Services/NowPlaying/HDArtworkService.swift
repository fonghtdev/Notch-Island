import AppKit

/// Tìm ảnh bìa độ phân giải cao (tới 1200×1200) bằng iTunes Search API cho bài đang phát.
/// Ảnh bìa mà player gửi qua MediaRemote thường chỉ vài trăm pixel nên phóng to lên là nhoè; ảnh từ iTunes thì nét.
/// Chỉ nhận kết quả khi tên bài VÀ nghệ sĩ khớp rõ ràng (tránh gắn nhầm ảnh); không khớp thì giữ ảnh gốc.
/// Mọi hàm gọi trên main thread.
final class HDArtworkService {
    private var cache: [String: NSImage] = [:]
    private var settled = Set<String>()      // đã tra (có hoặc không có kết quả) hoặc đang tra

    static func key(title: String, artist: String) -> String { "\(artist)|\(title)" }

    func cached(_ key: String) -> NSImage? { cache[key] }

    func fetch(title: String, artist: String, completion: @escaping (NSImage) -> Void) {
        let key = Self.key(title: title, artist: artist)
        guard cache[key] == nil, !settled.contains(key) else { return }
        settled.insert(key)

        let normalizedTitle = Self.normalize(title)
        let normalizedArtist = Self.normalize(artist)
        guard normalizedTitle.count >= 2,
              var components = URLComponents(string: "https://itunes.apple.com/search")
        else { return }
        components.queryItems = [
            URLQueryItem(name: "term", value: "\(normalizedTitle) \(normalizedArtist)"),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data,
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = root["results"] as? [[String: Any]],
                  let artworkURL = Self.bestMatch(in: results, title: normalizedTitle, artist: normalizedArtist)
            else { return }
            self.download(artworkURL, key: key, completion: completion)
        }.resume()
    }

    private func download(_ url: URL, key: String, completion: @escaping (NSImage) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self?.cache[key] = image
                completion(image)
            }
        }.resume()
    }

    // MARK: - Khớp bài

    private static func bestMatch(in results: [[String: Any]], title: String, artist: String) -> URL? {
        let paddedTitle = " \(title) "
        let paddedArtist = " \(artist) "

        for result in results {
            guard let trackName = result["trackName"] as? String,
                  let artistName = result["artistName"] as? String,
                  let art100 = result["artworkUrl100"] as? String
            else { continue }

            let track = normalize(trackName)
            guard track.count >= 2 else { continue }
            let titleOK = paddedTitle.contains(" \(track) ") || " \(track) ".contains(paddedTitle)
            let artistOK = normalize(artistName).split(separator: " ").contains { word in
                word.count >= 2 && (paddedArtist.contains(" \(word) ") || paddedTitle.contains(" \(word) "))
            }
            guard titleOK, artistOK else { continue }

            let hd = art100.replacingOccurrences(of: "100x100bb", with: "1200x1200bb")
            if let url = URL(string: hd) { return url }
        }
        return nil
    }

    /// Chữ thường, bỏ dấu, bỏ nội dung trong ngoặc ("(feat. …)", "[Official]"), bỏ ký tự lạ.
    private static func normalize(_ text: String) -> String {
        var value = text.lowercased().folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        value = value.replacingOccurrences(of: "đ", with: "d")
        value = value.replacingOccurrences(of: #"[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
        value = value.replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
        return value.split(separator: " ").joined(separator: " ")
    }
}
