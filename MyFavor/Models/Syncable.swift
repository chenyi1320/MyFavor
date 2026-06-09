//
//  Syncable.swift
//  MyFavor
//
//  云同步元数据协议 + 工具
//

import Foundation
import SwiftData

/// 同步元数据协议 — 4 个 @Model 共享的云同步字段 + 操作
///
/// 字段约束(强制):
/// - `clientId`: 客户端生成的 UUID(创建时即确定,跨设备唯一)
/// - `serverId`: 服务器返回的 ID(未同步前为 nil)
/// - `userId`: 本条记录归属的用户 ID(nil = "先逛逛" 样例数据,已登录用户永远只看到自己的)
/// - `updatedAt`: 最后修改时间(用于 LWW 冲突解决)
/// - `isDirty`: 本地有未推送的修改
/// - `deletedAt`: 软删除时间戳(用于跨端同步删除)
protocol Syncable: AnyObject {
    var clientId: String { get set }
    var serverId: String? { get set }
    var userId: String? { get set }
    var updatedAt: Date { get set }
    var isDirty: Bool { get set }
    var deletedAt: Date? { get set }
}

extension Syncable {
    /// 标记本地修改 — 调用此方法替代直接 save,确保同步状态正确
    func markDirty() {
        self.updatedAt = .now
        self.isDirty = true
    }

    /// 解析归属用户 ID
    /// - 显式传参(测试 / 批量种子)优先
    /// - 否则取 `AuthService.shared.currentUser?.id`(未登录 = nil = 样例数据归属)
    /// - 调用方必须在 MainActor(所有 UI 创建 Model 的入口都是 MainActor;SampleData 自身也是 @MainActor)
    static func resolveUserId(_ provided: String?) -> String? {
        if let provided { return provided }
        return MainActor.assumeIsolated { AuthService.shared.currentUser?.id }
    }
}

/// 同步状态机(预留,目前用 isDirty Bool 单字段即可)
enum SyncStatus: String, Codable {
    case localOnly   = "local"
    case synced      = "synced"
    case dirty       = "dirty"
    case conflicted  = "conflict"
}

/// 输入字段限制(防 DoS)
enum SyncLimits {
    static let maxNoteLength = 1000           // 备注最大字符数
    static let maxTitleLength = 200           // 标题最大字符数
    static let maxNameLength = 100            // 联系人姓名最大字符数
    static let maxPhoneLength = 30            // 手机号最大字符数
    static let maxAmount: Decimal = 999_999_999.99  // 单笔金额上限
    static let minAmount: Decimal = 0         // 单笔金额下限(允许 0)
}

/// 安全截断字符串(避免超长输入撑爆 SQLite)
func truncate(_ s: String, max: Int) -> String {
    if s.count <= max { return s }
    return String(s.prefix(max))
}

/// 金额校验(返回 nil 表示非法)
func sanitizeAmount(_ d: Decimal) -> Decimal? {
    if d.isNaN || d.isInfinite { return nil }
    if d < SyncLimits.minAmount || d > SyncLimits.maxAmount { return nil }
    return d
}
