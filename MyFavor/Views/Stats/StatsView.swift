//
//  StatsView.swift
//  MyFavor
//
//  来往统计 — Swift Charts(iOS 16+)
//

import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query private var allTxs: [Transaction]
    @State private var groupBy: GroupBy = .year
    @State private var cashOnly = false

    enum GroupBy: String, CaseIterable, Identifiable {
        case year = "按年", month = "按月", relation = "按关系"
        var id: String { rawValue }
    }

    private var filteredTxs: [Transaction] {
        let visible = CurrentUserScope.visible(allTxs, keyPath: \.userId)
        return cashOnly ? visible.filter { $0.giftKind == .cash } : visible
    }

    private var totalIncoming: Decimal {
        filteredTxs.filter { $0.book?.direction == .incoming }.reduce(0) { $0 + $1.amount }
    }
    private var totalOutgoing: Decimal {
        filteredTxs.filter { $0.book?.direction == .outgoing }.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.pageBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            ForEach(GroupBy.allCases) { g in
                                Button {
                                    groupBy = g
                                } label: {
                                    Text(g.rawValue)
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(groupBy == g ? Color.brandInk : Color.cardBackground)
                                        .foregroundStyle(groupBy == g ? .white : .secondary)
                                        .clipShape(Capsule())
                                }
                            }
                            Toggle("仅看礼金", isOn: $cashOnly)
                                .toggleStyle(.button)
                                .controlSize(.small)
                                .font(.caption)
                                .tint(.brandInk)
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        HStack(spacing: 12) {
                            totalCard("收礼", totalIncoming, .brandInk, "arrow.down.circle.fill")
                            totalCard("送礼", totalOutgoing, .brandTeal, "arrow.up.circle.fill")
                        }
                        .padding(.horizontal)
                        
                        HStack {
                            Text("收送差").font(.subheadline).foregroundStyle(.secondary)
                            Spacer()
                            Text(Fmt.money(totalIncoming - totalOutgoing))
                                .font(.title3.bold())
                                .foregroundStyle((totalIncoming - totalOutgoing) >= 0 ? .brandInk : .brandTeal)
                        }
                        .padding()
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                        
                        chartCard.padding(.horizontal)
                        tableCard.padding(.horizontal)
                        
                        Color.clear.frame(height: 80)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("统计")
        }
    }
    
    private func totalCard(_ title: String, _ amount: Decimal,
                           _ color: Color, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text(Fmt.money(amount))
                .font(.title2.bold())
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("收送趋势图").font(.headline)
            Chart(chartItems) { item in
                BarMark(
                    x: .value("分组", item.label),
                    y: .value("金额", item.value)
                )
                .foregroundStyle(by: .value("类型", item.direction))
                .position(by: .value("类型", item.direction))
            }
            .chartForegroundStyleScale([
                "收礼": Color.brandInk,
                "送礼": Color.brandTeal
            ])
            .frame(height: 220)
        }
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private var tableCard: some View {
        // 显式存为 let,让编译器看清是 [StatsRow] 不是 Binding
        let rows: [StatsRow] = tableRows

        return VStack(alignment: .leading, spacing: 0) {
            Text("收送统计表").font(.headline).padding()
            HStack {
                Text(headerLabel).frame(width: 80, alignment: .leading)
                Spacer()
                Text("收礼").frame(width: 80, alignment: .trailing).foregroundStyle(.brandInk)
                Text("送礼").frame(width: 80, alignment: .trailing).foregroundStyle(.brandTeal)
                Text("收送差").frame(width: 80, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            Divider()
            // 直接用数组本身(ForEach over Identifiable 或带 id)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack {
                    Text(row.label).frame(width: 80, alignment: .leading)
                    Spacer()
                    Text(Fmt.amountOnly(row.incoming)).frame(width: 80, alignment: .trailing).foregroundStyle(.brandInk)
                    Text(Fmt.amountOnly(row.outgoing)).frame(width: 80, alignment: .trailing).foregroundStyle(.brandTeal)
                    Text(Fmt.amountOnly(row.incoming - row.outgoing))
                        .frame(width: 80, alignment: .trailing)
                        .foregroundStyle((row.incoming - row.outgoing) >= 0 ? Color.primary : .brandTeal)
                }
                .font(.caption)
                .padding(.horizontal).padding(.vertical, 8)
                Divider()
            }
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private var headerLabel: String {
        switch groupBy {
        case .year:     return "年份"
        case .month:    return "月份"
        case .relation: return "关系"
        }
    }
    
    private struct ChartItem: Identifiable {
        let id = UUID()
        let label: String
        let value: Decimal
        let direction: String
    }
    
    private var chartItems: [ChartItem] {
        var items: [ChartItem] = []
        for row in tableRows {
            items.append(.init(label: row.label, value: row.incoming, direction: "收礼"))
            items.append(.init(label: row.label, value: row.outgoing, direction: "送礼"))
        }
        return items
    }
    
    private struct StatsRow {
        let label: String
        let incoming: Decimal
        let outgoing: Decimal
    }
    
    private var tableRows: [StatsRow] {
        let cal = Calendar.current
        let dict: [String: [Transaction]]
        switch groupBy {
        case .year:
            dict = Dictionary(grouping: filteredTxs) { String(cal.component(.year, from: $0.date)) }
        case .month:
            dict = Dictionary(grouping: filteredTxs) {
                let y = cal.component(.year, from: $0.date)
                let m = cal.component(.month, from: $0.date)
                return String(format: "%04d-%02d", y, m)
            }
        case .relation:
            dict = Dictionary(grouping: filteredTxs) { $0.contact?.relationship.rawValue ?? "其他" }
        }
        return dict.map { key, txs in
            let inc = txs.filter { $0.book?.direction == .incoming }.reduce(Decimal(0)) { $0 + $1.amount }
            let out = txs.filter { $0.book?.direction == .outgoing }.reduce(Decimal(0)) { $0 + $1.amount }
            return StatsRow(label: key, incoming: inc, outgoing: out)
        }
        .sorted { $0.label > $1.label }
    }
}
