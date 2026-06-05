//
//  PinyinHelper.swift
//  MyFavor
//
//  汉字 → 拼音首字母(用于联系人按字母分组)
//

import Foundation

enum PinyinHelper {
    /// 取姓名首个汉字的拼音首字母,失败返回 "#"
    static func firstLetter(of name: String) -> String {
        guard let firstChar = name.first else { return "#" }
        let s = String(firstChar) as NSString
        let mutable = NSMutableString(string: s) as CFMutableString
        // 转拼音
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        // 去掉音调
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let result = (mutable as String).trimmingCharacters(in: .whitespaces)
        if let firstLetter = result.first, firstLetter.isLetter {
            return String(firstLetter).uppercased()
        }
        return "#"
    }
}
