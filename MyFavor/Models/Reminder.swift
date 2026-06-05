//
//  Reminder.swift
//  MyFavor
//
//  Created by MyFavor on 2026/06/04.
//

import Foundation
import SwiftData
import SwiftUI

/// 事件提醒
@Model
final class Reminder {
    /// 事件标题(如「老李结婚」)
    var title: String = ""
    /// 事件日期(公历)
    var date: Date = Date()
    /// 是否使用农历
    var useLunar: Bool = false
    /// 提前提醒天数(0 = 当天, 1 = 提前 1 天 …)
    var advanceDays: Int = 7
    /// 备注
    var note: String = ""
    /// 颜色标签(hex)
    var colorHex: String = "#FF6B6B"
    /// 是否启用
    var isEnabled: Bool = true
    /// 创建时间
    var createdAt: Date = Date()

    // MARK: - 云同步字段
    var clientId: String = UUID().uuidString
    var serverId: String?
    var updatedAt: Date = Date()
    var isDirty: Bool = true
    var deletedAt: Date?

    init(
        title: String,
        date: Date,
        useLunar: Bool = false,
        advanceDays: Int = 7,
        note: String = "",
        colorHex: String = "#FF6B6B",
        isEnabled: Bool = true
    ) {
        self.title = title
        self.date = date
        self.useLunar = useLunar
        self.advanceDays = advanceDays
        self.note = note
        self.colorHex = colorHex
        self.isEnabled = isEnabled
        self.createdAt = .now
        self.updatedAt = .now
        self.clientId = UUID().uuidString
        self.isDirty = true
    }

    /// 距离今日还有多少天(负数 = 已过期)
    var daysFromNow: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: today, to: target).day ?? 0
    }

    /// 是否已过期
    var isExpired: Bool { daysFromNow < 0 }

    func markDirty() {
        self.updatedAt = .now
        self.isDirty = true
    }
}
