import Foundation
import Network
import Compression

/// Client kết nối TCP tới 1 server Minecraft Java Edition, nói đúng giao thức mạng
/// (KHÔNG chạy Java, KHÔNG vẽ đồ hoạ game) — chỉ đủ để đăng nhập offline, đọc & gửi chat.
///
/// Trước khi login, client tự dò protocol version thật của server (giống "Server List Ping"
/// mà client Minecraft chính chủ / ChatCraft dùng) nên không còn bị cứng vào 1 bản duy nhất.
///
/// Giới hạn đã biết: chỉ hỗ trợ server offline-mode (không yêu cầu tài khoản Minecraft/Microsoft
/// thật). Nếu server bật online-mode, server sẽ gửi "Encryption Request" — client sẽ báo lỗi rõ
/// ràng thay vì treo vô hạn, vì việc đăng nhập tài khoản thật cần thêm luồng xác thực Microsoft
/// riêng (chưa làm trong bản này).
@MainActor
final class MCClient: ObservableObject {
    @Published var state: MCConnectionState = .disconnected
    @Published var log: [MCLogEntry] = []
    @Published var onlinePlayerNames: Set<String> = []

    /// Dùng khi không dò được version thật (server không phản hồi status) — 340 = 1.12.2.
    private let fallbackProtocolVersion: Int32 = 340
    private var protocolVersion: Int32 = 340

    /// Bảng ID gói tin trong file này chỉ được viết đúng cho giao thức 1.12–1.12.2 (protocol 338-340).
    /// App luôn login bằng protocol 340 bất kể status ping báo version nào — vì có server
    /// (proxy, fake version trong MOTD, v.v.) báo protocol khác với protocol thật server chấp nhận
    /// lúc login. Nếu server đó KHÔNG thực sự nói giao thức 1.12.2 ở bước login, các case xử lý
    /// packet bên dưới (handleLoginPacket/handlePlayPacket) sẽ đọc sai dữ liệu.
    private let supportedProtocolRange: ClosedRange<Int32> = 338...340 // 1.12, 1.12.1, 1.12.2

    private var connection: NWConnection?
    private let buffer = MCByteBuffer()
    private var compressionThreshold: Int32 = -1 // -1 = tắt nén
    private var connectAttemptToken = UUID()

    private var host: String = ""
    private var port: UInt16 = 25565
    private var username: String = ""

    // MARK: - Kết nối

    /// `username`: lấy từ MCAccount đã chọn cho server này (đăng nhập kiểu offline/cracked).
    func connect(host: String, port: UInt16, username: String) {
        disconnect(silent: true)
        self.host = host
        self.port = port
        self.username = username
        let token = UUID()
        connectAttemptToken = token

        state = .connecting
        appendLog(.info, "Đang dò phiên bản server \(host):\(port)...")

        probeProtocolVersion(host: host, port: port) { [weak self] probed in
            guard let self, self.connectAttemptToken == token else { return }
            // Lưu ý: KHÔNG dùng protocol mà status ping trả về để chặn hay để login.
            // Một số server (proxy fake version, MOTD tuỳ chỉnh, v.v.) báo protocol khác
            // với protocol thật sự chấp nhận lúc login — status ping không đáng tin cho việc này.
            // App luôn ép cứng gửi protocol 340 (1.12.2) khi bắt tay & login, giống cách
            // TLauncher / mineflayer (ép version 1.12.2) đang kết nối thành công vào server.
            if let probed {
                self.appendLog(.info, "Server báo protocol \(probed) (\(self.versionHint(for: probed))) qua status ping — bỏ qua, vẫn login bằng 1.12.2 (protocol 340).")
            } else {
                self.appendLog(.info, "Không dò được version qua status ping, login bằng 1.12.2 (protocol 340)...")
            }
            self.protocolVersion = self.fallbackProtocolVersion
            self.openMainConnection(token: token)
        }
    }

    private func versionHint(for protocolNumber: Int32) -> String {
        switch protocolNumber {
        case 47: return "1.8.x"
        case 107...110: return "1.9.x"
        case 210: return "1.10.x"
        case 315...316: return "1.11.x"
        case 335...340: return "1.12.x"
        case 393...404: return "1.13.x"
        case 477...498: return "1.14.x"
        case 573...578: return "1.15.x"
        case 735...756: return "1.16.x"
        case 757...758: return "1.18.x"
        case 759...761: return "1.19.x"
        case 763...767: return "1.20.x"
        case 768...772: return "1.21.x"
        default: return "không xác định"
        }
    }

    func disconnect(silent: Bool = false) {
        connectAttemptToken = UUID() // vô hiệu hoá mọi callback đang chờ (probe/timeout) của lần kết nối trước
        connection?.cancel()
        connection = nil
        compressionThreshold = -1
        onlinePlayerNames.removeAll()
        if !silent {
            appendLog(.info, "Đã ngắt kết nối.")
        }
        state = .disconnected
    }

    // MARK: - Dò protocol version (Server List Ping / Status)

    /// Mở 1 kết nối tạm để hỏi server "bạn đang chạy version nào?" trước khi login thật.
    /// Đây là bước mà mọi client Minecraft (kể cả client chính chủ, ChatCraft...) đều làm
    /// khi hiện màn hình chọn server — giúp không bị cứng vào 1 protocol version.
    private func probeProtocolVersion(host: String, port: UInt16, completion: @escaping (Int32?) -> Void) {
        let probeConn = NWConnection(host: .init(host), port: .init(rawValue: port) ?? 25565, using: .tcp)
        let probeBuffer = MCByteBuffer()
        var finished = false

        func finish(_ result: Int32?) {
            guard !finished else { return }
            finished = true
            probeConn.cancel()
            completion(result)
        }

        func receiveStatus() {
            probeConn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                Task { @MainActor in
                    if let data, !data.isEmpty {
                        probeBuffer.append(data)
                        if let raw = probeBuffer.nextRawPacket() {
                            var idx = 0
                            guard let packetId = MCVarInt.decode(next: {
                                guard idx < raw.count else { return nil }
                                defer { idx += 1 }
                                return raw[raw.startIndex + idx]
                            }), packetId == 0x00 else { finish(nil); return }
                            let body = raw.suffix(from: raw.startIndex + idx)
                            guard let (json, _) = Data(body).readMCString(from: 0),
                                  let jsonData = json.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                                  let versionInfo = obj["version"] as? [String: Any],
                                  let protoNum = versionInfo["protocol"] as? Int else {
                                finish(nil); return
                            }
                            finish(Int32(protoNum))
                            return
                        }
                    }
                    if error != nil || isComplete { finish(nil); return }
                    receiveStatus()
                }
            }
        }

        probeConn.stateUpdateHandler = { newState in
            Task { @MainActor in
                switch newState {
                case .ready:
                    // Handshake với next_state = 1 (Status). Protocol version ở đây không quan trọng
                    // với gói Status Response, server luôn trả về version thật của nó.
                    var hsPayload: [UInt8] = []
                    hsPayload += MCVarInt.encode(-1)
                    hsPayload += mcEncodeString(host)
                    hsPayload += [UInt8(port >> 8), UInt8(port & 0xFF)]
                    hsPayload += MCVarInt.encode(1)
                    let hsBody = MCVarInt.encode(0x00) + hsPayload
                    let hsFull = MCVarInt.encode(Int32(hsBody.count)) + hsBody

                    let reqBody = MCVarInt.encode(0x00) // Status Request (0x00), không có payload
                    let reqFull = MCVarInt.encode(Int32(reqBody.count)) + reqBody

                    probeConn.send(content: Data(hsFull) + Data(reqFull), completion: .contentProcessed { _ in })
                    receiveStatus()
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
        }
        probeConn.start(queue: .main)

        // Không để dò version treo quá lâu nếu server chặn status ping.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { finish(nil) }
    }

    // MARK: - Kết nối thật (login)

    private func openMainConnection(token: UUID) {
        let conn = NWConnection(host: .init(host), port: .init(rawValue: port) ?? 25565, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                guard let self, self.connectAttemptToken == token else { return }
                self.handleConnectionState(newState)
            }
        }
        conn.start(queue: .main)
        receiveLoop(token: token)

        // Nếu sau 7s vẫn chưa vào được .connected, coi như treo (thường do server yêu cầu
        // online-mode và im lặng chờ Encryption Response, hoặc firewall chặn) → báo lỗi rõ ràng
        // thay vì để người dùng thấy app "kết nối mãi không vào".
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            guard let self, self.connectAttemptToken == token else { return }
            if self.state == .connecting || self.state == .loggingIn {
                self.appendLog(.error, "Hết thời gian chờ — server không phản hồi đăng nhập. Có thể server yêu cầu tài khoản Minecraft thật (online-mode) hoặc không thể truy cập từ mạng hiện tại.")
                self.state = .failed("Hết thời gian chờ khi đăng nhập")
                self.connection?.cancel()
            }
        }
    }

    private func handleConnectionState(_ nwState: NWConnection.State) {
        switch nwState {
        case .ready:
            startHandshakeAndLogin()
        case .failed(let error):
            state = .failed(error.localizedDescription)
            appendLog(.error, "Lỗi kết nối: \(error.localizedDescription)")
        case .cancelled:
            break
        default:
            break
        }
    }

    // MARK: - Gửi gói tin

    /// Đóng gói packetID + payload thành 1 gói tin hoàn chỉnh (length-prefixed),
    /// có tính tới nén nếu đã bật.
    private func send(packetId: Int32, payload: [UInt8]) {
        var body = MCVarInt.encode(packetId) + payload

        if compressionThreshold >= 0 {
            // Định dạng khi có nén: [dataLength varint][data (nén nếu vượt ngưỡng, raw nếu không)]
            if body.count >= Int(compressionThreshold) {
                let compressed = zlibDeflate(Data(body))
                let dataLen = MCVarInt.encode(Int32(body.count))
                body = dataLen + Array(compressed)
            } else {
                body = MCVarInt.encode(0) + body // dataLength = 0 nghĩa là không nén
            }
        }

        let full = MCVarInt.encode(Int32(body.count)) + body
        connection?.send(content: Data(full), completion: .contentProcessed { _ in })
    }

    private func startHandshakeAndLogin() {
        state = .loggingIn
        appendLog(.info, "Đang đăng nhập (offline) với tên \(username)...")

        // Handshake (0x00): protocol version, địa chỉ, cổng, next state = 2 (Login)
        var hsPayload: [UInt8] = []
        hsPayload += MCVarInt.encode(protocolVersion)
        hsPayload += mcEncodeString(host)
        hsPayload += [UInt8(port >> 8), UInt8(port & 0xFF)]
        hsPayload += MCVarInt.encode(2)
        send(packetId: 0x00, payload: hsPayload)

        // Login Start (0x00): chỉ cần username ở bản 1.12.2
        send(packetId: 0x00, payload: mcEncodeString(username))
    }

    // MARK: - Nhận dữ liệu

    private func receiveLoop(token: UUID) {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { @MainActor in
                guard self.connectAttemptToken == token else { return }
                if let data, !data.isEmpty {
                    self.buffer.append(data)
                    self.drainPackets()
                }
                if let error {
                    self.state = .failed(error.localizedDescription)
                    self.appendLog(.error, "Mất kết nối: \(error.localizedDescription)")
                    return
                }
                if isComplete {
                    if self.state != .disconnected {
                        self.appendLog(.error, "Server đã đóng kết nối.")
                        self.state = .disconnected
                    }
                    return
                }
                self.receiveLoop(token: token)
            }
        }
    }

    private func drainPackets() {
        while let raw = buffer.nextRawPacket() {
            handleRawPacket(raw)
        }
    }

    /// `raw` = toàn bộ nội dung sau byte độ dài gói (có thể còn nén).
    private func handleRawPacket(_ raw: Data) {
        var payload = raw
        if compressionThreshold >= 0 {
            var idx = 0
            guard let dataLen = MCVarInt.decode(next: {
                guard idx < raw.count else { return nil }
                defer { idx += 1 }
                return raw[raw.startIndex + idx]
            }) else { return }
            let rest = raw.suffix(from: raw.startIndex + idx)
            if dataLen == 0 {
                payload = Data(rest) // không nén
            } else if let inflated = zlibInflate(Data(rest), decompressedSize: Int(dataLen)) {
                payload = inflated
            } else {
                appendLog(.error, "Không giải nén được 1 gói tin, bỏ qua.")
                return
            }
        }

        var idx = 0
        guard let packetId = MCVarInt.decode(next: {
            guard idx < payload.count else { return nil }
            defer { idx += 1 }
            return payload[payload.startIndex + idx]
        }) else { return }
        let body = payload.suffix(from: payload.startIndex + idx)

        switch state {
        case .loggingIn:
            handleLoginPacket(id: packetId, body: Data(body))
        case .connected:
            handlePlayPacket(id: packetId, body: Data(body))
        default:
            break
        }
    }

    // MARK: - Login state

    private func handleLoginPacket(id: Int32, body: Data) {
        switch id {
        case 0x00: // Disconnect (login)
            let (reason, _) = body.readMCString(from: 0) ?? ("Bị từ chối kết nối.", 0)
            appendLog(.error, "Server từ chối đăng nhập: \(prettyChatJSON(reason))")
            state = .failed(prettyChatJSON(reason))
            connection?.cancel()

        case 0x01: // Encryption Request -> server yêu cầu tài khoản Minecraft/Microsoft thật
            appendLog(.error, "Server yêu cầu tài khoản Minecraft thật (online-mode). App hiện chỉ hỗ trợ server offline/cracked, không hỗ trợ đăng nhập bằng tài khoản thật.")
            state = .failed("Server yêu cầu tài khoản thật (online-mode)")
            connection?.cancel()

        case 0x02: // Login Success -> chuyển sang Play
            appendLog(.info, "Đăng nhập thành công, vào server...")
            state = .connected

        case 0x03: // Set Compression
            var idx = 0
            if let threshold = MCVarInt.decode(next: {
                guard idx < body.count else { return nil }
                defer { idx += 1 }
                return body[body.startIndex + idx]
            }) {
                compressionThreshold = threshold
            }

        default:
            break
        }
    }

    // MARK: - Play state

    private func handlePlayPacket(id: Int32, body: Data) {
        switch id {
        case 0x1F: // Keep Alive (clientbound) — 8 byte long, phải gửi lại y nguyên
            guard body.count >= 8 else { return }
            let longBytes = Array(body.prefix(8))
            send(packetId: 0x0B, payload: longBytes) // Keep Alive (serverbound)

        case 0x0F: // Chat Message (clientbound)
            guard let (json, next) = body.readMCString(from: 0) else { return }
            let position = next < body.count ? body[body.startIndex + next] : 0
            let segments = chatSegments(from: json)
            let text = segments.map(\.text).joined()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            appendLog(position == 1 ? .system : .chat, text, segments: segments)

        case 0x1A: // Disconnect (play)
            let (reason, _) = body.readMCString(from: 0) ?? ("Bạn đã bị ngắt kết nối.", 0)
            appendLog(.error, "Bị ngắt kết nối: \(prettyChatJSON(reason))")
            state = .disconnected
            connection?.cancel()

        default:
            break // các gói khác (world, entity, inventory...) bỏ qua có chủ đích
        }
    }

    // MARK: - Gửi chat

    func sendChat(_ text: String) {
        guard state == .connected, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        send(packetId: 0x02, payload: mcEncodeString(text)) // Chat (serverbound)
        // Không tự thêm vào log — server sẽ gửi lại chính tin nhắn này qua Chat Message (clientbound)
    }

    // MARK: - Tiện ích

    private func appendLog(_ kind: MCLogEntry.Kind, _ text: String, segments: [MCChatSegment]? = nil) {
        log.append(MCLogEntry(kind: kind, text: text, segments: segments))
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}

// MARK: - Parse chat component JSON đơn giản (text + extra, bỏ qua màu sắc/định dạng)

func prettyChatJSON(_ jsonString: String) -> String {
    return chatSegments(from: jsonString).map(\.text).joined()
}

/// Parse 1 chuỗi JSON chat component (hoặc chuỗi thô có mã màu §) thành danh sách đoạn có màu,
/// giữ nguyên màu/định dạng gốc từ server thay vì xoá đi — dùng để hiển thị giống client thật.
func chatSegments(from jsonString: String) -> [MCChatSegment] {
    guard let data = jsonString.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) else {
        return splitLegacyCodes(jsonString, base: MCChatStyle())
    }
    return walkChatComponent(obj, style: MCChatStyle())
}

private struct MCChatStyle {
    var colorHex: String?
    var bold = false
    var italic = false
    var underline = false
    var strikethrough = false
}

/// Bảng màu 16 màu chuẩn của Minecraft (mã §0-§f).
private let mcColorHex: [Character: String] = [
    "0": "#000000", "1": "#0000AA", "2": "#00AA00", "3": "#00AAAA",
    "4": "#AA0000", "5": "#AA00AA", "6": "#FFAA00", "7": "#AAAAAA",
    "8": "#555555", "9": "#5555FF", "a": "#55FF55", "b": "#55FFFF",
    "c": "#FF5555", "d": "#FF55FF", "e": "#FFFF55", "f": "#FFFFFF",
]

private let mcNamedColorHex: [String: String] = [
    "black": "#000000", "dark_blue": "#0000AA", "dark_green": "#00AA00", "dark_aqua": "#00AAAA",
    "dark_red": "#AA0000", "dark_purple": "#AA00AA", "gold": "#FFAA00", "gray": "#AAAAAA",
    "dark_gray": "#555555", "blue": "#5555FF", "green": "#55FF55", "aqua": "#55FFFF",
    "red": "#FF5555", "light_purple": "#FF55FF", "yellow": "#FFFF55", "white": "#FFFFFF",
]

/// Tách 1 chuỗi thô chứa mã màu kiểu cũ (§0-§f màu, §l/§o/§n/§m định dạng, §r reset)
/// thành các đoạn (segment) có màu/định dạng riêng, kế thừa style ban đầu `base`.
private func splitLegacyCodes(_ text: String, base: MCChatStyle) -> [MCChatSegment] {
    var segments: [MCChatSegment] = []
    var style = base
    var current = ""
    let chars = Array(text)
    var i = 0

    func flush() {
        guard !current.isEmpty else { return }
        segments.append(MCChatSegment(text: current, colorHex: style.colorHex, bold: style.bold,
                                       italic: style.italic, underline: style.underline,
                                       strikethrough: style.strikethrough))
        current = ""
    }

    while i < chars.count {
        if chars[i] == "\u{00A7}", i + 1 < chars.count {
            flush()
            let code = Character(String(chars[i + 1]).lowercased())
            if let hex = mcColorHex[code] {
                style = MCChatStyle(colorHex: hex) // đổi màu sẽ reset định dạng, đúng hành vi thật của Minecraft
            } else {
                switch code {
                case "l": style.bold = true
                case "o": style.italic = true
                case "n": style.underline = true
                case "m": style.strikethrough = true
                case "r": style = base
                default: break // §k (obfuscated) không hỗ trợ hiệu ứng nhấp nháy, bỏ qua
                }
            }
            i += 2
            continue
        }
        current.append(chars[i])
        i += 1
    }
    flush()
    return segments
}

/// Duyệt đệ quy 1 chat component JSON (text/extra/translate/color/bold...) thành danh sách đoạn có màu.
private func walkChatComponent(_ obj: Any, style: MCChatStyle) -> [MCChatSegment] {
    if let s = obj as? String {
        return splitLegacyCodes(s, base: style)
    }
    guard let dict = obj as? [String: Any] else { return [] }

    var st = style
    if let colorName = dict["color"] as? String {
        st.colorHex = mcNamedColorHex[colorName] ?? (colorName.hasPrefix("#") ? colorName : st.colorHex)
    }
    if let b = dict["bold"] as? Bool { st.bold = b }
    if let it = dict["italic"] as? Bool { st.italic = it }
    if let u = dict["underlined"] as? Bool { st.underline = u }
    if let s2 = dict["strikethrough"] as? Bool { st.strikethrough = s2 }

    var segments: [MCChatSegment] = []
    if let text = dict["text"] as? String, !text.isEmpty {
        segments += splitLegacyCodes(text, base: st)
    }
    if let translate = dict["translate"] as? String {
        let withArr = (dict["with"] as? [Any])?.flatMap { walkChatComponent($0, style: st) } ?? []
        segments += withArr.isEmpty ? splitLegacyCodes(translate, base: st) : withArr
    }
    if let extra = dict["extra"] as? [Any] {
        segments += extra.flatMap { walkChatComponent($0, style: st) }
    }
    return segments
}

// MARK: - zlib nén/giải nén (Minecraft dùng định dạng zlib chuẩn, RFC1950)

private func zlibInflate(_ data: Data, decompressedSize: Int) -> Data? {
    guard decompressedSize > 0, data.count > 6 else { return nil }
    // Bỏ 2 byte header zlib + 4 byte adler32 cuối, còn lại là raw DEFLATE
    let raw = data.dropFirst(2).dropLast(4)
    var result = Data(count: decompressedSize)
    let resultSize: Int = result.withUnsafeMutableBytes { dst -> Int in
        raw.withUnsafeBytes { src -> Int in
            guard let dstPtr = dst.bindMemory(to: UInt8.self).baseAddress,
                  let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return compression_decode_buffer(dstPtr, decompressedSize, srcPtr, raw.count, nil, COMPRESSION_ZLIB)
        }
    }
    guard resultSize == decompressedSize else { return nil }
    return result
}

private func zlibDeflate(_ data: Data) -> Data {
    // Nén raw DEFLATE rồi tự thêm header/trailer zlib tối giản để server chấp nhận.
    let capacity = data.count + data.count / 2 + 64
    var dst = Data(count: capacity)
    let compressedSize: Int = dst.withUnsafeMutableBytes { dstBuf -> Int in
        data.withUnsafeBytes { srcBuf -> Int in
            guard let dstPtr = dstBuf.bindMemory(to: UInt8.self).baseAddress,
                  let srcPtr = srcBuf.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(dstPtr, capacity, srcPtr, data.count, nil, COMPRESSION_ZLIB)
        }
    }
    guard compressedSize > 0 else { return data }
    let deflated = dst.prefix(compressedSize)
    var out = Data([0x78, 0x9C]) // header zlib chuẩn (mức nén mặc định)
    out.append(deflated)
    out.append(contentsOf: adler32(data))
    return out
}

private func adler32(_ data: Data) -> [UInt8] {
    var a: UInt32 = 1
    var b: UInt32 = 0
    let mod: UInt32 = 65521
    for byte in data {
        a = (a + UInt32(byte)) % mod
        b = (b + a) % mod
    }
    let checksum = (b << 16) | a
    return [UInt8(checksum >> 24), UInt8((checksum >> 16) & 0xFF), UInt8((checksum >> 8) & 0xFF), UInt8(checksum & 0xFF)]
}
