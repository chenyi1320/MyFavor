//
//  TransactionRow.swift
//  MyFavor
//

import SwiftUI

struct TransactionRow: View {
    let tx: Transaction
    
    var body: some View {
        HStack(spacing: 12) {
            // 头像
            ZStack {
                Circle()
                    .fill(Color.brandInkSoft)
                    .frame(width: 44, height: 44)
                Text(tx.contact?.avatarEmoji ?? "🙂")
                    .font(.title3)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tx.contact?.name ?? "未知")
                        .font(.subheadline.bold())
                    if tx.giftKind == .item {
                        Image(systemName: "gift.fill")
                            .font(.caption2)
                            .foregroundStyle(.brandGold)
                    }
                }
                Text(Fmt.shortDate.string(from: tx.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text((tx.book?.direction == .incoming ? "收 " : "送 ") + Fmt.money(tx.amount))
                    .font(.subheadline.bold())
                    .foregroundStyle(tx.book?.direction.color ?? .primary)
                if tx.giftKind == .item, !tx.itemDescription.isEmpty {
                    Text(tx.itemDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
