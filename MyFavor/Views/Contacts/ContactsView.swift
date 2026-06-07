//
//  ContactsView.swift
//  MyFavor
//

import SwiftUI
import SwiftData

struct ContactsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\Contact.pinyinInitial), SortDescriptor(\Contact.name)])
    private var contacts: [Contact]
    
    @State private var search = ""
    @State private var showAdd = false
    
    private var filtered: [Contact] {
        guard !search.isEmpty else { return contacts }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    
    private var grouped: [(String, [Contact])] {
        let dict = Dictionary(grouping: filtered) { $0.pinyinInitial }
        return dict.sorted { $0.key < $1.key }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.pageBackground.ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                        ForEach(grouped, id: \.0) { letter, list in
                            Section {
                                VStack(spacing: 0) {
                                    ForEach(list) { c in
                                        NavigationLink(value: c) {
                                            ContactRow(contact: c)
                                        }
                                        .buttonStyle(.plain)
                                        if c.id != list.last?.id {
                                            Divider().padding(.leading, 70)
                                        }
                                    }
                                }
                                .background(Color.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .padding(.horizontal)
                            } header: {
                                Text(letter)
                                    .font(.caption.bold())
                                    .foregroundStyle(.brandRed)
                                    .padding(.leading, 22)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 4)
                                    .background(Color.pageBackground)
                            }
                        }
                        Color.clear.frame(height: 80)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("联系人")
            .searchable(text: $search, prompt: "搜索姓名")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .navigationDestination(for: Contact.self) { c in
                ContactDetailView(contact: c)
            }
            .sheet(isPresented: $showAdd) {
                AddContactSheet()
            }
        }
    }
}

struct ContactRow: View {
    let contact: Contact
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.brandRedSoft).frame(width: 48, height: 48)
                Text(contact.avatarEmoji).font(.title2)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(contact.name).font(.subheadline.bold())
                    Text(contact.relationship.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.brandRedSoft)
                        .foregroundStyle(.brandRedDeep)
                        .clipShape(Capsule())
                }
                Text("\(contact.transactionCount) 笔来往")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("收 " + Fmt.money(contact.totalIncoming))
                    .font(.caption2).foregroundStyle(.brandRed)
                Text("送 " + Fmt.money(contact.totalOutgoing))
                    .font(.caption2).foregroundStyle(.brandTeal)
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct ContactDetailView: View {
    @Bindable var contact: Contact
    @Environment(\.modelContext) private var context
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.brandRedSoft).frame(width: 84, height: 84)
                        Text(contact.avatarEmoji).font(.system(size: 44))
                    }
                    Text(contact.name).font(.title2.bold())
                    Text(contact.relationship.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.brandRedSoft)
                        .foregroundStyle(.brandRedDeep)
                        .clipShape(Capsule())
                    if !contact.phone.isEmpty {
                        Text(contact.phone).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top)
                
                HStack(spacing: 12) {
                    statBox("收礼", contact.totalIncoming, .brandRed)
                    statBox("送礼", contact.totalOutgoing, .brandTeal)
                }
                .padding(.horizontal)
                
                HStack {
                    Text("收送差").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Fmt.money(contact.balance))
                        .font(.headline.bold())
                        .foregroundStyle(contact.balance >= 0 ? .brandRed : .brandTeal)
                }
                .padding()
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("来往明细").font(.headline).padding(.horizontal)
                    if contact.transactions.isEmpty {
                        EmptyStateView(icon: "tray", title: "暂无来往", subtitle: "")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(contact.transactions.sorted { $0.date > $1.date }) { tx in
                                TransactionRow(tx: tx)
                                if tx.id != contact.transactions.last?.id {
                                    Divider().padding(.leading, 60)
                                }
                            }
                        }
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal)
                    }
                }
            }
        }
        .background(Color.pageBackground)
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func statBox(_ title: String, _ amount: Decimal, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(Fmt.money(amount))
                .font(.title3.bold())
                .foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct AddContactSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    var onCreated: ((Contact) -> Void)? = nil
    
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship: ContactRelation = .friend
    @State private var emoji = "🙂"
    
    private let emojiChoices = ["🙂","🧑","👨","👩","👴","👵","🧒","👶","🧔"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("姓名", text: $name)
                    TextField("手机号", text: $phone)
                        .keyboardType(.phonePad)
                    Picker("关系", selection: $relationship) {
                        ForEach(ContactRelation.allCases) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                }
                Section("头像") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 40))]) {
                        ForEach(emojiChoices, id: \.self) { e in
                            Text(e).font(.title2).padding(6)
                                .background(emoji == e ? Color.brandRedSoft : .clear)
                                .clipShape(Circle())
                                .onTapGesture { emoji = e }
                        }
                    }
                }
            }
            .navigationTitle("新建联系人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .bold()
                }
            }
        }
    }
    
    private func save() {
        let initial = PinyinHelper.firstLetter(of: name)
        let c = Contact(name: name, pinyinInitial: initial, phone: phone,
                        relationship: relationship, avatarEmoji: emoji)
        context.insert(c)
        try? context.save()
        onCreated?(c)
        dismiss()
    }
}
