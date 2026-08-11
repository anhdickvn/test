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
    @State private var showInventory = false
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
                .overlay(Color.appSurface2)

            HStack(spacing: 8) {
                TextField("Nhắn trong chat...", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .disabled(client.state != .connected)
                    .onSubmit(sendMessage)

                Button("Gửi", action: sendMessage)
                    .disabled(client.state != .connected || input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(Color.appSurface)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Chỉ giữ đúng 2 nút: balo (xem giáp/balo/hotbar) và la bàn (mở GUI chọn server).
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if client.state == .connected {
                        Button("🎒") { showInventory = true } // balo — xem giáp/balo/hotbar

                        Button("🧭") { // la bàn — chuột phải vào la bàn để server mở GUI chọn server
                            if let slot = serverSelectorSlot {
                                client.useHotbarItem(slot)
                            } else {
                                showInventory = true // không thấy la bàn trong hotbar -> mở balo để tự chọn item khác
                            }
                        }
                    }
                    connectButton
                }
            }
        }
        .sheet(isPresented: $showInventory) {
            fullInventorySheet
        }
        .sheet(isPresented: Binding(
            get: { client.currentWindow != nil },
            set: { isPresented in if !isPresented { client.closeCurrentWindow() } }
        )) {
            serverMenuSheet
        }
        // KHÔNG disconnect ở onDisappear: iOS có thể làm View biến mất khi app
        // chuyển nền/chuyển scene. Kết nối phải do nút "Ngắt" chủ động điều khiển.
        .preferredColorScheme(.dark)
    }

    /// GUI server mở ra (vd chuột phải la bàn, hoặc gõ lệnh như "/pv 1" mở kho đồ) — tự bật lên
    /// ngay khi server gửi Open Window, hiện đúng số ô server gửi (vd kho 54 ô) kèm icon từng món.
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
                                    itemRow(icon: mcItemEmoji(for: item.itemId),
                                            segments: item.nameSegments,
                                            plainName: item.plainName)
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

    /// Slot 5-8 = giáp (mũ/áo/quần/giày), 9-35 = balo (main storage), 36-44 = hotbar.
    private var fullInventorySheet: some View {
        NavigationView {
            List {
                Section("Giáp") {
                    inventoryRows(slots: 5...8, emptyText: "(chưa mặc giáp)")
                }
                Section("Balo") {
                    inventoryRows(slots: 9...35, emptyText: "(balo trống)")
                }
                Section("Hotbar") {
                    ForEach(0..<9, id: \.self) { i in
                        if let item = client.hotbar[i] {
                            Button {
                                client.useHotbarItem(i)
                                showInventory = false
                            } label: {
                                itemRow(icon: mcItemEmoji(for: item.itemId),
                                        segments: item.nameSegments,
                                        plainName: item.plainName,
                                        count: item.count)
                            }
                        } else {
                            Text("(ô trống)").foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Giáp / Balo / Hotbar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showInventory = false }
                }
            }
        }
    }

    @ViewBuilder
    private func inventoryRows(slots: ClosedRange<Int>, emptyText: String) -> some View {
        let items = slots.compactMap { slot in client.playerInventory[slot].map { (slot, $0) } }
        if items.isEmpty {
            Text(emptyText).foregroundColor(.secondary)
        } else {
            ForEach(items, id: \.0) { _, item in
                itemRow(icon: mcItemEmoji(for: item.itemId),
                        segments: item.nameSegments,
                        plainName: item.plainName,
                        count: item.count)
            }
        }
    }

    /// 1 dòng hiển thị item: icon (emoji, không cần tải texture) + tên (đúng màu server đặt nếu có) + số lượng.
    @ViewBuilder
    private func itemRow(icon: String, segments: [MCChatSegment]?, plainName: String, count: Int? = nil) -> some View {
        HStack {
            Text(icon)
            if let segments, !segments.isEmpty {
                coloredText(segments)
            } else {
                Text(plainName)
            }
            if let count, count > 1 {
                Spacer()
                Text("x\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                .foregroundColor(.appSecondaryText)
            Spacer()
            if let account {
                Text(account.username)
                    .font(.caption2)
                    .foregroundColor(.appSecondaryText)
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

    /// Không còn icon riêng cho từng dòng log — chỉ hiện đúng nội dung, giữ nguyên màu gốc
    /// server gửi (không tự đổi màu) để dễ đọc như trong game thật.
    @ViewBuilder
    private func logRow(_ entry: MCLogEntry) -> some View {
        if let segments = entry.segments, !segments.isEmpty {
            coloredText(segments)
                .font(.system(.subheadline))
                .textSelection(.enabled)
        } else {
            Text(entry.text)
                .font(.system(.subheadline))
                .foregroundColor(entry.kind == .info ? .appSecondaryText : .appText)
                .textSelection(.enabled)
        }
    }

    /// Ghép các đoạn có màu/định dạng riêng thành 1 Text duy nhất, giữ đúng màu server gửi
    /// (không map lại sang bảng màu khác của app — đây là màu gốc server đặt).
    private func coloredText(_ segments: [MCChatSegment]) -> Text {
        segments.reduce(Text("")) { partial, seg in
            var t = Text(seg.text)
                .foregroundColor(seg.colorHex.flatMap(Color.init(hex:)) ?? .appText)
            if seg.bold { t = t.bold() }
            if seg.italic { t = t.italic() }
            if seg.strikethrough { t = t.strikethrough() }
            if seg.underline { t = t.underline() }
            return partial + t
        }
    }
}
