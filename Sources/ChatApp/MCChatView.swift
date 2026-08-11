import SwiftUI
import UIKit


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
    @State private var showPlayers = false
    @State private var tooltipItem: MCItemSlot?
    @State private var tooltipWindowItem: MCOpenWindowItem?
    @State private var inputFocused = false
    @StateObject private var resourcePack = MCResourcePackStore.shared

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
            .background(Color.black) // nền đen giống khung chat thật của Minecraft

            Divider()

            VStack(spacing: 4) {
                if client.state == .connected && !client.tabCompletions.isEmpty && input.hasPrefix("/") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(client.tabCompletions.prefix(8), id: \.self) { name in
                                Button(name) {
                                    input = replaceLastToken(in: input, with: name)
                                    inputFocused = true
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }

                HStack(spacing: 8) {
                    MCTabTextField(text: $input, isFocused: $inputFocused,
                                   placeholder: "Nhắn trong chat...",
                                   onSubmit: sendMessage,
                                   onTab: completeTab)
                        .disabled(client.state != .connected)
                        .frame(height: 38)

                    Button("Gửi", action: sendMessage)
                        .disabled(client.state != .connected || input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .background(Color.black)
        }
        .background(Color.black.ignoresSafeArea())
        .onChange(of: input) { newValue in
            guard client.state == .connected else { return }
            if newValue.hasPrefix("/") && newValue.contains(" ") {
                client.requestTabCompletions(newValue)
            } else if !newValue.hasPrefix("/") {
                client.tabCompletions = []
            }
        }
        .navigationTitle(profile.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Chỉ giữ 2 mục: người chơi và balo/inventory. Không còn mục biểu tượng/la bàn riêng.
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    if client.state == .connected {
                        Button { showPlayers = true } label: {
                            Image(systemName: "person.3.fill")
                        }
                        .accessibilityLabel("Danh sách người chơi")

                        Button { showInventory = true } label: {
                            Image(systemName: "bag.fill")
                        }
                        .accessibilityLabel("Balo, giáp và hotbar")
                    }
                    connectButton
                }
            }
        }
        .sheet(isPresented: $showPlayers) {
            playerListSheet
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
        .onDisappear {
            // Không tự disconnect khi SwiftUI view biến mất. Client tự giữ socket/reconnect.
            // Chỉ nút "Ngắt" mới chủ động kết thúc phiên. Force-quit toàn app thì iOS vẫn
            // có quyền kill process và không có API nào giữ TCP sống sau force-quit.
        }
        .sheet(item: $tooltipItem) { item in
            itemTooltipSheet(name: item.plainName, segments: item.nameSegments,
                             lore: item.loreSegments, image: resourcePack.image(for: item))
        }
        .sheet(item: $tooltipWindowItem) { item in
            itemTooltipSheet(name: item.plainName, segments: item.nameSegments,
                             lore: item.loreSegments, image: resourcePack.image(for: item),
                             windowAction: { mouseButton in
                                 client.clickWindowSlot(item.slot, mouseButton: mouseButton)
                                 tooltipWindowItem = nil
                             })
        }
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
                                itemActionRow(item: item) {
                                    client.clickWindowSlot(slot, mouseButton: 0)
                                    client.closeCurrentWindow()
                                } rightClick: {
                                    client.clickWindowSlot(slot, mouseButton: 1)
                                    client.closeCurrentWindow()
                                } more: {
                                    tooltipWindowItem = item
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
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
                            itemActionRow(item: item) {
                                client.useHotbarItem(i)
                                showInventory = false
                            } rightClick: {
                                client.useHotbarItem(i)
                                showInventory = false
                            } more: {
                                tooltipItem = item
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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
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
                itemActionRow(item: item) {
                    tooltipItem = item
                } rightClick: {
                    tooltipItem = item
                } more: {
                    tooltipItem = item
                }
            }
        }
    }

    /// Một item có icon texture, tên/lore và menu "..." cho click trái/phải.
    @ViewBuilder
    private func itemActionRow(item: MCItemSlot,
                               leftClick: @escaping () -> Void,
                               rightClick: @escaping () -> Void,
                               more: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: leftClick) {
                itemVisual(item: item)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Chuột trái") { leftClick() }
                Button("Chuột phải") { rightClick() }
                Button("Xem tooltip") { more() }
            }

            Spacer(minLength: 0)

            Menu {
                Button("Chuột trái") { leftClick() }
                Button("Chuột phải") { rightClick() }
                Button("Xem tooltip / Lore") { more() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func itemActionRow(item: MCOpenWindowItem,
                               leftClick: @escaping () -> Void,
                               rightClick: @escaping () -> Void,
                               more: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: leftClick) {
                itemVisual(itemId: item.itemId, damage: item.damage,
                           segments: item.nameSegments, plainName: item.plainName)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Chuột trái") { leftClick() }
                Button("Chuột phải") { rightClick() }
                Button("Xem tooltip / Lore") { more() }
            }

            Spacer(minLength: 0)

            Menu {
                Button("Chuột trái") { leftClick() }
                Button("Chuột phải") { rightClick() }
                Button("Xem tooltip / Lore") { more() }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func itemVisual(item: MCItemSlot) -> some View {
        itemVisual(itemId: item.itemId, damage: item.damage,
                    segments: item.nameSegments, plainName: item.plainName, count: item.count)
    }

    @ViewBuilder
    private func itemVisual(itemId: Int16, damage: Int16,
                            segments: [MCChatSegment]?, plainName: String,
                            count: Int? = nil) -> some View {
        HStack(spacing: 10) {
            if let uiImage = resourcePack.image(for: MCItemSlot(hotbarIndex: -1, itemId: itemId,
                                                                damage: damage, count: count ?? 1,
                                                                nameSegments: segments)) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 42, height: 42)
            } else {
                Text(mcItemEmoji(for: itemId))
                    .font(.title2)
                    .frame(width: 42, height: 42)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let segments, !segments.isEmpty {
                    coloredText(segments)
                } else {
                    Text(plainName)
                }
                if let count, count > 1 {
                    Text("x\(count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func itemTooltipSheet(name: String,
                                  segments: [MCChatSegment]?,
                                  lore: [[MCChatSegment]],
                                  image: UIImage?,
                                  windowAction: ((UInt8) -> Void)? = nil) -> some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                        } else {
                            Text("📦").font(.largeTitle)
                        }
                        if let segments, !segments.isEmpty {
                            coloredText(segments).font(.headline)
                        } else {
                            Text(name).font(.headline)
                        }
                    }

                    if !lore.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(lore.enumerated()), id: \.offset) { _, line in
                                coloredText(line)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.leading, 4)
                    } else {
                        Text("Không có Lore")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let windowAction {
                        HStack {
                            Button("Chuột trái") { windowAction(0) }
                                .buttonStyle(.borderedProminent)
                            Button("Chuột phải") { windowAction(1) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Tooltip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") {
                        tooltipItem = nil
                        tooltipWindowItem = nil
                    }
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
                Text(account.username)
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

    private func completeTab() {
        guard client.state == .connected else { return }
        if let completed = client.completeWithNextPlayerName(input) {
            input = completed
            inputFocused = true
            client.requestTabCompletions(input)
        } else if input.hasPrefix("/") {
            client.requestTabCompletions(input)
            inputFocused = true
        }
    }

    private func replaceLastToken(in text: String, with value: String) -> String {
        guard let range = text.range(of: #"\S+$"#, options: .regularExpression) else { return text + value }
        return String(text[..<range.lowerBound]) + value
    }

    private var playerListSheet: some View {
        NavigationView {
            List {
                Section("Online · \(client.onlinePlayerNames.count)") {
                    if client.onlinePlayerNames.isEmpty {
                        Text("Chưa nhận được danh sách người chơi từ server.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(client.onlinePlayerNames.sorted { $0.lowercased() < $1.lowercased() }, id: \.self) { name in
                            HStack(spacing: 10) {
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                                Text(name)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Người chơi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Đóng") { showPlayers = false }
                }
            }
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
                .foregroundColor(entry.kind == .info ? .secondary : .primary)
                .textSelection(.enabled)
        }
    }

    /// Ghép các đoạn có màu/định dạng riêng thành 1 Text duy nhất, giữ đúng màu server gửi
    /// (không map lại sang bảng màu khác của app — đây là màu gốc server đặt).
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
}
