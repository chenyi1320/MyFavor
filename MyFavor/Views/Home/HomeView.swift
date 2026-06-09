//
//  HomeView.swift
//  MyFavor
//
//  首页 — 礼簿列表(收 / 送 两栏切换)
//

import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerBook.eventDate, order: .reverse) private var allBooks: [LedgerBook]

    @State private var direction: Direction = .incoming
    @State private var searchText = ""
    @State private var showAddBook = false

    private var books: [LedgerBook] {
        CurrentUserScope.visible(allBooks, keyPath: \.userId).filter { book in
            book.direction == direction &&
            (searchText.isEmpty || book.title.localizedCaseInsensitiveContains(searchText))
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.pageBackground.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        // 顶部 Banner
                        bannerCard
                            .padding(.horizontal)
                        
                        // 方向切换
                        directionPicker
                            .padding(.horizontal)
                        
                        // 礼簿卡片网格
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12),
                                      GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(books) { book in
                                NavigationLink(value: book) {
                                    LedgerBookCard(book: book)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            // 添加礼簿卡片
                            Button { showAddBook = true } label: {
                                AddBookCardPlaceholder()
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        
                        Color.clear.frame(height: 80) // tabbar 占位
                    }
                    .padding(.top, 8)
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                            prompt: "搜索礼簿")
            }
            .navigationTitle("礼簿")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 占位:扫码导入
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 占位:通知
                    } label: {
                        Image(systemName: "bell")
                    }
                }
            }
            .navigationDestination(for: LedgerBook.self) { book in
                BookDetailView(book: book)
            }
            .sheet(isPresented: $showAddBook) {
                AddBookSheet()
            }
        }
    }
    
    // MARK: - Banner
    private var bannerCard: some View {
        ZStack(alignment: .leading) {
            BrandGradient()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .frame(height: 110)
                .shadow(color: .brandInk.opacity(0.25), radius: 12, y: 6)
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("共享记账")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text("一个本子，全家共享")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Image(systemName: "person.2.crop.square.stack.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Direction Picker
    private var directionPicker: some View {
        HStack(spacing: 0) {
            ForEach(Direction.allCases) { dir in
                Button {
                    withAnimation(.spring(response: 0.3)) { direction = dir }
                } label: {
                    VStack(spacing: 6) {
                        Text("\(dir.rawValue)礼簿")
                            .font(.headline)
                            .foregroundStyle(direction == dir ? Color.primary : .secondary)
                        Rectangle()
                            .fill(direction == dir ? Color.brandInk : .clear)
                            .frame(height: 3)
                            .clipShape(Capsule())
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - 礼簿卡片
struct LedgerBookCard: View {
    let book: LedgerBook
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部彩色带子
            ZStack(alignment: .topLeading) {
                Color(hex: book.coverColorHex)
                    .frame(height: 70)
                HStack {
                    Text(book.category.emoji).font(.title2)
                    Text(book.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(12)
                
                if book.isClosed {
                    HStack {
                        Spacer()
                        Text("已封账")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(8)
                    }
                }
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
            
            // 主体
            VStack(alignment: .leading, spacing: 6) {
                Text("共\(book.count)笔")
                    .font(.caption).foregroundStyle(.secondary)
                Text(Fmt.money(book.totalAmount))
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.cardBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
}

// MARK: - 添加礼簿空卡片
struct AddBookCardPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.brandInk)
            Text("添加礼簿")
                .font(.subheadline)
                .foregroundStyle(.brandInk)
        }
        .frame(maxWidth: .infinity, minHeight: 152)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6,4]))
                .foregroundStyle(.brandInk.opacity(0.6))
        )
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [LedgerBook.self, Contact.self, Transaction.self, Reminder.self],
                        inMemory: true)
}
