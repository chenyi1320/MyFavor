//
//  LedgerBook.swift
//  MyFavor
//
//  Created by MyFavor on 2026/06/04.
//

import Foundation
import SwiftData

/// 礼簿 — 一个事件(如「我结婚」「女儿周岁」)对应一本礼簿,
/// 里面记录该事件的所有来往。
@Model
final class LedgerBook: Syncable {
    /// 礼簿标题(如「老爸六十大寿」)
    var title: String = ""
    /// 事件类型
    var category: EventCategory = EventCategory.other
    /// 方向:收礼簿 or 送礼簿
    var direction: Direction = Direction.incoming
    /// 事件日期
    var eventDate: Date = Date()
    /// 备注
    var note: String = ""
    /// 封面颜色(hex 字符串)
    var coverColorHex: String = "#2C5F4F"
    /// 是否已封账(封账后不可编辑)
    var isClosed: Bool = false
    /// 创建时间
    var createdAt: Date = Date()

    // MARK: - 云同步字段(Syncable 协议)
    var clientId: String = UUID().uuidString
    var serverId: String?
    var updatedAt: Date = Date()
    var isDirty: Bool = true
    var deletedAt: Date?

    /// 反向关联 — 来往记录
    /// 注意:SwiftData @Relationship 的 cascade 与业务"软删除"语义有冲突
    /// 调用方需要先软删所有 transactions(标记 deletedAt),再调硬删,避免丢未同步数据
    @Relationship(deleteRule: .cascade, inverse: \Transaction.book)
    var transactions: [Transaction] = []

    init(
        title: String,
        category: EventCategory = .other,
        direction: Direction = .incoming,
        eventDate: Date = .now,
        note: String = "",
        coverColorHex: String = "#2C5F4F",
        isClosed: Bool = false
    ) {
        self.title = truncate(title, max: SyncLimits.maxTitleLength)
        self.category = category
        self.direction = direction
        self.eventDate = eventDate
        self.note = truncate(note, max: SyncLimits.maxNoteLength)
        // 校验 hex 颜色格式(6 位),非法用默认
        self.coverColorHex = isValidHex(coverColorHex) ? coverColorHex : "#2C5F4F"
        self.isClosed = isClosed
        self.createdAt = .now
        self.updatedAt = .now
        self.clientId = UUID().uuidString
        self.isDirty = true
    }

    /// 汇总金额
    var totalAmount: Decimal {
        transactions.filter { $0.deletedAt == nil }
                    .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// 笔数
    var count: Int { transactions.filter { $0.deletedAt == nil }.count }
}

// MARK: - Hex 颜色校验
private let hexPattern = "^#[0-9A-Fa-f]{6}$"
func isValidHex(_ s: String) -> Bool {
    s.range(of: hexPattern, options: .regularExpression) != nil
}
