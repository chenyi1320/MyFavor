//
//  KeychainHelper.swift
//  MyFavor
//
//  Keychain 封装 — 用于安全存储 JWT、用户标识等敏感信息
//  特点:卸载重装不会清空(走 iCloud Keychain 还能跨设备)
//

import Foundation
import Security

final class KeychainHelper {
    static let shared = KeychainHelper()
    private init() {}
    
    private let service = "com.myfavor.app"
    
    enum Key: String {
        case jwtToken    = "jwt_token"
        case userId      = "user_id"
        case userEmail   = "user_email"
        case userName    = "user_name"
        case tokenExpiry = "token_expiry"
    }
    
    @discardableResult
    func save(_ value: String, for key: Key) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     key.rawValue,
            kSecValueData as String:       data,
            kSecAttrAccessible as String:  kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary) // 先删
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func read(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     key.rawValue,
            kSecMatchLimit as String:      kSecMatchLimitOne,
            kSecReturnData as String:      true
        ]
        var item: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &item)
        guard let data = item as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }
    
    @discardableResult
    func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  key.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    func clearAll() {
        Key.allKeys.forEach { delete($0) }
    }
}

extension KeychainHelper.Key {
    static var allKeys: [KeychainHelper.Key] {
        [.jwtToken, .userId, .userEmail, .userName, .tokenExpiry]
    }
}
