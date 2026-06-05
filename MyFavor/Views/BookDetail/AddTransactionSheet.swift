//
//  AddTransactionSheet.swift
//  MyFavor
//

import SwiftUI
import SwiftData

struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerBook.eventDate, order: .reverse) private var books: [LedgerBook]
    @Query(sort: \Contact.name) private var contacts: [Contact]
    
    /// 预选礼簿(从礼簿详情进入时传入)
    var book: LedgerBook?
    
    @State private var selectedBook: LedgerBook?
    @State private var selectedContact: Contact?
    @State private var amount: Decimal? = nil
    @State private var giftKind: GiftKind = .cash
    @State private var itemDesc = ""
    @State private var date: Date = .now
    @State private var note = ""
    @State private var showNewContact = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("归属礼簿") {
                    Picker("礼簿", selection: $selectedBook) {
                        Text("请选择").tag(LedgerBook?.none)
                        ForEach(books) { b in
                            Text("\(b.category.emoji) \(b.title)").tag(LedgerBook?.some(b))
                        }
                    }
                }
                
                Section("联系人") {
                    Picker("联系人", selection: $selectedContact) {
                        Text("请选择").tag(Contact?.none)
                        ForEach(contacts) { c in
                            Text("\(c.avatarEmoji) \(c.name)").tag(Contact?.some(c))
                        }
                    }
                    Button {
                        showNewContact = true
                    } label: {
                        Label("添加新联系人", systemImage: "person.crop.circle.badge.plus")
                            .foregroundStyle(.brandRed)
                    }
                }
                
                Section("礼金 / 礼品") {
                    Picker("类型", selection: $giftKind) {
                        ForEach(GiftKind.allCases) { k in
                            Label(k.rawValue, systemImage: k.systemImage).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("¥").foregroundStyle(.secondary)
                        TextField("0.00", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    
                    if giftKind == .item {
                        TextField("礼品描述(如「保健品」)", text: $itemDesc)
                    }
                }
                
                Section("日期 / 备注") {
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("备注", text: $note, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("记一笔来往")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(!isValid)
                        .bold()
                }
            }
            .sheet(isPresented: $showNewContact) {
                AddContactSheet { newContact in
                    selectedContact = newContact
                }
            }
            .onAppear {
                if selectedBook == nil { selectedBook = book ?? books.first }
            }
        }
    }
    
    private var isValid: Bool {
        guard let a = amount, a > 0 else { return false }
        return selectedBook != nil && selectedContact != nil
    }
    
    private func save() {
        guard let b = selectedBook, let c = selectedContact, let a = amount else { return }
        let tx = Transaction(
            amount: a, giftKind: giftKind, itemDescription: itemDesc,
            date: date, note: note, book: b, contact: c
        )
        context.insert(tx)
        try? context.save()
        dismiss()
    }
}
