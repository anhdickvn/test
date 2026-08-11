import SwiftUI

extension Color {
    /// Khởi tạo Color từ chuỗi hex dạng "#RRGGBB". Trả về nil nếu chuỗi không hợp lệ.
    init?(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

struct MCChatView: View {
    let profile: MCServerProfile
    @EnvironmentObject var accountStore: MCAccountStore
    @StateObject private var client = MCClient()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var account: MCAccount? {
        accountStore.account(for: profile.accountId)
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBar

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(client.log) { entry in
                            logRow(entry).id(entry.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: client.log.count) { _ in
                    if let last = client.log.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Nhắn trong chat...", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .disabled(client.state != .connected)
                    .onSubmit(sendMessage)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(client.state != .connected || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                connectButton
            }
        }
        .onDisappear { client.disconnect(silent: true) }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let account {
                Label(account.username, systemImage: "person.fill")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var statusColor: Color {
        switch client.state {
        case .connected: return .green
        case .connecting, .loggingIn: return .yellow
        case .failed: return .red
        case .disconnected: return .gray
        }
    }

    private var statusText: String {
        switch client.state {
        case .disconnected: return "Chưa kết nối"
        case .connecting: return "Đang kết nối..."
        case .loggingIn: return "Đang đăng nhập..."
        case .connected: return "Đã kết nối tới \(profile.host):\(profile.port)"
        case .failed(let reason): return "Lỗi: \(reason)"
        }
    }

    @ViewBuilder
    private var connectButton: some View {
        if client.state == .connected || client.state == .connecting || client.state == .loggingIn {
            Button("Ngắt") { client.disconnect() }
        } else {
            Button("Kết nối") {
                guard let account else { return }
                client.connect(host: profile.host, port: profile.port, username: account.username)
            }
            .disabled(account == nil)
        }
    }

    private func sendMessage() {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        client.sendChat(text)
        input = ""
    }

    @ViewBuilder
    private func logRow(_ entry: MCLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: iconName(for: entry.kind))
                .font(.caption2)
                .foregroundColor(iconColor(for: entry.kind))
                .frame(width: 14)
            if let segments = entry.segments, !segments.isEmpty {
                coloredText(segments)
                    .font(.system(.subheadline))
                    .textSelection(.enabled)
            } else {
                Text(entry.text)
                    .font(.system(.subheadline))
                    .foregroundColor(entry.kind == .info ? .secondary : .primary)
                    .textSelection(.enabled)
            }
        }
    }

    /// Ghép các đoạn có màu/định dạng riêng thành 1 Text duy nhất, giữ đúng màu server gửi.
    private func coloredText(_ segments: [MCChatSegment]) -> Text {
        segments.reduce(Text("")) { partial, seg in
            var t = Text(seg.text)
                .foregroundColor(seg.colorHex.flatMap(Color.init(hex:)) ?? .primary)
            if seg.bold { t = t.bold() }
            if seg.italic { t = t.italic() }
            if seg.strikethrough { t = t.strikethrough() }
            if seg.underline { t = t.underline() }
            return partial + t
        }
    }

    private func iconName(for kind: MCLogEntry.Kind) -> String {
        switch kind {
        case .chat: return "bubble.left.fill"
        case .system: return "megaphone.fill"
        case .info: return "info.circle"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func iconColor(for kind: MCLogEntry.Kind) -> Color {
        switch kind {
        case .chat: return .accentColor
        case .system: return .orange
        case .info: return .secondary
        case .error: return .red
        }
    }
}
