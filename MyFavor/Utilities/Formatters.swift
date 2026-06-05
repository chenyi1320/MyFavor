//
//  Formatters.swift
//  MyFavor
//

import Foundation

enum Fmt {
    /// 货币(人民币)
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "CNY"
        f.currencySymbol = "¥"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()
    
    /// 千分位 — 不带 ¥
    static let amount: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f
    }()
    
    /// 短日期(2026-06-04)
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    /// 中文日期(2026年6月4日 星期四)
    static let chineseDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月d日 EEEE"
        return f
    }()
    
    /// 农历
    static let lunarDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.calendar = Calendar(identifier: .chinese)
        f.dateStyle = .medium
        return f
    }()
    
    /// 格式化金额(¥1,234.50)
    static func money(_ d: Decimal) -> String {
        currency.string(from: NSDecimalNumber(decimal: d)) ?? "¥0"
    }
    
    /// 格式化金额(纯数字 1,234.50)
    static func amountOnly(_ d: Decimal) -> String {
        amount.string(from: NSDecimalNumber(decimal: d)) ?? "0"
    }
}
