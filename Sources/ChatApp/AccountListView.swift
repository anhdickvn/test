import SwiftUI

struct AccountListView: View {
    @EnvironmentObject var accountStore: MCAccountStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if accountStore.accounts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("Chưa có tài khoản nào")
                            .font(.headline)
                        Text("Nhấn + để thêm 1 username offline/cracked.\nBạn có thể dùng nhiều tài khoản khác nhau cho từng server.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(accountStore.accounts) { account in
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                    .overlay(Text(account.initials).font(.headline))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.username).font(.body.weight(.medium))
                                    Text("Offline / cracked")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            accountStore.accounts.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showAdd) {
                MCAccountEditView(account: MCAccount(username: "")) { newAccount in
                    accountStore.accounts.append(newAccount)
                }
            }
        }
    }
}

struct MCAccountEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var account: MCAccount
    let onSave: (MCAccount) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Tài khoản") {
                    TextField("Username", text: $account.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section {
                    Text("Chỉ dùng để đăng nhập offline/cracked (không phải tài khoản Minecraft/Microsoft thật, không cần mật khẩu). Server phải bật chế độ online-mode=false để chấp nhận đăng nhập kiểu này.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle(account.username.isEmpty ? "Tài khoản mới" : account.username)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") {
                        onSave(account)
                        dismiss()
                    }
                    .disabled(account.username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
