//
//  APIClient.swift
//  MyFavor
//
//  REST API 客户端 — 自动注入 JWT、处理过期、统一错误
//

import Foundation

/// 后端 API 错误(给用户看的友好文案,不含技术细节)
enum APIError: Error, LocalizedError {
    case invalidURL
    case notAuthenticated
    case tokenExpired
    case server(code: Int, message: String, hint: String? = nil)
    case decoding
    case network
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "请求地址无效"
        case .notAuthenticated:     return "请先登录"
        case .tokenExpired:         return "登录已过期,请重新登录"
        case .server(let c, let m, let hint):
            if let hint { return "\(m)\n\(hint)" }
            return "服务器错误 (\(c))"
        case .decoding:             return "数据加载失败,请稍后重试"
        case .network:              return "网络连接异常,请检查网络后重试"
        case .unknown:              return "未知错误,请稍后重试"
        }
    }
}

/// HTTP 方法
enum HTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}

actor APIClient {
    static let shared = APIClient()

    /// 后端基地址 — 切换 dev/prod
    #if DEBUG
    // 模拟器调试:用 localhost(本机后端)
    let baseURL = URL(string: "http://localhost:3000")!
    #else
    // 真机 Release:从 Info.plist 读取(避免硬编码到代码)
    // 上线前在 Xcode Info.plist 中配置 API_BASE_URL 为你的 HTTPS 域名
    let baseURL = URL(string: Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
                      ?? "https://api.example.com")!
    #endif

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    /// 设备 ID(用于后端风控,首次启动生成并存 Keychain)
    private let deviceId: String

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 60
        // 强制 HTTPS(在生产环境,防止 ATS 被 Info.plist 误关)
        #if !DEBUG
        cfg.urlCache = nil
        #endif
        self.session = URLSession(configuration: cfg)

        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = e

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = d

        // 设备 ID:首次启动生成,后续从 Keychain 取
        if let existing = KeychainHelper.shared.read(.deviceId) {
            self.deviceId = existing
        } else {
            let new = UUID().uuidString
            KeychainHelper.shared.save(new, for: .deviceId)
            self.deviceId = new
        }
    }

    /// 通用请求 — 幂等请求(GET)自动重试 2 次,其他请求不重试
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = true,
        retryOnNetworkError: Bool? = nil
    ) async throws -> T {
        let shouldRetry = retryOnNetworkError ?? (method == .GET)
        var lastError: Error?
        for attempt in 0..<(shouldRetry ? 3 : 1) {
            do {
                return try await performRequest(path, method: method, body: body, requiresAuth: requiresAuth)
            } catch APIError.network {
                lastError = APIError.network
                // 指数退避:200ms, 600ms
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(200_000_000 * (attempt + 1) * (attempt + 1)))
                    continue
                }
                throw APIError.network
            } catch {
                throw error
            }
        }
        throw lastError ?? APIError.unknown
    }

    private func performRequest<T: Decodable>(
        _ path: String,
        method: HTTPMethod,
        body: Encodable?,
        requiresAuth: Bool
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MyFavor-iOS/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")

        if requiresAuth {
            guard let token = KeychainHelper.shared.read(.jwtToken), !token.isEmpty else {
                throw APIError.notAuthenticated
            }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw APIError.network
        }

        guard let http = resp as? HTTPURLResponse else { throw APIError.unknown }

        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding
            }
        case 401:
            // 401:只发通知,不清 Keychain(交给 AuthService 统一处理避免竞态)
            await MainActor.run {
                NotificationCenter.default.post(name: .authDidExpire, object: nil)
            }
            throw APIError.tokenExpired
        default:
            // 解析后端 { error, code, hint } 结构,提供更好的错误信息
            let body = (try? decoder.decode(ErrorBody.self, from: data))
            let msg = body?.error ?? "服务器返回错误"
            throw APIError.server(code: http.statusCode, message: msg, hint: body?.hint)
        }
    }

    /// 无返回值的请求
    func requestVoid(
        _ path: String,
        method: HTTPMethod = .POST,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws {
        struct EmptyResp: Decodable {}
        let _: EmptyResp = try await request(path, method: method, body: body, requiresAuth: requiresAuth)
    }

    private struct ErrorBody: Decodable {
        let error: String
        let code: String?
        let hint: String?
    }
}

/// 用于擦除具体 Encodable 类型
struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

extension Notification.Name {
    /// JWT 失效通知
    static let authDidExpire = Notification.Name("authDidExpire")
    /// 登录成功通知
    static let authDidLogin = Notification.Name("authDidLogin")
    /// 登出通知
    static let authDidLogout = Notification.Name("authDidLogout")
}
