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
import os

@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    var isSyncing = false
    var lastSyncDate: Date?
    var lastSyncError: String?
    /// 同步进度(0-1),用于 UI 显示
    var progress: Double = 0

    private let lastSyncKey = "myfavor.lastSyncAt"
    private let logger = Logger(subsystem: "com.myfavor.app", category: "Sync")
    /// 共享 ISO8601 formatter(避免每次 new)
    private static let iso8601: ISO8601DateFormatter = ISO8601DateFormatter()

    private init() {
        if let ts = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
            lastSyncDate = ts
        }
    }

    /// 全量同步入口(推+拉)
    /// - Parameter forceFull: true 时忽略 lastSyncDate,拉取该用户云端所有数据
    ///   用于"新账号在本机首次登录"或"删除账号后该邮箱重新注册"场景
    @MainActor
    func syncNow(context: ModelContext, forceFull: Bool = false) async {
        guard AuthService.shared.isLoggedIn else {
            lastSyncError = "未登录,无法同步"
            return
        }
        guard !isSyncing else { return }

        if forceFull {
            lastSyncDate = nil
            UserDefaults.standard.removeObject(forKey: lastSyncKey)
        }

        isSyncing = true
        lastSyncError = nil
        progress = 0
        defer {
            isSyncing = false
            progress = 0
        }

        do {
            try await pushLocalChanges(context: context)
            progress = 0.5
            let serverTime = try await pullRemoteChanges(context: context)
            // 用服务器时间作为下次 since,避免本地时钟漂移导致漏同步/重放
            lastSyncDate = serverTime
            UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
            progress = 1.0
        } catch {
            lastSyncError = (error as? APIError)?.errorDescription ?? "同步失败"
            // 不打印整个 error(可能含敏感数据)
            logger.error("同步失败: \(error.localizedDescription, privacy: .public)")
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

        // === 性能优化:把 dirty 数组转成 Dictionary,O(N) 写入回写 ===
        // 原代码 first(where:) 循环 4 × N × N = O(4N²)
        let bookMap = Dictionary(uniqueKeysWithValues: dirtyBooks.map { ($0.clientId, $0) })
        let contactMap = Dictionary(uniqueKeysWithValues: dirtyContacts.map { ($0.clientId, $0) })
        let txMap = Dictionary(uniqueKeysWithValues: dirtyTxs.map { ($0.clientId, $0) })
        let reminderMap = Dictionary(uniqueKeysWithValues: dirtyReminders.map { ($0.clientId, $0) })

        for mapping in resp.ledgerBooks {
            bookMap[mapping.clientId]?.serverId = mapping.serverId
            bookMap[mapping.clientId]?.isDirty = false
        }
        for mapping in resp.contacts {
            contactMap[mapping.clientId]?.serverId = mapping.serverId
            contactMap[mapping.clientId]?.isDirty = false
        }
        for mapping in resp.transactions {
            txMap[mapping.clientId]?.serverId = mapping.serverId
            txMap[mapping.clientId]?.isDirty = false
        }
        for mapping in resp.reminders {
            reminderMap[mapping.clientId]?.serverId = mapping.serverId
            reminderMap[mapping.clientId]?.isDirty = false
        }

        try context.save()
    }

    // MARK: - PULL
    @discardableResult
    private func pullRemoteChanges(context: ModelContext) async throws -> Date {
        let since = lastSyncDate.map { SyncEngine.iso8601.string(from: $0) } ?? ""
        let path = "/sync/pull?since=\(since)"
        let resp: PullResponse = try await APIClient.shared.request(path)

        // === 性能优化:预加载所有现有记录到 Dictionary,避免每个 DTO 触发 fetch ===
        // 原代码每个 DTO 都 context.fetch 一次 = N+1
        let allBooks = try context.fetch(FetchDescriptor<LedgerBook>())
        let allContacts = try context.fetch(FetchDescriptor<Contact>())
        let allTxs = try context.fetch(FetchDescriptor<Transaction>())
        let allReminders = try context.fetch(FetchDescriptor<Reminder>())
        let bookMap = Dictionary(uniqueKeysWithValues: allBooks.map { ($0.clientId, $0) })
        let contactMap = Dictionary(uniqueKeysWithValues: allContacts.map { ($0.clientId, $0) })
        let txMap = Dictionary(uniqueKeysWithValues: allTxs.map { ($0.clientId, $0) })
        let reminderMap = Dictionary(uniqueKeysWithValues: allReminders.map { ($0.clientId, $0) })

        // 依赖顺序:contacts/books 先,transactions 后
        for dto in resp.contacts {
            try upsert(dto: dto, existing: contactMap[dto.clientId], in: context)
        }
        for dto in resp.ledgerBooks {
            try upsert(dto: dto, existing: bookMap[dto.clientId], in: context)
        }
        for dto in resp.transactions {
            // 查 book/contact 引用不再触发 DB 查询,只在 Map 找
            let book = dto.bookClientId.flatMap { bookMap[$0] }
            let contact = dto.contactClientId.flatMap { contactMap[$0] }
            try upsert(dto: dto, existing: txMap[dto.clientId], book: book, contact: contact, in: context)
        }
        for dto in resp.reminders {
            try upsert(dto: dto, existing: reminderMap[dto.clientId], in: context)
        }
        try context.save()
        return resp.serverTime
    }

    /// 通用 upsert(用预加载的 existing,不再触发 fetch)
    private func upsert(dto: LedgerBookDTO, existing: LedgerBook?, in context: ModelContext) throws {
        if let local = existing {
            // 软删除:直接删
            if dto.deletedAt != nil {
                context.delete(local)
                return
            }
            // LWW:仅当服务器时间更新才覆盖(防止本地未同步的修改被覆盖)
            guard dto.updatedAt > local.updatedAt else { return }
            local.title = dto.title
            local.category = EventCategory(rawValue: dto.categoryRaw) ?? local.category
            local.direction = Direction(rawValue: dto.directionRaw) ?? local.direction
            local.eventDate = dto.eventDate
            local.note = dto.note
            local.coverColorHex = dto.coverColorHex
            local.isClosed = dto.isClosed
            local.userId = dto.userId ?? local.userId   // 同步后端归属(防止本机残留 userId 错位)
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
                isClosed: dto.isClosed,
                userId: dto.userId
            )
            new.clientId = dto.clientId
            new.serverId = dto.serverId
            new.updatedAt = dto.updatedAt
            new.isDirty = false
            context.insert(new)
        }
    }

    private func upsert(dto: ContactDTO, existing: Contact?, in context: ModelContext) throws {
        if let local = existing {
            if dto.deletedAt != nil { context.delete(local); return }
            guard dto.updatedAt > local.updatedAt else { return }
            local.name = dto.name
            local.pinyinInitial = dto.pinyinInitial
            local.phone = dto.phone
            local.relationship = ContactRelation(rawValue: dto.relationshipRaw) ?? local.relationship
            local.avatarEmoji = dto.avatarEmoji
            local.note = dto.note
            local.birthday = dto.birthday
            local.userId = dto.userId ?? local.userId
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
                birthday: dto.birthday,
                userId: dto.userId
            )
            new.clientId = dto.clientId
            new.serverId = dto.serverId
            new.updatedAt = dto.updatedAt
            new.isDirty = false
            context.insert(new)
        }
    }

    private func upsert(dto: TransactionDTO, existing: Transaction?, book: LedgerBook?, contact: Contact?, in context: ModelContext) throws {
        if let local = existing {
            if dto.deletedAt != nil { context.delete(local); return }
            guard dto.updatedAt > local.updatedAt else { return }
            local.amount = Decimal(string: dto.amount) ?? local.amount
            local.giftKind = GiftKind(rawValue: dto.giftKindRaw) ?? local.giftKind
            local.itemDescription = dto.itemDescription
            local.date = dto.date
            local.note = dto.note
            local.book = book
            local.contact = contact
            local.userId = dto.userId ?? local.userId
            local.updatedAt = dto.updatedAt
            local.serverId = dto.serverId
            local.isDirty = false
        } else if dto.deletedAt == nil {
            let new = Transaction(
                amount: Decimal(string: dto.amount) ?? 0,
                giftKind: GiftKind(rawValue: dto.giftKindRaw) ?? .cash,
                itemDescription: dto.itemDescription,
                date: dto.date,
                note: dto.note,
                book: book,
                contact: contact,
                userId: dto.userId
            )
            new.clientId = dto.clientId
            new.serverId = dto.serverId
            new.updatedAt = dto.updatedAt
            new.isDirty = false
            context.insert(new)
        }
    }

    private func upsert(dto: ReminderDTO, existing: Reminder?, in context: ModelContext) throws {
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
            local.userId = dto.userId ?? local.userId
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
                isEnabled: dto.isEnabled,
                userId: dto.userId
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
    var userId: String?
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
        self.userId = b.userId
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
    var userId: String?
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
        self.userId = c.userId
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
    var userId: String?
    let clientId: String
    var serverId: String?
    /// 后端以字符串形式序列化 Decimal(避免 JS 浮点精度问题)
    let amount: String
    let giftKindRaw: String
    let itemDescription: String
    let date: Date
    let note: String
    let bookClientId: String?
    let contactClientId: String?
    let updatedAt: Date
    let deletedAt: Date?

    init(_ t: Transaction) {
        self.userId = t.userId
        self.clientId = t.clientId
        self.serverId = t.serverId
        self.amount = "\(t.amount)"
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
    var userId: String?
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
        self.userId = r.userId
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
