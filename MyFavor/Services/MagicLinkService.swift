//
//  MagicLinkService.swift
//  MyFavor
//
//  邮箱 Magic Link 登录服务
//  与 Resend / 后端 /auth/magic/* 交互
//

import Foundation

@MainActor
@Observable
final class MagicLinkService {
    static let shared = MagicLinkService()
    private init() {}
    
    var isLoading = false
    var errorMessage: String?
    /// 验证码倒计时(秒)
    var resendCountdown = 0
    private var timer: Timer?
    
    // MARK: - 发送验证码邮件
    func sendCode(to email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let body = SendRequest(email: email)
            let resp: SendResponse = try await APIClient.shared.request(
                "/auth/magic/send",
                method: .POST,
                body: body,
                requiresAuth: false
            )
            startCountdown()
            print("[MagicLink] sent:", resp.message ?? "ok")
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
    
    // MARK: - 用 6 位验证码登录
    func verifyCode(email: String, code: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let body = VerifyByCodeRequest(email: email, code: code)
            let resp: AuthResponse = try await APIClient.shared.request(
                "/auth/magic/verify",
                method: .POST,
                body: body,
                requiresAuth: false
            )
            persistLoginAndNotify(resp)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
    
    // MARK: - 用邮件链接里的 token 登录(深度链接回调)
    func verifyToken(_ token: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        do {
            let body = VerifyByTokenRequest(token: token)
            let resp: AuthResponse = try await APIClient.shared.request(
                "/auth/magic/verify",
                method: .POST,
                body: body,
                requiresAuth: false
            )
            persistLoginAndNotify(resp)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
    
    // MARK: - 通用:保存登录态 + 通知 UI
    private func persistLoginAndNotify(_ resp: AuthResponse) {
        KeychainHelper.shared.save(resp.token, for: .jwtToken)
        KeychainHelper.shared.save(resp.user.id, for: .userId)
        KeychainHelper.shared.save(resp.user.name, for: .userName)
        if let email = resp.user.email {
            KeychainHelper.shared.save(email, for: .userEmail)
        }
        KeychainHelper.shared.save(
            ISO8601DateFormatter().string(from: resp.expiresAt),
            for: .tokenExpiry
        )
        // 同步 AuthService 的内存状态
        AuthService.shared.refreshFromKeychain()
        NotificationCenter.default.post(name: .authDidLogin, object: nil)
    }
    
    // MARK: - 倒计时(防重复发送)
    private func startCountdown() {
        resendCountdown = 60
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            // 关键:在 Task 外先解包 self(避免 Swift 6 并发捕获警告)
            guard let self else { t.invalidate(); return }
            // 现在 self 是局部常量,Task 安全捕获
            Task { @MainActor in
                self.resendCountdown -= 1
                if self.resendCountdown <= 0 {
                    t.invalidate()
                }
            }
        }
    }
}

// MARK: - Request / Response DTOs

private struct SendRequest: Codable {
    let email: String
}

private struct SendResponse: Codable {
    let ok: Bool
    let expiresIn: Int?
    let message: String?
}

private struct VerifyByCodeRequest: Codable {
    let email: String
    let code: String
}

private struct VerifyByTokenRequest: Codable {
    let token: String
}
