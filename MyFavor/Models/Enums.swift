//
//  Enums.swift
//  MyFavor
//
//  Created by MyFavor on 2026/06/04.
//

import Foundation
import SwiftUI

/// 来往方向:收礼 or 送礼
enum Direction: String, Codable, CaseIterable, Identifiable {
    case incoming = "收礼"   // 收到的人情
    case outgoing = "送礼"   // 送出的人情
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .incoming: return Color.brandRed
        case .outgoing: return Color.brandTeal
        }
    }
    
    var systemImage: String {
        switch self {
        case .incoming: return "arrow.down.circle.fill"
        case .outgoing: return "arrow.up.circle.fill"
        }
    }
}

/// 事件类型(预置场景)
enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case wedding   = "结婚"
    case birthday  = "生日"
    case fullMoon  = "满月"
    case oneYear   = "周岁"
    case longevity = "寿宴"
    case housewarm = "乔迁"
    case schooling = "升学"
    case promotion = "升职"
    case opening   = "开业"
    case funeral   = "白事"
    case festival  = "节日"
    case other     = "其他"
    
    var id: String { rawValue }
    
    var emoji: String {
        switch self {
        case .wedding:   return "💍"
        case .birthday:  return "🎂"
        case .fullMoon:  return "🌕"
        case .oneYear:   return "🎈"
        case .longevity: return "🎁"
        case .housewarm: return "🏠"
        case .schooling: return "🎓"
        case .promotion: return "📈"
        case .opening:   return "🎊"
        case .funeral:   return "🕯️"
        case .festival:  return "🧧"
        case .other:     return "📝"
        }
    }
}

/// 礼品类型:礼金 or 实物
enum GiftKind: String, Codable, CaseIterable, Identifiable {
    case cash = "礼金"
    case item = "礼品"
    
    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .cash: return "yensign.circle"
        case .item: return "gift"
        }
    }
}

/// 联系人关系分组
enum Relationship: String, Codable, CaseIterable, Identifiable {
    case family    = "家人"
    case relative  = "亲戚"
    case friend    = "朋友"
    case classmate = "同学"
    case colleague = "同事"
    case neighbor  = "邻居"
    case other     = "其他"
    
    var id: String { rawValue }
}
