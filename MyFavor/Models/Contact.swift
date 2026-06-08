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
final class Contact: Syncable {
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
    /// 生日(可选,只存月日更稳定,跨时区不变)
    /// 保留 Date 是为了兼容旧数据,新代码应该用 birthdayMonthDay
    var birthday: Date?
    /// 生日月日(MM-DD 格式字符串,跨时区稳定)
    var birthdayMonthDay: String = ""
    /// 创建时间
    var createdAt: Date = Date()

    // MARK: - 云同步字段(Syncable 协议)
    var clientId: String = UUID().uuidString
    var serverId: String?
    var updatedAt: Date = Date()
    var isDirty: Bool = true
    var deletedAt: Date?

    /// 反向关联 — 该联系人的所有交易(nullify:删联系人保留交易)
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
        self.name = truncate(name, max: SyncLimits.maxNameLength)
        // pinyinInitial 应该是单字母,过长截断
        let initial = pinyinInitial.uppercased()
        self.pinyinInitial = String(initial.prefix(1))
        self.phone = truncate(phone, max: SyncLimits.maxPhoneLength)
        self.relationship = relationship
        self.avatarEmoji = avatarEmoji
        self.note = truncate(note, max: SyncLimits.maxNoteLength)
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
}
