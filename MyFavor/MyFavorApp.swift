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
                                await SyncEngine.shared.syncNow(context: container.mainContext)
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


