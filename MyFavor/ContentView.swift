//
//  ContentView.swift
//  MyFavor
//
//  根 Tab — 礼簿 / 统计 / [+ 中央按钮] / 联系人 / 我的
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selectedTab: Tab = .books
    @State private var showAddSheet = false
    
    enum Tab: Hashable {
        case books, stats, center, contacts, profile
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("礼簿", systemImage: "book.closed.fill") }
                    .tag(Tab.books)
                
                StatsView()
                    .tabItem { Label("统计", systemImage: "chart.bar.fill") }
                    .tag(Tab.stats)
                
                // 中央占位(由浮动按钮覆盖)
                Color.clear
                    .tabItem { Label("", systemImage: "") }
                    .tag(Tab.center)
                    
                
                ContactsView()
                    .tabItem { Label("联系人", systemImage: "person.2.fill") }
                    .tag(Tab.contacts)
                
                ProfileView()
                    .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                    .tag(Tab.profile)
            }
            .tint(.brandInk)
            
            // 中央悬浮 + 按钮
            Button {
                showAddSheet = true
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color.brandInk, Color.brandInkDeep],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 58, height: 58)
                        .shadow(color: .brandInk.opacity(0.45), radius: 10, x: 0, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -8)
            .accessibilityLabel("新建")
        }
        .sheet(isPresented: $showAddSheet) {
            QuickAddSheet()
                .presentationDetents([.medium])
        }
    }
}

/// 中央 + 按钮弹出的快速新建面板
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showBook = false
    @State private var showTx = false
    @State private var showReminder = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                addRow(title: "新建礼簿", subtitle: "为一个事件建立账本",
                       icon: "book.closed.fill", color: .brandInk) { showBook = true }
                addRow(title: "记一笔来往", subtitle: "快速录入收/送礼",
                       icon: "yensign.circle.fill", color: .brandTeal) { showTx = true }
                addRow(title: "添加事件提醒", subtitle: "重要日子不再忘",
                       icon: "bell.badge.fill", color: .brandGold) { showReminder = true }
                Spacer()
            }
            .padding(20)
            .navigationTitle("新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showBook) { AddBookSheet() }
            .sheet(isPresented: $showTx)   { AddTransactionSheet(book: nil) }
            .sheet(isPresented: $showReminder) { AddReminderSheet() }
        }
    }
    
    private func addRow(title: String, subtitle: String, icon: String,
                        color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [LedgerBook.self, Contact.self, Transaction.self, Reminder.self],
                        inMemory: true)
}
