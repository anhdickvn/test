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
    @State private var showHotbar = false
    @FocusState private var inputFocused: Bool

    private var account: MCAccount? {
        accountStore.account(for: profile.accountId)
    }

    /// Tìm ô hotbar nào là "la bàn chọn server" — ưu tiên theo tên hiển thị server đặt,
    /// nếu server không đặt tên riêng thì fallback theo itemId 345 (Compass trong 1.12.2).
    private var serverSelectorSlot: Int? {
        let nameHit = client.hotbar.firstIndex { slot in
            guard let slot else { return false }
            let name = slot.plainName.lowercased()
            return name.contains("chọn máy chủ") || name.contains("chon may chu") || name.contains("server")
        }
        if let nameHit { return nameHit }
        return client.hotbar.firstIndex { $0?.itemId == 345 }
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
                HStack(spacing: 16) {
                    if client.state == .connected {
                        Button {
                            showHotbar = true
                        } label: {
                            Image(systemName: "bag.fill") // biểu tượng cặp sách — mở toàn bộ hotbar
                        }

                        Button {
                            if let slot = serverSelectorSlot {
                                client.useHotbarItem(slot) // chuột phải vào la bàn -> server mở GUI chọn server
                            } else {
                                showHotbar = true // không thấy la bàn trong hotbar -> mở hotbar để tự chọn item khác
                            }
                        } label: {
                            Image(systemName: "safari") // biểu tượng la bàn
                        }
                    }
                    connectButton
                }
            }
        }
        .sheet(isPresented: $showHotbar) {
            hotbarSheet
        }
        .sheet(isPresented: Binding(
            get: { client.currentWindow != nil },
            set: { isPresented in if !isPresented { client.closeCurrentWindow() } }
        )) {
            serverMenuSheet
        }
        .onDisappear { client.disconnect(silent: true) }
    }

    /// GUI server mở ra khi chuột phải la bàn (vd danh sách server để chọn vào).
    /// Bấm vào 1 dòng = click chọn ô đó trong menu, y như click chuột trong game thật.
    private var serverMenuSheet: some View {
        NavigationView {
            Group {
                if let window = client.currentWindow, !window.items.isEmpty {
                    List {
                        ForEach(window.items.keys.sorted(), id: \.self) { slot in
                            if let item = window.items[slot] {
                                Button {
                                    client.clickWindowSlot(slot)
                                    client.closeCurrentWindow()
                                } label: {
                                    if let segments = item.nameSegments, !segments.isEmpty {
                                        coloredText(segments)
                                    } else {
                                        Text(item.plainName)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView("Đang tải danh sách...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(client.currentWindow?.title.isEmpty == false ? client.currentWindow!.title : "Chọn server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { client.closeCurrentWindow() }
                }
            }
        }
    }

    private var hotbarSheet: some View {
        NavigationView {
            List {
                ForEach(0..<9, id: \.self) { i in
                    if let item = client.hotbar[i] {
                        Button {
                            client.useHotbarItem(i)
                            showHotbar = false
                        } label: {
                            HStack {
                                if let segments = item.nameSegments, !segments.isEmpty {
                                    coloredText(segments)
                                } else {
                                    Text(item.plainName)
                                }
                                Spacer()
                                Text("x\(item.count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("(ô trống)")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Hotbar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showHotbar = false }
                }
            }
        }
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
