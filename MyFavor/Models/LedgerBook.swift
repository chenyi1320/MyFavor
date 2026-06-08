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
final class LedgerBook {
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

    // MARK: - 云同步字段
    /// 客户端 UUID(创建时即生成,跨设备唯一)
    var clientId: String = UUID().uuidString
    /// 服务器 ID(同步成功后由服务器返回)
    var serverId: String?
    /// 最后修改时间(用于增量同步)
    var updatedAt: Date = Date()
    /// 本地是否有未推送的修改
    var isDirty: Bool = true
    /// 软删除标记(同步删除用)
    var deletedAt: Date?

    /// 反向关联 — 来往记录
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
        self.title = title
        self.category = category
        self.direction = direction
        self.eventDate = eventDate
        self.note = note
        self.coverColorHex = coverColorHex
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

    /// 标记本地修改 — 调用此方法替代直接 save
    func markDirty() {
        self.updatedAt = .now
        self.isDirty = true
    }
}
