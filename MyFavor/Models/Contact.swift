//
//  Contact.swift
//  MyFavor
//
//  Created by MyFavor on 2026/06/04.
//

import Foundation
import SwiftData

/// 联系人
@Model
final class Contact {
    /// 姓名
    var name: String = ""
    /// 拼音首字母(用于排序分组,如「张」-> "Z")
    var pinyinInitial: String = "#"
    /// 手机号(可选)
    var phone: String = ""
    /// 关系
    var relationship: ContactRelation = ContactRelation.friend
    /// 头像 emoji
    var avatarEmoji: String = "🙂"
    /// 备注
    var note: String = ""
    /// 生日(可选)
    var birthday: Date?
    /// 创建时间
    var createdAt: Date = Date()

    // MARK: - 云同步字段
    var clientId: String = UUID().uuidString
    var serverId: String?
    var updatedAt: Date = Date()
    var isDirty: Bool = true
    var deletedAt: Date?

    /// 反向关联 — 该联系人的所有交易
    @Relationship(deleteRule: .nullify, inverse: \Transaction.contact)
    var transactions: [Transaction] = []

    init(
        name: String,
        pinyinInitial: String = "#",
        phone: String = "",
        relationship: ContactRelation = .friend,
        avatarEmoji: String = "🙂",
        note: String = "",
        birthday: Date? = nil
    ) {
        self.name = name
        self.pinyinInitial = pinyinInitial.uppercased()
        self.phone = phone
        self.relationship = relationship
        self.avatarEmoji = avatarEmoji
        self.note = note
        self.birthday = birthday
        self.createdAt = .now
        self.updatedAt = .now
        self.clientId = UUID().uuidString
        self.isDirty = true
    }

    /// 收礼总额
    var totalIncoming: Decimal {
        transactions
            .filter { $0.deletedAt == nil && $0.book?.direction == .incoming }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// 送礼总额
    var totalOutgoing: Decimal {
        transactions
            .filter { $0.deletedAt == nil && $0.book?.direction == .outgoing }
            .reduce(Decimal(0)) { $0 + $1.amount }
    }

    /// 收送差(正数 = 收得多)
    var balance: Decimal { totalIncoming - totalOutgoing }

    /// 总笔数
    var transactionCount: Int { transactions.filter { $0.deletedAt == nil }.count }

    func markDirty() {
        self.updatedAt = .now
        self.isDirty = true
    }
}
