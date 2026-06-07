//
//  APIClient.swift
//  MyFavor
//
//  REST API 客户端 — 自动注入 JWT、处理过期、统一错误
//

import Foundation

/// 后端 API 错误
enum APIError: Error, LocalizedError {
    case invalidURL
    case notAuthenticated
    case tokenExpired
    case server(code: Int, message: String)
    case decoding(Error)
    case network(Error)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "URL 无效"
        case .notAuthenticated:     return "未登录"
        case .tokenExpired:         return "登录已过期,请重新登录"
        case .server(let c, let m): return "服务器错误 (\(c)):\(m)"
        case .decoding(let e):      return "数据解析失败:\(e.localizedDescription)"
        case .network(let e):       return "网络错误:\(e.localizedDescription)"
        case .unknown:              return "未知错误"
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
    let baseURL = URL(string: "http://39.105.106.86:3000")!
    #else
    // 生产:阿里云 ECS 部署
    let baseURL = URL(string: "http://39.105.106.86:3000")!
    #endif
    
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        cfg.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: cfg)
        
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = e
        
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        d.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = d
    }
    
    /// 通用请求
    func request<T: Decodable>(
        _ path: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("MyFavor-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
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
            throw APIError.network(error)
        }
        
        guard let http = resp as? HTTPURLResponse else { throw APIError.unknown }
        
        switch http.statusCode {
        case 200..<300:
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        case 401:
            // JWT 过期 — 清空 Keychain,通知 UI 跳登录
            KeychainHelper.shared.clearAll()
            await MainActor.run {
                NotificationCenter.default.post(name: .authDidExpire, object: nil)
            }
            throw APIError.tokenExpired
        default:
            let msg = (try? decoder.decode(ErrorBody.self, from: data))?.error
                       ?? String(data: data, encoding: .utf8)
                       ?? "Unknown"
            throw APIError.server(code: http.statusCode, message: msg)
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
