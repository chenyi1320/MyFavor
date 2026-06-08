//
//  MagicLinkService.swift
//  MyFavor
//
//  邮箱 Magic Link 登录服务
//  与 Resend / 后端 /auth/magic/* 交互
//

import Foundation
import os

@MainActor
@Observable
final class MagicLinkService {
    static let shared = MagicLinkService()
    private init() {}

    private let logger = Logger(subsystem: "com.myfavor.app", category: "MagicLink")

    var isLoading = false
    var errorMessage: String?
    /// 验证码倒计时(秒)
    var resendCountdown = 0

    // MARK: - 发送验证码邮件
    func sendCode(to email: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let body = SendRequest(email: email)
            let _: SendResponse = try await APIClient.shared.request(
                "/auth/magic/send",
                method: .POST,
                body: body,
                requiresAuth: false
            )
            startCountdown()
            // 不打印 message(含邮箱等 PII)
            logger.debug("MagicLink 验证码已发送")
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "发送失败,请稍后重试"
            return false
        }
    }

    // MARK: - 6 位验证码登录
    func verifyCode(email: String, code: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resp: AuthResponse = try await APIClient.shared.request(
                "/auth/magic/verify",
                method: .POST,
                body: VerifyByCodeRequest(email: email, code: code),
                requiresAuth: false
            )
            persistLoginAndNotify(resp)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "验证失败"
            return false
        }
    }

    // MARK: - Token 登录(深度链接回调)
    func verifyToken(_ token: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let resp: AuthResponse = try await APIClient.shared.request(
                "/auth/magic/verify",
                method: .POST,
                body: VerifyByTokenRequest(token: token),
                requiresAuth: false
            )
            persistLoginAndNotify(resp)
            return true
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "链接无效或已过期"
            return false
        }
    }

    // MARK: - 通用:保存登录态 + 通知 UI
    private func persistLoginAndNotify(_ resp: AuthResponse) {
        // 串行执行,任一失败不影响其他(都是本地存储)
        KeychainHelper.shared.save(resp.token, for: .jwtToken)
        KeychainHelper.shared.save(resp.user.id, for: .userId)
        KeychainHelper.shared.save(resp.user.name, for: .userName)
        if let email = resp.user.email {
            KeychainHelper.shared.save(email, for: .userEmail)
        }
        KeychainHelper.shared.save(
            MagicLinkService.iso8601.string(from: resp.expiresAt),
            for: .tokenExpiry
        )
        // 同步 AuthService 的内存状态
        AuthService.shared.refreshFromKeychain()
        NotificationCenter.default.post(name: .authDidLogin, object: nil)
    }

    // MARK: - 倒计时(防重复发送)
    private func startCountdown() {
        resendCountdown = 60
        // 用 Task-based 倒计时,避免 Timer + 闭包捕获 self 的 Swift 6 并发警告
        // 也不需要显式 invalidate(新 Task 自动覆盖 resendCountdown 写入)
        Task { @MainActor [weak self] in
            for i in stride(from: 59, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.resendCountdown = i
            }
        }
    }

    // 共享 ISO8601 格式化器(避免每次 new)
    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()
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
