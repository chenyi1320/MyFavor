//
//  Transaction.swift
//  MyFavor
//
//  Created by MyFavor on 2026/06/04.
//

import Foundation
import SwiftData

/// 单条礼尚往来记录(收/送礼)
@Model
final class Transaction: Syncable {
    /// 金额(支持小数)
    var amount: Decimal = Decimal(0)
    /// 礼品类型(礼金 / 礼品)
    var giftKind: GiftKind = GiftKind.cash
    /// 实物礼品描述(如 GiftKind == .item 时使用)
    var itemDescription: String = ""
    /// 发生日期
    var date: Date = Date()
    /// 备注
    var note: String = ""
    /// 关联礼簿
    var book: LedgerBook?
    /// 关联联系人
    var contact: Contact?
    /// 创建时间
    var createdAt: Date = Date()

    // MARK: - 云同步字段(Syncable 协议)
    var clientId: String = UUID().uuidString
    var serverId: String?
    var userId: String?
    var updatedAt: Date = Date()
    var isDirty: Bool = true
    var deletedAt: Date?

    init(
        amount: Decimal = 0,
        giftKind: GiftKind = .cash,
        itemDescription: String = "",
        date: Date = .now,
        note: String = "",
        book: LedgerBook? = nil,
        contact: Contact? = nil,
        userId: String? = nil
    ) {
        // 金额校验:非法时 fallback 为 0(避免负数/NaN/超大)
        self.amount = sanitizeAmount(amount) ?? 0
        self.giftKind = giftKind
        self.itemDescription = truncate(itemDescription, max: SyncLimits.maxNoteLength)
        self.date = date
        self.note = truncate(note, max: SyncLimits.maxNoteLength)
        self.book = book
        self.contact = contact
        self.createdAt = .now
        self.updatedAt = .now
        self.clientId = UUID().uuidString
        self.userId = Self.resolveUserId(userId)
        self.isDirty = true
    }
}
