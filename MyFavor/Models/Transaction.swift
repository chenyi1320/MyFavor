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
final class Transaction {
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

    // MARK: - 云同步字段
    var clientId: String = UUID().uuidString
    var serverId: String?
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
        contact: Contact? = nil
    ) {
        self.amount = amount
        self.giftKind = giftKind
        self.itemDescription = itemDescription
        self.date = date
        self.note = note
        self.book = book
        self.contact = contact
        self.createdAt = .now
        self.updatedAt = .now
        self.clientId = UUID().uuidString
        self.isDirty = true
    }

    func markDirty() {
        self.updatedAt = .now
        self.isDirty = true
    }
}
