//
//  BookDetailView.swift
//  MyFavor
//
//  礼簿详情 — 收/送总额 + 按拼音分组列表
//

import SwiftUI
import SwiftData

struct BookDetailView: View {
    @Bindable var book: LedgerBook
    @Environment(\.modelContext) private var context
    
    enum SortKey: String, CaseIterable, Identifiable {
        case name = "姓名", time = "来往时间", record = "记录时间", cashOnly = "仅看礼金"
        var id: String { rawValue }
    }
    @State private var sortKey: SortKey = .name
    @State private var showAdd = false
    
    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    summaryHeader
                    sortBar
                    if filteredAndSortedTransactions.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "暂无记录",
                            subtitle: "点击右下角 + 记录第一笔来往"
                        )
                        .padding(.top, 60)
                    } else {
                        groupedList
                    }
                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        book.isClosed.toggle()
                        try? context.save()
                    } label: {
                        Label(book.isClosed ? "解除封账" : "封账(防误编辑)",
                              systemImage: book.isClosed ? "lock.open" : "lock")
                    }
                    Button(role: .destructive) {
                        context.delete(book)
                        try? context.save()
                    } label: {
                        Label("删除礼簿", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: {
                    Image(systemName: "plus")
                }
                .disabled(book.isClosed)
            }
        }
        .sheet(isPresented: $showAdd) {
            AddTransactionSheet(book: book)
        }
    }
    
    // MARK: - 汇总头
    private var summaryHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(book.category.emoji) \(book.category.rawValue)")
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.brandRedSoft)
                    .foregroundStyle(.brandRedDeep)
                    .clipShape(Capsule())
                Spacer()
                Text(Fmt.shortDate.string(from: book.eventDate))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                summaryNumber(title: book.direction == .incoming ? "收礼" : "送礼",
                              amount: book.totalAmount,
                              count: book.count,
                              color: book.direction.color)
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color(hex: book.coverColorHex).opacity(0.15), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
    
    private func summaryNumber(title: String, amount: Decimal, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(Fmt.money(amount))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text("\(title) · \(count) 笔")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - 排序栏
    private var sortBar: some View {
        HStack(spacing: 8) {
            ForEach(SortKey.allCases) { key in
                Button {
                    sortKey = key
                } label: {
                    Text(key.rawValue)
                        .font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(sortKey == key ? Color.brandRed : Color.cardBackground)
                        .foregroundStyle(sortKey == key ? .white : .secondary)
                        .clipShape(Capsule())
                }
            }
            Spacer()
        }
    }
    
    // MARK: - 分组列表
    private var filteredAndSortedTransactions: [Transaction] {
        var list = book.transactions
        if sortKey == .cashOnly { list = list.filter { $0.giftKind == .cash } }
        switch sortKey {
        case .name:
            return list.sorted {
                ($0.contact?.pinyinInitial ?? "#") < ($1.contact?.pinyinInitial ?? "#")
            }
        case .time, .cashOnly:
            return list.sorted { $0.date > $1.date }
        case .record:
            return list.sorted { $0.createdAt > $1.createdAt }
        }
    }
    
    private var groupedByLetter: [(String, [Transaction])] {
        let dict = Dictionary(grouping: filteredAndSortedTransactions) {
            $0.contact?.pinyinInitial ?? "#"
        }
        return dict.sorted { $0.key < $1.key }
    }
    
    @ViewBuilder
    private var groupedList: some View {
        if sortKey == .name {
            VStack(spacing: 14) {
                ForEach(groupedByLetter, id: \.0) { letter, txs in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(letter)
                            .font(.caption.bold())
                            .foregroundStyle(.brandRed)
                            .padding(.leading, 4)
                        VStack(spacing: 0) {
                            ForEach(txs) { tx in
                                TransactionRow(tx: tx)
                                if tx.id != txs.last?.id {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(filteredAndSortedTransactions) { tx in
                    TransactionRow(tx: tx)
                    if tx.id != filteredAndSortedTransactions.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
