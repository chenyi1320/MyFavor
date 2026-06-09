//
//  QueryHelpers.swift
//  MyFavor
//
//  v2.0 数据与登录账号绑定 — 当前用户作用域工具
//
//  用法:
//    @Query private var allBooks: [LedgerBook]
//    private var books: [LedgerBook] {
//        CurrentUserScope.visible(allBooks, keyPath: \.userId).filter { ... }
//    }
//
//  行为:
//   - 已登录(currentUser.id 存在): 只返回 userId == currentId 的记录
//   - 未登录("先逛逛"模式):       只返回 userId == nil 的样例数据
//   - 跨账号登录同一设备:          旧账号数据被过滤掉,但仍保留在本地(可手动删除或登出后回归可见)
//
//  并发设计:
//   - 整个 enum 是 nonisolated — 任何上下文都能调用(避免在 View 的计算属性上反复标 @MainActor)
//   - 内部用 MainActor.assumeIsolated 读 AuthService(运行时检查必须在 MainActor)
//   - 实际所有 View 计算属性的 getter 都在 MainActor(body 调用),所以 assumeIsolated 不会 crash
//

import Foundation

enum CurrentUserScope {
    /// 当前登录用户 ID;未登录 → nil
    nonisolated static var currentId: String? {
        MainActor.assumeIsolated { AuthService.shared.currentUser?.id }
    }

    /// 判断某条记录是否在当前用户作用域内
    nonisolated static func isVisible(_ recordUserId: String?) -> Bool {
        MainActor.assumeIsolated {
            if let current = AuthService.shared.currentUser?.id {
                return recordUserId == current
            } else {
                return recordUserId == nil
            }
        }
    }

    /// 过滤数组(只保留当前用户可见的记录)
    nonisolated static func visible<T>(_ items: [T], keyPath: KeyPath<T, String?>) -> [T] {
        items.filter { isVisible($0[keyPath: keyPath]) }
    }
}
