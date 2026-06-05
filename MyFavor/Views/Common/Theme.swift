//
//  Theme.swift
//  MyFavor
//
//  品牌色 & 主题封装(对标人情账簿的珊瑚红主色)
//

import SwiftUI

extension Color {
    /// 品牌主色 — 珊瑚红(对标人情账簿)
    static let brandRed = Color(hex: "#FF6B6B")
    /// 深红(强调)
    static let brandRedDeep = Color(hex: "#E63946")
    /// 浅红背景
    static let brandRedSoft = Color(hex: "#FFE5E5")
    /// 收/送差额—正向(蓝绿)
    static let brandTeal = Color(hex: "#2BB6A6")
    /// 强调金色(VIP / 礼金)
    static let brandGold = Color(hex: "#F2B53C")
    /// 卡片背景
    static let cardBackground = Color(.systemBackground)
    /// 页面背景
    static let pageBackground = Color(hex: "#F7F7F9")
    /// 次要文字
    static let secondaryText  = Color(hex: "#8E8E93")
    
    /// 从 HEX 字符串构造 Color
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "#", with: "")
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        let r, g, b, a: Double
        switch h.count {
        case 6:
            r = Double((v & 0xFF0000) >> 16) / 255
            g = Double((v & 0x00FF00) >>  8) / 255
            b = Double( v & 0x0000FF       ) / 255
            a = 1
        case 8:
            r = Double((v & 0xFF000000) >> 24) / 255
            g = Double((v & 0x00FF0000) >> 16) / 255
            b = Double((v & 0x0000FF00) >>  8) / 255
            a = Double( v & 0x000000FF       ) / 255
        default:
            r = 0; g = 0; b = 0; a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

/// 渐变背景(banner / 大卡片用)
struct BrandGradient: View {
    var body: some View {
        LinearGradient(
            colors: [Color.brandRed, Color.brandRedDeep],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

/// 通用卡片样式
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
