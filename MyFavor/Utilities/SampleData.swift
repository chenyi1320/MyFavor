//
//  SampleData.swift
//  MyFavor
//
//  首次启动种子数据(让用户一进来就有内容可看)
//

import Foundation
import SwiftData

enum SampleData {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        // 已存在数据则跳过
        let bookCount = (try? context.fetchCount(FetchDescriptor<LedgerBook>())) ?? 0
        guard bookCount == 0 else { return }
        
        // ===== 联系人 =====
        let zhangSan  = Contact(name: "张三",   pinyinInitial: "Z", phone: "13800138001", relationship: .friend,    avatarEmoji: "🧑")
        let liSi      = Contact(name: "李四",   pinyinInitial: "L", phone: "13800138002", relationship: .colleague, avatarEmoji: "👨")
        let wangWu    = Contact(name: "王五",   pinyinInitial: "W", phone: "13800138003", relationship: .relative,  avatarEmoji: "👴")
        let amei      = Contact(name: "阿美",   pinyinInitial: "A", phone: "13800138004", relationship: .friend,    avatarEmoji: "👩")
        let dajiu     = Contact(name: "大舅",   pinyinInitial: "D", phone: "13800138005", relationship: .family,    avatarEmoji: "👴")
        let daGu      = Contact(name: "大姑",   pinyinInitial: "D", phone: "13800138006", relationship: .family,    avatarEmoji: "👵")
        [zhangSan, liSi, wangWu, amei, dajiu, daGu].forEach { context.insert($0) }
        
        // ===== 礼簿 =====
        let weddingBook = LedgerBook(
            title: "我的结婚",
            category: .wedding,
            direction: .incoming,
            eventDate: Calendar.current.date(byAdding: .day, value: -120, to: .now) ?? .now,
            note: "婚礼当天收礼",
            coverColorHex: "#2C5F4F"
        )
        let zhouSuiBook = LedgerBook(
            title: "女儿周岁",
            category: .oneYear,
            direction: .incoming,
            eventDate: Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now,
            coverColorHex: "#F2B53C"
        )
        let shouYanBook = LedgerBook(
            title: "老爸六十大寿",
            category: .longevity,
            direction: .outgoing,
            eventDate: Calendar.current.date(byAdding: .day, value: -10, to: .now) ?? .now,
            coverColorHex: "#2BB6A6"
        )
        [weddingBook, zhouSuiBook, shouYanBook].forEach { context.insert($0) }
        
        // ===== 来往明细 =====
        let tx1 = Transaction(amount: 2000, giftKind: .cash, date: weddingBook.eventDate, book: weddingBook, contact: zhangSan)
        let tx2 = Transaction(amount: 1000, giftKind: .cash, date: weddingBook.eventDate, book: weddingBook, contact: liSi)
        let tx3 = Transaction(amount: 5000, giftKind: .cash, date: weddingBook.eventDate, book: weddingBook, contact: dajiu)
        let tx4 = Transaction(amount: 3000, giftKind: .cash, date: weddingBook.eventDate, book: weddingBook, contact: daGu)
        let tx5 = Transaction(amount: 800,  giftKind: .cash, date: zhouSuiBook.eventDate, book: zhouSuiBook, contact: amei)
        let tx6 = Transaction(amount: 500,  giftKind: .cash, date: zhouSuiBook.eventDate, book: zhouSuiBook, contact: liSi)
        let tx7 = Transaction(amount: 1500, giftKind: .cash, date: shouYanBook.eventDate, book: shouYanBook, contact: wangWu)
        let tx8 = Transaction(amount: 200,  giftKind: .item, itemDescription: "保健品",
                              date: shouYanBook.eventDate, book: shouYanBook, contact: zhangSan)
        [tx1, tx2, tx3, tx4, tx5, tx6, tx7, tx8].forEach { context.insert($0) }
        
        // ===== 事件提醒 =====
        let r1 = Reminder(title: "老李结婚",
                          date: Calendar.current.date(byAdding: .day, value: 6,   to: .now) ?? .now,
                          advanceDays: 1, colorHex: "#2C5F4F")
        let r2 = Reminder(title: "王总饭店开业",
                          date: Calendar.current.date(byAdding: .day, value: 12,  to: .now) ?? .now,
                          advanceDays: 3, colorHex: "#F2B53C")
        let r3 = Reminder(title: "姐姐搬家",
                          date: Calendar.current.date(byAdding: .day, value: 95,  to: .now) ?? .now,
                          advanceDays: 7, colorHex: "#2BB6A6")
        let r4 = Reminder(title: "吴先生的儿子考上重点高中",
                          date: Calendar.current.date(byAdding: .day, value: 135, to: .now) ?? .now,
                          advanceDays: 30, colorHex: "#9B6BFF")
        [r1, r2, r3, r4].forEach { context.insert($0) }
        
        try? context.save()
    }
}
