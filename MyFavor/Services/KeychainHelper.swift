//
//  KeychainHelper.swift
//  MyFavor
//
//  Keychain 封装 — 用于安全存储 JWT、用户标识等敏感信息
//  注意:jwtToken/用户信息显式关闭 iCloud 同步,避免跨设备共享 JWT
//

import Foundation
import Security
import os

/// final class + 串行 DispatchQueue:防止 save/delete 并发竞态(原 delete+add 非原子)
/// 用 final class 而非 actor,避免全部调用方都得 await
final class KeychainHelper: @unchecked Sendable {
    static let shared = KeychainHelper()
    private init() {}

    private let service = "com.myfavor.app"
    private let queue = DispatchQueue(label: "com.myfavor.keychain", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.myfavor.app", category: "Keychain")

    enum Key: String {
        case jwtToken    = "jwt_token"
        case userId      = "user_id"
        case userEmail   = "user_email"
        case userName    = "user_name"
        case tokenExpiry = "token_expiry"
        case deviceId    = "device_id"   // 设备唯一标识(用于后端风控)
    }

    /// 保存 — 优先用 SecItemUpdate 保持原子性,失败 fallback 到 add
    @discardableResult
    func save(_ value: String, for key: Key) -> Bool {
        queue.sync {
            guard let data = value.data(using: .utf8) else {
                logger.error("Keychain save: 编码失败")
                return false
            }

            let baseQuery: [String: Any] = [
                kSecClass as String:           kSecClassGenericPassword,
                kSecAttrService as String:     service,
                kSecAttrAccount as String:     key.rawValue,
            ]

            // 1. 先尝试 SecItemUpdate(原子,避免 delete+add 竞态)
            let updateAttrs: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any, // 显式关闭 iCloud 同步
            ]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus == errSecSuccess {
                return true
            }
            if updateStatus != errSecItemNotFound {
                logger.error("Keychain update failed: \(updateStatus, privacy: .public)")
            }

            // 2. item 不存在 → add
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                return true
            }
            logger.error("Keychain add failed: \(addStatus, privacy: .public)")
            return false
        }
    }

    /// 读取
    func read(_ key: Key) -> String? {
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String:           kSecClassGenericPassword,
                kSecAttrService as String:     service,
                kSecAttrAccount as String:     key.rawValue,
                kSecMatchLimit as String:      kSecMatchLimitOne,
                kSecReturnData as String:      true,
            ]
            var item: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status != errSecSuccess && status != errSecItemNotFound {
                logger.error("Keychain read failed: \(status, privacy: .public)")
            }
            guard status == errSecSuccess,
                  let data = item as? Data,
                  let str = String(data: data, encoding: .utf8) else { return nil }
            return str
        }
    }

    /// 删除
    @discardableResult
    func delete(_ key: Key) -> Bool {
        queue.sync {
            let query: [String: Any] = [
                kSecClass as String:        kSecClassGenericPassword,
                kSecAttrService as String:  service,
                kSecAttrAccount as String:  key.rawValue,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound {
                return true
            }
            logger.error("Keychain delete failed: \(status, privacy: .public)")
            return false
        }
    }

    /// 清空所有
    func clearAll() {
        queue.sync {
            var hadError = false
            for key in Key.allKeys {
                let query: [String: Any] = [
                    kSecClass as String:        kSecClassGenericPassword,
                    kSecAttrService as String:  service,
                    kSecAttrAccount as String:  key.rawValue,
                ]
                let status = SecItemDelete(query as CFDictionary)
                if status != errSecSuccess && status != errSecItemNotFound {
                    hadError = true
                }
            }
            if hadError {
                logger.error("Keychain clearAll: 部分删除失败")
            }
        }
    }
}

extension KeychainHelper.Key {
    static var allKeys: [KeychainHelper.Key] {
        [.jwtToken, .userId, .userEmail, .userName, .tokenExpiry, .deviceId]
    }
}
