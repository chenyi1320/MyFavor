//
//  AddBookSheet.swift
//  MyFavor
//

import SwiftUI
import SwiftData

struct AddBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @State private var title = ""
    @State private var category: EventCategory = .wedding
    @State private var direction: Direction = .incoming
    @State private var date: Date = .now
    @State private var note = ""
    @State private var colorHex = "#FF6B6B"
    
    private let colorChoices: [String] = [
        "#FF6B6B", "#F2B53C", "#2BB6A6", "#4A90E2",
        "#9B6BFF", "#E63946", "#FF8A65", "#3D5A80"
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("礼簿名称(如「我的结婚」)", text: $title)
                    Picker("方向", selection: $direction) {
                        ForEach(Direction.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    Picker("事件类型", selection: $category) {
                        ForEach(EventCategory.allCases) { c in
                            Text("\(c.emoji) \(c.rawValue)").tag(c)
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                }
                
                Section("封面颜色") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                        ForEach(colorChoices, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 38, height: 38)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: colorHex == hex ? 2 : 0)
                                )
                                .onTapGesture { colorHex = hex }
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("备注") {
                    TextField("可选", text: $note, axis: .vertical)
                        .lineLimit(3...5)
                }
            }
            .navigationTitle("新建礼簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .bold()
                }
            }
        }
    }
    
    private func save() {
        let book = LedgerBook(
            title: title, category: category, direction: direction,
            eventDate: date, note: note, coverColorHex: colorHex
        )
        context.insert(book)
        try? context.save()
        dismiss()
    }
}

#Preview { AddBookSheet().modelContainer(for: LedgerBook.self, inMemory: true) }
