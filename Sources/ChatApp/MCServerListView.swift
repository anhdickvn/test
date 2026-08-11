import SwiftUI

struct MCServerListView: View {
    @StateObject private var store = MCProfileStore()
    @EnvironmentObject var accountStore: MCAccountStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if store.profiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("Chưa có server nào")
                            .font(.headline)
                        Text("Nhấn + để thêm server offline/cracked")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.profiles) { profile in
                            NavigationLink {
                                MCChatView(profile: profile)
                                    .environmentObject(accountStore)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name).font(.body.weight(.medium))
                                    Text("\(profile.host):\(profile.port) — \(accountLabel(for: profile))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            store.profiles.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                MCServerEditView(
                    profile: MCServerProfile(name: "", host: "", accountId: accountStore.accounts.first?.id)
                ) { newProfile in
                    store.profiles.append(newProfile)
                }
                .environmentObject(accountStore)
            }
        }
    }

    private func accountLabel(for profile: MCServerProfile) -> String {
        accountStore.account(for: profile.accountId)?.username ?? "Chưa chọn tài khoản"
    }
}

struct MCServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var accountStore: MCAccountStore
    @State var profile: MCServerProfile
    @State private var showAddAccount = false
    let onSave: (MCServerProfile) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Thông tin server") {
                    TextField("Tên gợi nhớ (vd: Server nhà)", text: $profile.name)
                    TextField("Địa chỉ (vd: play.example.com)", text: $profile.host)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    TextField("Cổng", value: $profile.port, format: .number)
                        .keyboardType(.numberPad)
                }

                Section("Tài khoản đăng nhập") {
                    if accountStore.accounts.isEmpty {
                        Text("Chưa có tài khoản nào. Thêm 1 tài khoản (username) ở tab Accounts trước, hoặc thêm nhanh bên dưới.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Username", selection: $profile.accountId) {
                            Text("Chưa chọn").tag(UUID?.none)
                            ForEach(accountStore.accounts) { account in
                                Text(account.username).tag(Optional(account.id))
                            }
                        }
                    }
                    Button {
                        showAddAccount = true
                    } label: {
                        Label("Thêm tài khoản mới", systemImage: "plus.circle")
                    }
                }

                Section {
                    Text("Chỉ hỗ trợ server offline/cracked chạy phiên bản 1.12.2 (protocol 340). Server dùng phiên bản khác hoặc yêu cầu tài khoản Minecraft thật sẽ không kết nối được.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(profile.name.isEmpty ? "Server mới" : profile.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(profile)
                        dismiss()
                    }
                    .disabled(profile.name.trimmingCharacters(in: .whitespaces).isEmpty ||
                              profile.host.trimmingCharacters(in: .whitespaces).isEmpty ||
                              profile.accountId == nil)
                }
            }
            .sheet(isPresented: $showAddAccount) {
                MCAccountEditView(account: MCAccount(username: "Player\(Int.random(in: 100...999))")) { newAccount in
                    accountStore.accounts.append(newAccount)
                    profile.accountId = newAccount.id
                }
            }
        }
    }
}
