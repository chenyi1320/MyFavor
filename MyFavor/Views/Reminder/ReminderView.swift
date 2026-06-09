//
//  ReminderView.swift
//  MyFavor
//
//  事件提醒
//

import SwiftUI
import SwiftData

struct ReminderView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Reminder.date) private var allReminders: [Reminder]
    @State private var showAdd = false

    private var reminders: [Reminder] {
        CurrentUserScope.visible(allReminders, keyPath: \.userId)
    }

    var body: some View {
        ZStack {
            Color.pageBackground.ignoresSafeArea()
            if reminders.isEmpty {
                EmptyStateView(icon: "bell.slash",
                               title: "暂无提醒",
                               subtitle: "添加重要日子,再也不会忘")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(reminders) { r in
                            ReminderCard(reminder: r)
                        }
                        Color.clear.frame(height: 80)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("事件提醒")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddReminderSheet() }
    }
}

struct ReminderCard: View {
    let reminder: Reminder
    
    var body: some View {
        HStack(spacing: 14) {
            // 左侧圆点
            Circle()
                .fill(Color(hex: reminder.colorHex))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(reminder.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(reminder.isExpired ? .secondary : .primary)
                HStack(spacing: 6) {
                    Image(systemName: "calendar").font(.caption2)
                    Text(Fmt.chineseDate.string(from: reminder.date))
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                if !reminder.note.isEmpty {
                    Text(reminder.note).font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            // 倒计时徽章
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(reminder.isExpired ? Color.gray.opacity(0.3) : Color(hex: reminder.colorHex))
                    .frame(width: 58, height: 56)
                VStack(spacing: 0) {
                    if reminder.isExpired {
                        Text("已过期").font(.caption2.bold()).foregroundStyle(.white)
                    } else {
                        Text("距离还有").font(.system(size: 8)).foregroundStyle(.white.opacity(0.9))
                        Text("\(reminder.daysFromNow)")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .opacity(reminder.isExpired ? 0.6 : 1)
    }
}

struct AddReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @State private var title = ""
    @State private var date: Date = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var advanceDays = 7
    @State private var colorHex = "#2C5F4F"
    @State private var note = ""
    
    private let colorChoices = [
        "#2C5F4F",  // 墨绿(主)
        "#1A3D2E",  // 深墨绿
        "#F2B53C",  // 金
        "#2BB6A6",  // 青
        "#9B6BFF"   // 紫
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("事件") {
                    TextField("事件标题", text: $title)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Stepper("提前 \(advanceDays) 天提醒", value: $advanceDays, in: 0...60)
                }
                Section("颜色") {
                    HStack {
                        ForEach(colorChoices, id: \.self) { hex in
                            Circle().fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(.primary, lineWidth: colorHex == hex ? 2 : 0))
                                .onTapGesture { colorHex = hex }
                        }
                    }
                }
                Section("备注") {
                    TextField("可选", text: $note, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("新建提醒")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let r = Reminder(title: title, date: date,
                                         advanceDays: advanceDays, note: note,
                                         colorHex: colorHex)
                        context.insert(r)
                        try? context.save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .bold()
                }
            }
        }
    }
}
