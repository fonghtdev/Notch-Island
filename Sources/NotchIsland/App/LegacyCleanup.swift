import Foundation
import Security

/// Dọn dữ liệu của tính năng Face ID / PAM đã gỡ (v0.8–v0.9): mẫu khuôn mặt, khoá trong Keychain, socket, cài đặt.
/// Chạy mỗi lần khởi động; không còn gì để xoá thì không làm gì.
enum LegacyCleanup {
    static func run() {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchIsland", isDirectory: true)
        for name in ["face.bin", "face.plist", "pam-enroll.txt", "pam.sock", "ArcFaceMobile.mlmodelc"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }

        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "dev.fong.notchisland.face",
        ] as CFDictionary)
        SecItemDelete([
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data("dev.fong.notchisland.pam.signing".utf8),
        ] as CFDictionary)

        let defaults = UserDefaults.standard
        for key in ["faceUnlockEnabled", "faceTolerance", "faceThreshold", "pamEnabled", "faceFailures", "faceLockedUntil"] {
            defaults.removeObject(forKey: key)
        }
    }
}
