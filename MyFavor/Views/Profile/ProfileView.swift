//
//  ProfileView.swift
//  MyFavor
//
//  "我的" 页 — 含登录状态、云同步入口
//

import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Query private var books: [LedgerBook]
    @Query private var contacts: [Contact]
    @Query private var reminders: [Reminder]
    
    @State private var auth = AuthService.shared
    @State private var sync = SyncEngine.shared
    @State private var showLogin = false
    @State private var showLogoutAlert = false
    @State private var showDeleteAlert = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.pageBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        userHeader
                        if auth.isLoggedIn { syncCard }
                        statsRow
                        functionList
                        if auth.isLoggedIn { dangerZone }
                        Color.clear.frame(height: 80)
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showLogin) { LoginView { showLogin = false } }
            .alert("确认退出登录?", isPresented: $showLogoutAlert) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) { auth.logout() }
            } message: {
                Text("退出后本地数据保留,但不再同步")
            }
            .alert("永久删除账号?", isPresented: $showDeleteAlert) {
                Button("取消", role: .cancel) {}
                Button("永久删除", role: .destructive) {
                    Task { try? await auth.deleteAccount() }
                }
            } message: {
                Text("此操作不可恢复。服务器上的所有云端数据将被删除,本地数据保留。")
            }
        }
    }
    
    // MARK: - 用户卡片
    private var userHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(BrandGradient()).frame(width: 64, height: 64)
                if auth.isLoggedIn {
                    Text(String(auth.currentUser?.name.prefix(1) ?? "我"))
                        .font(.title.bold()).foregroundStyle(.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.title).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                if auth.isLoggedIn, let u = auth.currentUser {
                    Text(u.name.isEmpty ? "MyFavor 用户" : u.name).font(.title3.bold())
                    if let email = u.email, !email.isEmpty {
                        Text(email).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("已登录").font(.caption).foregroundStyle(.brandTeal)
                    }
                } else {
                    Text("未登录").font(.title3.bold())
                    Text("登录后数据将同步到云端").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !auth.isLoggedIn {
                Button {
                    showLogin = true
                } label: {
                    Text("登录")
                        .font(.caption.bold())
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Color.brandRed)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
    
    // MARK: - 云同步卡片
    private var syncCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(.brandRed)
                Text("云同步").font(.headline)
                Spacer()
                if sync.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("立即同步") {
                        Task { await sync.syncNow(context: context) }
                    }
                    .font(.caption.bold())
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.brandRed)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
                }
            }
            HStack {
                if let last = sync.lastSyncDate {
                    Text("上次同步:\(Fmt.shortDate.string(from: last))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("尚未同步").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let err = sync.lastSyncError {
                    Text(err).font(.caption2).foregroundStyle(.red).lineLimit(1)
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
    
    // MARK: - 数据汇总
    private var statsRow: some View {
        HStack(spacing: 12) {
            statBox("\(books.count)", "礼簿")
            statBox("\(contacts.count)", "联系人")
            statBox("\(reminders.count)", "提醒")
        }
        .padding(.horizontal)
    }
    
    private func statBox(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(.brandRed)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - 功能入口
    private var functionList: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ReminderView()
            } label: {
                row("bell.badge.fill", "事件提醒", .brandGold)
            }
            Divider().padding(.leading, 60)
            row("square.and.arrow.up", "导入导出", .brandTeal)
            Divider().padding(.leading, 60)
            row("person.2.fill", "共享记账(规划中)", .purple)
            Divider().padding(.leading, 60)
            row("star.fill", "评分支持", .brandRed)
            Divider().padding(.leading, 60)
            row("info.circle.fill", "关于 MyFavor", .gray)
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
    
    // MARK: - 危险操作区(已登录时)
    private var dangerZone: some View {
        VStack(spacing: 0) {
            Button { showLogoutAlert = true } label: {
                row("rectangle.portrait.and.arrow.right", "退出登录", .orange)
            }
            Divider().padding(.leading, 60)
            Button { showDeleteAlert = true } label: {
                row("trash.fill", "永久删除账号", .red)
            }
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
    
    private func row(_ icon: String, _ title: String, _ color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon).foregroundStyle(color)
            }
            Text(title).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [LedgerBook.self, Contact.self, Reminder.self, Transaction.self],
                        inMemory: true)
}
