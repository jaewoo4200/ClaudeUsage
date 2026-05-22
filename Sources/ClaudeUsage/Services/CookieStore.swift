import Foundation
import Security

enum CookieStore {
    private static let service = "com.jaewoolee.ClaudeUsage"
    private static let account = "claude.ai-cookie"

    static func save(_ cookieString: String) {
        guard let data = cookieString.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
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

    static func save(_ point: NSPoint) {
        let dict = ["x": point.x, "y": point.y]
        UserDefaults.standard.set(dict, forKey: key)
    }

    static func load() -> NSPoint? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double else { return nil }
        return NSPoint(x: x, y: y)
    }
}
