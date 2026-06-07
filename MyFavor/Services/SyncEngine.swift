//
//  SyncEngine.swift
//  MyFavor
//
//  数据同步引擎 — Last-Write-Wins + 增量同步
//  策略:
//   1. PUSH:本地 isDirty=true 的所有记录 → POST /sync/push
//   2. PULL:服务器自 lastSyncAt 起的所有变更 → GET /sync/pull?since=xx
//   3. 冲突:服务器 updatedAt > 本地 updatedAt → 服务器赢(覆盖本地)
//   4. 删除:软删除(deletedAt 时间戳)
//

import Foundation
import SwiftData

@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()
    
    var isSyncing = false
    var lastSyncDate: Date?
    var lastSyncError: String?
    
    private let lastSyncKey = "myfavor.lastSyncAt"
    
    private init() {
        if let ts = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = ts
        }
    }
    
    /// 全量同步入口(推+拉)
    @MainActor
    func syncNow(context: ModelContext) async {
        guard AuthService.shared.isLoggedIn else {
            lastSyncError = "未登录,无法同步"
            return
        }
        guard !isSyncing else { return }
        
        isSyncing = true
        lastSyncError = nil
        defer { isSyncing = false }
        
        do {
            try await pushLocalChanges(context: context)
            try await pullRemoteChanges(context: context)
            lastSyncDate = .now
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
        } catch {
            lastSyncError = error.localizedDescription
            print("[Sync] failed:", error)
        }
    }
    
    // MARK: - PUSH
    private func pushLocalChanges(context: ModelContext) async throws {
        // 收集所有 dirty 的实体
        let dirtyBooks = try context.fetch(FetchDescriptor<LedgerBook>(
            predicate: #Predicate { $0.isDirty == true }
        ))
        let dirtyContacts = try context.fetch(FetchDescriptor<Contact>(
            predicate: #Predicate { $0.isDirty == true }
        ))
        let dirtyTxs = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.isDirty == true }
        ))
        let dirtyReminders = try context.fetch(FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.isDirty == true }
        ))
        
        guard !dirtyBooks.isEmpty || !dirtyContacts.isEmpty
              || !dirtyTxs.isEmpty || !dirtyReminders.isEmpty else {
            print("[Sync] nothing to push")
            return
        }
        
        let payload = PushPayload(
            ledgerBooks:  dirtyBooks.map(LedgerBookDTO.init),
            contacts:     dirtyContacts.map(ContactDTO.init),
            transactions: dirtyTxs.map(TransactionDTO.init),
            reminders:    dirtyReminders.map(ReminderDTO.init)
        )
        
        let resp: PushResponse = try await APIClient.shared.request(
            "/sync/push", method: .POST, body: payload
        )
        
        // 把 server 返回的 serverId 回写,并清掉 isDirty
        for mapping in resp.ledgerBooks {
            if let local = dirtyBooks.first(where: { $0.clientId == mapping.clientId }) {
                local.serverId = mapping.serverId
                local.isDirty = false
            }
        }
        for mapping in resp.contacts {
            if let local = dirtyContacts.first(where: { $0.clientId == mapping.clientId }) {
                local.serverId = mapping.serverId
                local.isDirty = false
            }
        }
        for mapping in resp.transactions {
            if let local = dirtyTxs.first(where: { $0.clientId == mapping.clientId }) {
                local.serverId = mapping.serverId
                local.isDirty = false
            }
        }
        for mapping in resp.reminders {
            if let local = dirtyReminders.first(where: { $0.clientId == mapping.clientId }) {
                local.serverId = mapping.serverId
                local.isDirty = false
            }
        }
        
        try context.save()
        print("[Sync] pushed: books=\(dirtyBooks.count) contacts=\(dirtyContacts.count) txs=\(dirtyTxs.count) reminders=\(dirtyReminders.count)")
    }
    
    // MARK: - PULL
    private func pullRemoteChanges(context: ModelContext) async throws {
        let since = lastSyncDate.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let path = "/sync/pull?since=\(since)"
        let resp: PullResponse = try await APIClient.shared.request(path)
        
        // 1. 联系人优先(transaction 引用它)
        for dto in resp.contacts {
            try upsert(dto: dto, in: context)
        }
        // 2. 礼簿(transaction 引用)
        for dto in resp.ledgerBooks {
            try upsert(dto: dto, in: context)
        }
        // 3. 来往
        for dto in resp.transactions {
            try upsert(dto: dto, in: context)
        }
        // 4. 提醒
        for dto in resp.reminders {
            try upsert(dto: dto, in: context)
        }
        try context.save()
        print("[Sync] pulled: books=\(resp.ledgerBooks.count) contacts=\(resp.contacts.count) txs=\(resp.transactions.count) reminders=\(resp.reminders.count)")
    }
    
    /// 通用 upsert(根据 clientId 匹配,服务器时间更新就覆盖)
    private func upsert(dto: LedgerBookDTO, in context: ModelContext) throws {
        let cid = dto.clientId
        let existing = try context.fetch(FetchDescriptor<LedgerBook>(
            predicate: #Predicate { $0.clientId == cid }
        )).first
        
        if let local = existing {
            // 软删除
            if dto.deletedAt != nil {
                context.delete(local)
                return
            }
            // 仅当服务器更新更晚才覆盖
            guard dto.updatedAt > local.updatedAt else { return }
            local.title = dto.title
            local.category = EventCategory(rawValue: dto.categoryRaw) ?? .other
            local.direction = Direction(rawValue: dto.directionRaw) ?? .incoming
            local.eventDate = dto.eventDate
            local.note = dto.note
            local.coverColorHex = dto.coverColorHex
            local.isClosed = dto.isClosed
            local.updatedAt = dto.updatedAt
            local.serverId = dto.serverId
            local.isDirty = false
        } else if dto.deletedAt == nil {
            let new = LedgerBook(
                title: dto.title,
                category: EventCategory(rawValue: dto.categoryRaw) ?? .other,
                direction: Direction(rawValue: dto.directionRaw) ?? .incoming,
                eventDate: dto.eventDate,
                note: dto.note,
                coverColorHex: dto.coverColorHex,
                isClosed: dto.isClosed
            )
            new.clientId = dto.clientId
            new.serverId = dto.serverId
            new.updatedAt = dto.updatedAt
            new.isDirty = false
            context.insert(new)
        }
    }
    
    private func upsert(dto: ContactDTO, in context: ModelContext) throws {
        let cid = dto.clientId
        let existing = try context.fetch(FetchDescriptor<Contact>(
            predicate: #Predicate { $0.clientId == cid }
        )).first
        
        if let local = existing {
            if dto.deletedAt != nil { context.delete(local); return }
            guard dto.updatedAt > local.updatedAt else { return }
            local.name = dto.name
            local.pinyinInitial = dto.pinyinInitial
            local.phone = dto.phone
            local.relationship = ContactRelation(rawValue: dto.relationshipRaw) ?? .friend
            local.avatarEmoji = dto.avatarEmoji
            local.note = dto.note
            local.birthday = dto.birthday
            local.updatedAt = dto.updatedAt
            local.serverId = dto.serverId
            local.isDirty = false
        } else if dto.deletedAt == nil {
            let new = Contact(
                name: dto.name,
                pinyinInitial: dto.pinyinInitial,
                phone: dto.phone,
                relationship: ContactRelation(rawValue: dto.relationshipRaw) ?? .friend,
                avatarEmoji: dto.avatarEmoji,
                note: dto.note,
                birthday: dto.birthday
            )
            new.clientId = dto.clientId
            new.serverId = dto.serverId
            new.updatedAt = dto.updatedAt
            new.isDirty = false
            context.insert(new)
        }
    }
    
    private func upsert(dto: TransactionDTO, in context: ModelContext) throws {
        let cid = dto.clientId
        let existing = try context.fetch(FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.clientId == cid }
        )).first
        
        // 找关联的 book / contact(by clientId)
        let bookCid = dto.bookClientId
        let contactCid = dto.contactClientId
        let book: LedgerBook? = bookCid.flatMap { id in
            try? context.fetch(FetchDescriptor<LedgerBook>(
                predicate: #Predicate { $0.clientId == id }
            )).first
        }
        let contact: Contact? = contactCid.flatMap { id in
            try? context.fetch(FetchDescriptor<Contact>(
                predicate: #Predicate { $0.clientId == id }
            )).first
        }
        
        if let local = existing {
            if dto.deletedAt != nil { context.delete(local); return }
            guard dto.updatedAt > local.updatedAt else { return }
            local.amount = dto.amount
            local.giftKind = GiftKind(rawValue: dto.giftKindRaw) ?? .cash
            local.itemDescription = dto.itemDescription
            local.date = dto.date
            local.note = dto.note
            local.book = book
            local.contact = contact
            local.updatedAt = dto.updatedAt
            local.serverId = dto.serverId
            local.isDirty = false
        } else if dto.deletedAt == nil {
            let new = Transaction(
                amount: dto.amount,
                giftKind: GiftKind(rawValue: dto.giftKindRaw) ?? .cash,
                itemDescription: dto.itemDescription,
                date: dto.date,
                note: dto.note,
                book: book,
                contact: contact
            )
            new.clientId = dto.clientId
            new.serverId = dto.serverId
            new.updatedAt = dto.updatedAt
            new.isDirty = false
            context.insert(new)
        }
    }
    
    private func upsert(dto: ReminderDTO, in context: ModelContext) throws {
        let cid = dto.clientId
        let existing = try context.fetch(FetchDescriptor<Reminder>(
            predicate: #Predicate { $0.clientId == cid }
        )).first
        
        if let local = existing {
            if dto.deletedAt != nil { context.delete(local); return }
            guard dto.updatedAt > local.updatedAt else { return }
            local.title = dto.title
            local.date = dto.date
            local.useLunar = dto.useLunar
            local.advanceDays = dto.advanceDays
            local.note = dto.note
            local.colorHex = dto.colorHex
            local.isEnabled = dto.isEnabled
            local.updatedAt = dto.updatedAt
            local.serverId = dto.serverId
            local.isDirty = false
        } else if dto.deletedAt == nil {
            let new = Reminder(
                title: dto.title,
                date: dto.date,
                useLunar: dto.useLunar,
                advanceDays: dto.advanceDays,
                note: dto.note,
                colorHex: dto.colorHex,
                isEnabled: dto.isEnabled
            )
            new.clientId = dto.clientId
            new.serverId = dto.serverId
            new.updatedAt = dto.updatedAt
            new.isDirty = false
            context.insert(new)
        }
    }
}

// MARK: - DTOs (与后端 JSON 一致)

struct PushPayload: Codable {
    let ledgerBooks: [LedgerBookDTO]
    let contacts: [ContactDTO]
    let transactions: [TransactionDTO]
    let reminders: [ReminderDTO]
}

struct PushResponse: Codable {
    let ledgerBooks: [IDMapping]
    let contacts: [IDMapping]
    let transactions: [IDMapping]
    let reminders: [IDMapping]
}

struct IDMapping: Codable {
    let clientId: String
    let serverId: String
}

struct PullResponse: Codable {
    let ledgerBooks: [LedgerBookDTO]
    let contacts: [ContactDTO]
    let transactions: [TransactionDTO]
    let reminders: [ReminderDTO]
    let serverTime: Date
}

struct LedgerBookDTO: Codable {
    let clientId: String
    var serverId: String?
    let title: String
    let categoryRaw: String
    let directionRaw: String
    let eventDate: Date
    let note: String
    let coverColorHex: String
    let isClosed: Bool
    let updatedAt: Date
    let deletedAt: Date?
    
    init(_ b: LedgerBook) {
        self.clientId = b.clientId
        self.serverId = b.serverId
        self.title = b.title
        self.categoryRaw = b.category.rawValue
        self.directionRaw = b.direction.rawValue
        self.eventDate = b.eventDate
        self.note = b.note
        self.coverColorHex = b.coverColorHex
        self.isClosed = b.isClosed
        self.updatedAt = b.updatedAt
        self.deletedAt = b.deletedAt
    }
}

struct ContactDTO: Codable {
    let clientId: String
    var serverId: String?
    let name: String
    let pinyinInitial: String
    let phone: String
    let relationshipRaw: String
    let avatarEmoji: String
    let note: String
    let birthday: Date?
    let updatedAt: Date
    let deletedAt: Date?
    
    init(_ c: Contact) {
        self.clientId = c.clientId
        self.serverId = c.serverId
        self.name = c.name
        self.pinyinInitial = c.pinyinInitial
        self.phone = c.phone
        self.relationshipRaw = c.relationship.rawValue
        self.avatarEmoji = c.avatarEmoji
        self.note = c.note
        self.birthday = c.birthday
        self.updatedAt = c.updatedAt
        self.deletedAt = c.deletedAt
    }
}

struct TransactionDTO: Codable {
    let clientId: String
    var serverId: String?
    let amount: Decimal
    let giftKindRaw: String
    let itemDescription: String
    let date: Date
    let note: String
    let bookClientId: String?
    let contactClientId: String?
    let updatedAt: Date
    let deletedAt: Date?
    
    init(_ t: Transaction) {
        self.clientId = t.clientId
        self.serverId = t.serverId
        self.amount = t.amount
        self.giftKindRaw = t.giftKind.rawValue
        self.itemDescription = t.itemDescription
        self.date = t.date
        self.note = t.note
        self.bookClientId = t.book?.clientId
        self.contactClientId = t.contact?.clientId
        self.updatedAt = t.updatedAt
        self.deletedAt = t.deletedAt
    }
}

struct ReminderDTO: Codable {
    let clientId: String
    var serverId: String?
    let title: String
    let date: Date
    let useLunar: Bool
    let advanceDays: Int
    let note: String
    let colorHex: String
    let isEnabled: Bool
    let updatedAt: Date
    let deletedAt: Date?
    
    init(_ r: Reminder) {
        self.clientId = r.clientId
        self.serverId = r.serverId
        self.title = r.title
        self.date = r.date
        self.useLunar = r.useLunar
        self.advanceDays = r.advanceDays
        self.note = r.note
        self.colorHex = r.colorHex
        self.isEnabled = r.isEnabled
        self.updatedAt = r.updatedAt
        self.deletedAt = r.deletedAt
    }
}
