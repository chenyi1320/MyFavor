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

    // nonisolated(unsafe) static 存储:避免 deinit 访问 @MainActor 属性
    // 单例:进程生命周期内唯一,deinit 不会真正被调用
    // 这里保留 observer token 仅为静态分析,实际由 NotificationCenter 在进程退出时清理
    nonisolated(unsafe) private static var observerToken: NSObjectProtocol?

    private init() {
        loadFromKeychain()

        // 监听 401 失效
        // 用 MainActor.assumeIsolated 替代 Task { @MainActor in ... }:
        //   - addObserver 已传 queue: .main,closure 本就在主队列执行
        //   - assumeIsolated 不会创建新 Task,避免 [weak self] var 跨并发边界问题
        let token = NotificationCenter.default.addObserver(
            forName: .authDidExpire, object: nil, queue: .main
        ) { [weak self] _ in
            // 立即 unwrap 弱引用为 let,避免 self var 跨边界
            guard let service = self else { return }
            // 已经在 main queue 上,显式声明为 main actor 隔离
            MainActor.assumeIsolated {
                service.logout(notify: false)
            }
        }
        Self.observerToken = token
    }

    deinit {
        // 单例的 deinit 不会真正被调用
        // 保留 deinit 是为了 Swift 6 静态分析 + 未来扩展时不会忘记清理
        if let token = Self.observerToken {
            NotificationCenter.default.removeObserver(token)
            Self.observerToken = nil
        }
    }

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
    // 成功后调用方(ProfileView)负责调用 LocalDataCleaner 清本机数据
    func deleteAccount() async throws {
        do {
            try await APIClient.shared.requestVoid("/account", method: .DELETE)
        } catch {
            // 失败时仍清 Keychain 并提示"账号可能已删除"
            KeychainHelper.shared.clearAll()
            currentUser = nil
            isLoggedIn = false
            // 清掉该 user 的同步时间戳,避免同邮箱重新注册时漏拉
            UserDefaults.standard.removeObject(forKey: "myfavor.lastSyncUserId")
            throw error
        }
        // 成功路径:logout 会清 Keychain + 重置 in-memory 状态
        logout()
        // 清掉 lastSyncUserId(否则下次同账号登录会复用旧 since,漏拉数据)
        UserDefaults.standard.removeObject(forKey: "myfavor.lastSyncUserId")
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
