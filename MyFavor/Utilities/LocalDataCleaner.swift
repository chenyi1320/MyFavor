//
//  LocalDataCleaner.swift
//  MyFavor
//
//  v2.0 清理本机 SwiftData 里某个 userId 的全部数据
//  用途:
//   1. 永久删除账号后,清本机该 userId 的全部记录
//   2. 切账号时,清本机其他 userId 的全部记录(用户主动确认)
//

import Foundation
import SwiftData

@MainActor
enum LocalDataCleaner {
    /// 统计每种实体中"非当前用户"的数据条数(用于 UI 提示)
    /// 返回: (books, contacts, transactions, reminders) 四个非当前用户记录数
    static func otherUserCounts(
        in context: ModelContext,
        excluding currentUserId: String
    ) -> (books: Int, contacts: Int, transactions: Int, reminders: Int) {
        var booksCount = 0, contactsCount = 0, txsCount = 0, remindersCount = 0

        if let books = try? context.fetch(FetchDescriptor<LedgerBook>()) {
            booksCount = books.filter { $0.userId != nil && $0.userId != currentUserId }.count
        }
        if let contacts = try? context.fetch(FetchDescriptor<Contact>()) {
            contactsCount = contacts.filter { $0.userId != nil && $0.userId != currentUserId }.count
        }
        if let txs = try? context.fetch(FetchDescriptor<Transaction>()) {
            txsCount = txs.filter { $0.userId != nil && $0.userId != currentUserId }.count
        }
        if let reminders = try? context.fetch(FetchDescriptor<Reminder>()) {
            remindersCount = reminders.filter { $0.userId != nil && $0.userId != currentUserId }.count
        }

        return (booksCount, contactsCount, txsCount, remindersCount)
    }

    /// 找出本机所有"非当前用户"的 userId(去重,排序)
    static func findOtherUserIds(
        in context: ModelContext,
        excluding currentUserId: String
    ) -> [String] {
        var ids = Set<String>()

        if let books = try? context.fetch(FetchDescriptor<LedgerBook>()) {
            for b in books {
                if let uid = b.userId, uid != currentUserId { ids.insert(uid) }
            }
        }
        if let contacts = try? context.fetch(FetchDescriptor<Contact>()) {
            for c in contacts {
                if let uid = c.userId, uid != currentUserId { ids.insert(uid) }
            }
        }
        if let txs = try? context.fetch(FetchDescriptor<Transaction>()) {
            for t in txs {
                if let uid = t.userId, uid != currentUserId { ids.insert(uid) }
            }
        }
        if let reminders = try? context.fetch(FetchDescriptor<Reminder>()) {
            for r in reminders {
                if let uid = r.userId, uid != currentUserId { ids.insert(uid) }
            }
        }

        return Array(ids).sorted()
    }

    /// 是否有任何"非当前用户"的数据
    static func hasOtherUsersData(
        in context: ModelContext,
        excluding currentUserId: String
    ) -> Bool {
        !findOtherUserIds(in: context, excluding: currentUserId).isEmpty
    }

    /// 删除指定 userId 归属的全部 LedgerBook / Contact / Transaction / Reminder
    /// 注:SwiftData @Relationship cascade 在 .delete 时级联
    ///     但软删除字段(deletedAt) 不会触发 cascade — 必须先硬删,所以这里直接硬删
    static func cleanup(userId: String, in context: ModelContext) {
        // 先清 transactions(避免外键约束或 cascade 失效)
        if let txs = try? context.fetch(FetchDescriptor<Transaction>()) {
            for tx in txs where tx.userId == userId {
                context.delete(tx)
            }
        }
        if let books = try? context.fetch(FetchDescriptor<LedgerBook>()) {
            for b in books where b.userId == userId {
                context.delete(b)
            }
        }
        if let contacts = try? context.fetch(FetchDescriptor<Contact>()) {
            for c in contacts where c.userId == userId {
                context.delete(c)
            }
        }
        if let reminders = try? context.fetch(FetchDescriptor<Reminder>()) {
            for r in reminders where r.userId == userId {
                context.delete(r)
            }
        }
        try? context.save()
    }

    /// 一键清理所有"非当前用户"的数据
    /// 返回清理的 userId 数量
    @discardableResult
    static func cleanupAllOtherUsers(
        in context: ModelContext,
        excluding currentUserId: String
    ) -> Int {
        let others = findOtherUserIds(in: context, excluding: currentUserId)
        for uid in others {
            cleanup(userId: uid, in: context)
        }
        return others.count
    }
}
