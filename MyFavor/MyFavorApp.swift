//
//  MyFavorApp.swift
//  MyFavor
//
//  应用入口 — 启动时根据登录状态决定流程
//

import SwiftUI
import SwiftData

@main
@MainActor
struct MyFavorApp: App {
    /// 全局 SwiftData 容器
    let container: ModelContainer = {
        let schema = Schema([
            LedgerBook.self,
            Contact.self,
            Transaction.self,
            Reminder.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 降级:磁盘失败时尝试内存模式,避免 App 闪退
            print("[FATAL] SwiftData 容器创建失败,降级到内存模式: \(error)")
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // 如果连内存也失败,才是真没救
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }()

    @State private var auth = AuthService.shared
    /// "先逛逛"状态 — 持久化到 UserDefaults,App 重启后保留
    @AppStorage("myfavor.didSkipLogin") private var didSkipLogin = false
    @Environment(\.scenePhase) private var scenePhase

    /// v2.0:切账号后,本机检测到其他账号数据时弹确认 alert
    @State private var showOtherUsersCleanupAlert = false
    @State private var otherUsersCleanupSummary: (count: Int, books: Int, contacts: Int, transactions: Int, reminders: Int)?

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn || didSkipLogin {
                    RootTabView()
                        .tint(.brandInk)
                        .task {
                            // 首次启动种子数据(只在本地使用 / 未登录时)
                            SampleData.seedIfNeeded(in: container.mainContext)
                            // 已登录则自动同步(放在 seed 之后,避免种子数据被误推)
                            if auth.isLoggedIn {
                                // === v2.0:如果本机没有该 userId 的同步记录 → 强制全量拉取 ===
                                // 场景:新账号首次在本机登录 / 删除账号后用同邮箱重新注册
                                let lastUserId = UserDefaults.standard.string(forKey: "myfavor.lastSyncUserId")
                                let currentId = auth.currentUser?.id
                                let needFullSync = (lastUserId != currentId)
                                await SyncEngine.shared.syncNow(
                                    context: container.mainContext,
                                    forceFull: needFullSync
                                )
                                UserDefaults.standard.set(currentId, forKey: "myfavor.lastSyncUserId")
                            }
                        }
                } else {
                    LoginView { didSkipLogin = true }
                }
            }
            .modelContainer(container)
            .onChange(of: scenePhase) { _, phase in
                // App 切换到前台时,自动同步
                if phase == .active, auth.isLoggedIn {
                    Task {
                        await SyncEngine.shared.syncNow(context: container.mainContext)
                    }
                }
            }
            // 监听用户切换:清除"上次同步用户"标记,触发全量同步
            // (覆盖"App 已启动后才登录 / 登录一个账号后登出再换另一个"的场景)
            .onChange(of: auth.currentUser?.id) { _, newId in
                let lastUserId = UserDefaults.standard.string(forKey: "myfavor.lastSyncUserId")
                if lastUserId != newId {
                    // 不同用户(登出后换号 / 登录另一个账号)→ 强制下次 sync 为全量
                    SyncEngine.shared.lastSyncDate = nil
                    UserDefaults.standard.removeObject(forKey: "myfavor.lastSyncAt")
                    UserDefaults.standard.set(newId, forKey: "myfavor.lastSyncUserId")
                    // 已登录新用户 → 同步完成后,检查本机是否有其他账号数据
                    if let newId = newId, auth.isLoggedIn {
                        Task {
                            await SyncEngine.shared.syncNow(
                                context: container.mainContext,
                                forceFull: true
                            )
                            // 同步完后再问,避免"先弹出清理 alert 又被新数据淹没"
                            let counts = LocalDataCleaner.otherUserCounts(
                                in: container.mainContext, excluding: newId
                            )
                            if counts.books + counts.contacts + counts.transactions + counts.reminders > 0 {
                                otherUsersCleanupSummary = (
                                    count: LocalDataCleaner.findOtherUserIds(
                                        in: container.mainContext, excluding: newId
                                    ).count,
                                    books: counts.books,
                                    contacts: counts.contacts,
                                    transactions: counts.transactions,
                                    reminders: counts.reminders
                                )
                                showOtherUsersCleanupAlert = true
                            }
                        }
                    }
                }
            }
            // 切账号时清理本机其他账号数据的确认 alert
            .alert(
                "本机有其他账号的数据",
                isPresented: $showOtherUsersCleanupAlert
            ) {
                Button("保留(仅隐藏)", role: .cancel) {
                    otherUsersCleanupSummary = nil
                }
                Button("清除本机", role: .destructive) {
                    if let newId = auth.currentUser?.id {
                        LocalDataCleaner.cleanupAllOtherUsers(
                            in: container.mainContext, excluding: newId
                        )
                    }
                    otherUsersCleanupSummary = nil
                }
            } message: {
                if let s = otherUsersCleanupSummary {
                    Text("""
                    本机残留着 \(s.count) 个其他账号的本地数据(共 \(s.books) 本礼簿、\(s.contacts) 位联系人、\(s.transactions) 笔来往、\(s.reminders) 条提醒)。

    清除后本机不再保留,云端不受影响 — 这些账号下次在本机登录时,可重新从云端拉取。
                    """)
                }
            }
            // 邮件 Magic Link 深度链接处理:myfavor://magic?token=xxx
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    /// 处理 URL Scheme 跳转
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "myfavor",
              url.host == "magic",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = comps.queryItems?.first(where: { $0.name == "token" })?.value
        else {
            // 不打印 URL(可能含 token 或邮箱)
            return
        }
        // 不打印 "magic token received" 这类可能含敏感信息的日志
        Task {
            let ok = await MagicLinkService.shared.verifyToken(token)
            if ok {
                didSkipLogin = false
            }
        }
    }
}


