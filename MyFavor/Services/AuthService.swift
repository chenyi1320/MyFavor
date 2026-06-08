//
//  AuthService.swift
//  MyFavor
//
//  统一身份状态管理(无 Apple/Magic Link 都通过这里读写 Keychain)
//

import Foundation

@Observable
@MainActor
final class AuthService {
    /// 单例:把 @MainActor 加在 static let 上而不是 class 上
    @MainActor static let shared = AuthService()

    private init() {
        loadFromKeychain()

        // 监听 401 失效 — 保存 observer token 以便 deinit 移除
        authDidExpireObserver = NotificationCenter.default.addObserver(
            forName: .authDidExpire, object: nil, queue: .main
        ) { [weak self] _ in
            // 已在主队列,直接调用 MainActor 方法
            Task { @MainActor in
                self?.logout(notify: false)
            }
        }
    }

    deinit {
        if let token = authDidExpireObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private var authDidExpireObserver: NSObjectProtocol?

    /// 当前是否已登录
    private(set) var isLoggedIn: Bool = false
    /// 当前用户
    private(set) var currentUser: AuthUser?

    private func loadFromKeychain() {
        guard let token = KeychainHelper.shared.read(.jwtToken),
              !token.isEmpty,
              let uid = KeychainHelper.shared.read(.userId)
        else {
            isLoggedIn = false
            currentUser = nil
            return
        }
        // 检查 token 是否过期(避免拿过期 token 启动,首次请求就被踢)
        if let expiryStr = KeychainHelper.shared.read(.tokenExpiry),
           let expiry = ISO8601DateFormatter().date(from: expiryStr),
           expiry <= .now {
            // 过期,清空 Keychain
            KeychainHelper.shared.clearAll()
            isLoggedIn = false
            currentUser = nil
            return
        }
        let name  = KeychainHelper.shared.read(.userName) ?? ""
        let email = KeychainHelper.shared.read(.userEmail)
        currentUser = AuthUser(id: uid, name: name, email: email)
        isLoggedIn = true
    }

    /// 外部(如 MagicLinkService)更新 Keychain 后调用此方法刷新内存状态
    func refreshFromKeychain() {
        loadFromKeychain()
    }

    // MARK: - 登出
    func logout(notify: Bool = true) {
        KeychainHelper.shared.clearAll()
        currentUser = nil
        isLoggedIn = false
        if notify {
            NotificationCenter.default.post(name: .authDidLogout, object: nil)
        }
    }

    // MARK: - 永久删除账号
    // 失败时也清 Keychain(后端可能已删成功,客户端需要同步状态)
    func deleteAccount() async throws {
        do {
            try await APIClient.shared.requestVoid("/account", method: .DELETE)
        } catch {
            // 失败时仍清 Keychain 并提示"账号可能已删除"
            KeychainHelper.shared.clearAll()
            currentUser = nil
            isLoggedIn = false
            throw error
        }
        logout()
    }
}

// MARK: - 用户数据结构
struct AuthUser: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let email: String?
}

// MARK: - 通用 Auth 返回结构(MagicLinkService 用)
struct AuthResponse: Codable {
    let token: String
    let user: AuthUser
    let expiresAt: Date
}
