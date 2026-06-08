//
//  Theme.swift
//  MyFavor
//
//  品牌色 & 主题 — 墨绿 + 琥珀 配色方案(自研)
//

import SwiftUI

/// ShapeStyle 扩展 — 让 `.brandInk` 等可在 .foregroundStyle() 中用
extension ShapeStyle where Self == Color {
    static var brandInk: Color { Color.brandInk }
    static var brandInkDeep: Color { Color.brandInkDeep }
    static var brandInkSoft: Color { Color.brandInkSoft }
    static var brandTeal: Color { Color.brandTeal }
    static var brandGold: Color { Color.brandGold }
    static var cardBackground: Color { Color.cardBackground }
    static var pageBackground: Color { Color.pageBackground }
    static var secondaryText: Color { Color.secondaryText }
}

/// 品牌渐变(也作为 ShapeStyle 暴露)
extension ShapeStyle where Self == LinearGradient {
    static var brandGradient: LinearGradient {
        LinearGradient(
            colors: [Color.brandInk, Color.brandInkDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    /// 品牌主色 — 墨绿(自研配色)
    static let brandInk = Color(hex: "#2C5F4F")
    /// 深墨绿(强调)
    static let brandInkDeep = Color(hex: "#1A3D2E")
    /// 浅墨绿背景
    static let brandInkSoft = Color(hex: "#E8F0E8")
    /// 收/送差额—正向(青绿)
    static let brandTeal = Color(hex: "#2BB6A6")
    /// 强调金色(礼金 / 重要金额)
    static let brandGold = Color(hex: "#F2B53C")
    /// 琥珀辅助色
    static let brandAmber = Color(hex: "#F5E6D3")
    /// 卡片背景
    static let cardBackground = Color(.systemBackground)
    /// 页面背景
    static let pageBackground = Color(hex: "#FAF8F4")
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
            colors: [Color.brandInk, Color.brandInkDeep],
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
