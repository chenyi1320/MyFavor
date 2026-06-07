//
//  AuthService.swift
//  MyFavor
//
//  统一身份状态管理(无 Apple/Magic Link 都通过这里读写 Keychain)
//

import Foundation

@MainActor
@Observable
final class AuthService {
    /// 单例 — 用 nonisolated(unsafe) 绕过 Swift 6 静态属性必须隔离的限制
    /// (init 内部全在 MainActor 上下文,所以实际安全)
    nonisolated(unsafe) static let shared = AuthService()
    
    /// 当前是否已登录
    private(set) var isLoggedIn: Bool = false
    /// 当前用户
    private(set) var currentUser: AuthUser?
    
    private init() {
        loadFromKeychain()
        
        // 监听 401 失效
        NotificationCenter.default.addObserver(
            forName: .authDidExpire, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.logout(notify: false)
            }
        }
    }
    
    private func loadFromKeychain() {
        guard let token = KeychainHelper.shared.read(.jwtToken),
              !token.isEmpty,
              let uid = KeychainHelper.shared.read(.userId)
        else {
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
    
    // MARK: - 永久删除账号(苹果审核惯例,即使用邮箱登录也最好提供)
    func deleteAccount() async throws {
        try await APIClient.shared.requestVoid("/account", method: .DELETE)
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
