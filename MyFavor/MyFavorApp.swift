//
//  MyFavorApp.swift
//  MyFavor
//
//  应用入口 — 启动时根据登录状态决定流程
//

import SwiftUI
import SwiftData

@main
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
            fatalError("无法创建 ModelContainer: \(error)")
        }
    }()

    @State private var auth = AuthService.shared
    @State private var didSkipLogin = false   // 用户点了「先逛逛」
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn || didSkipLogin {
                    RootTabView()
                        .tint(.brandRed)
                        .task {
                            // 首次启动种子数据
                            SampleData.seedIfNeeded(in: container.mainContext)
                            // 已登录则自动同步
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
            print("[DeepLink] unrecognized: \(url)")
            return
        }
        print("[DeepLink] magic token received, verifying...")
        Task {
            let ok = await MagicLinkService.shared.verifyToken(token)
            if ok {
                didSkipLogin = false // 关闭「逛逛」状态,进入正式登录
            }
        }
    }
}


