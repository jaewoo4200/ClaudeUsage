import Foundation
import Security

enum CookieStore {
    private static let service = "app.claudeusage"
    private static let account = "claude.ai-cookie"

    @discardableResult
    static func save(_ cookieString: String) -> Bool {
        guard let data = cookieString.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var attributes = query
        attributes[kSecValueData as String] = data
        // 이 기기에서만 접근, 첫 unlock 후에만 접근 가능 — iCloud 백업/다른 기기 복원 방지
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum WidgetPositionStore {
    private static let key = "widget.position"

    static func save(_ point: NSPoint, id: String = "combined") {
        let dict = ["x": point.x, "y": point.y]
        UserDefaults.standard.set(dict, forKey: storageKey(for: id))
    }

    static func load(id: String = "combined") -> NSPoint? {
        guard let dict = UserDefaults.standard.dictionary(forKey: storageKey(for: id)),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double else { return nil }
        return NSPoint(x: x, y: y)
    }

    private static func storageKey(for id: String) -> String {
        id == "combined" ? key : "\(key).\(id)"
    }
}
