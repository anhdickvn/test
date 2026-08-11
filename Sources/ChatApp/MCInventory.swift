import Foundation

/// 1 item trong hotbar (đã parse xong, sẵn sàng hiển thị).
struct MCItemSlot: Identifiable, Equatable {
    var id = UUID()
    var hotbarIndex: Int          // 0-8
    var itemId: Int16             // ID numeric của item (định dạng pre-1.13)
    var count: Int
    /// Tên hiển thị: ưu tiên tên tuỳ chỉnh server đặt (NBT display.Name), có màu.
    /// Nếu server không đặt tên riêng, đây là nil — UI tự hiện tên id.
    var nameSegments: [MCChatSegment]?

    var plainName: String {
        nameSegments?.map(\.text).joined() ?? "Item #\(itemId)"
    }
}

// MARK: - NBT (Named Binary Tag) — parser tối giản, đủ để lấy display.Name / display.Lore

private enum MCNBT {
    case end
    case byte(Int8)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case float(Float)
    case double(Double)
    case byteArray([Int8])
    case string(String)
    case list([MCNBT])
    case compound([String: MCNBT])
    case intArray([Int32])
    case longArray([Int64])
}

private struct MCNBTReader {
    let data: Data
    var offset: Int

    mutating func readU8() -> UInt8? {
        guard let (v, next) = data.readU8(from: offset) else { return nil }
        offset = next
        return v
    }

    mutating func readI16() -> Int16? {
        guard let (v, next) = data.readI16BE(from: offset) else { return nil }
        offset = next
        return v
    }

    mutating func readI32() -> Int32? {
        guard let (v, next) = data.readI32BE(from: offset) else { return nil }
        offset = next
        return v
    }

    mutating func readI64() -> Int64? {
        guard offset + 8 <= data.count else { return nil }
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(data[data.startIndex + offset + i]) }
        offset += 8
        return Int64(bitPattern: v)
    }

    mutating func readF32() -> Float? {
        guard let bits = readI32() else { return nil }
        return Float(bitPattern: UInt32(bitPattern: bits))
    }

    mutating func readF64() -> Double? {
        guard let bits = readI64() else { return nil }
        return Double(bitPattern: UInt64(bitPattern: bits))
    }

    /// Chuỗi NBT: Short độ dài (unsigned) + UTF-8 bytes.
    mutating func readNBTString() -> String? {
        guard let (hi, n1) = data.readU8(from: offset), let (lo, n2) = data.readU8(from: n1) else { return nil }
        let len = Int(UInt16(hi) << 8 | UInt16(lo))
        offset = n2
        guard offset + len <= data.count else { return nil }
        let start = data.startIndex + offset
        let str = String(data: data[start..<start + len], encoding: .utf8) ?? ""
        offset += len
        return str
    }

    /// Đọc payload của 1 tag theo tagId (không đọc tên — tên đọc riêng ở nơi gọi khi cần).
    mutating func readPayload(tagId: UInt8) -> MCNBT? {
        switch tagId {
        case 0: return .end
        case 1: return readU8().map { .byte(Int8(bitPattern: $0)) }
        case 2: return readI16().map(MCNBT.short)
        case 3: return readI32().map(MCNBT.int)
        case 4: return readI64().map(MCNBT.long)
        case 5: return readF32().map(MCNBT.float)
        case 6: return readF64().map(MCNBT.double)
        case 7: // Byte_Array: Int32 length + bytes
            guard let len = readI32(), len >= 0, offset + Int(len) <= data.count else { return nil }
            let bytes = data[data.startIndex + offset..<data.startIndex + offset + Int(len)].map { Int8(bitPattern: $0) }
            offset += Int(len)
            return .byteArray(bytes)
        case 8: return readNBTString().map(MCNBT.string)
        case 9: // List: Byte elemTagId + Int32 length + payloads (không tên)
            guard let elemId = readU8(), let len = readI32(), len >= 0 else { return nil }
            var items: [MCNBT] = []
            for _ in 0..<len {
                guard let v = readPayload(tagId: elemId) else { return nil }
                items.append(v)
            }
            return .list(items)
        case 10: // Compound: các tag có tên, kết thúc bằng TAG_End
            var dict: [String: MCNBT] = [:]
            while true {
                guard let childId = readU8() else { return nil }
                if childId == 0 { break }
                guard let name = readNBTString(), let value = readPayload(tagId: childId) else { return nil }
                dict[name] = value
            }
            return .compound(dict)
        case 11: // Int_Array
            guard let len = readI32(), len >= 0 else { return nil }
            var vals: [Int32] = []
            for _ in 0..<len { guard let v = readI32() else { return nil }; vals.append(v) }
            return .intArray(vals)
        case 12: // Long_Array
            guard let len = readI32(), len >= 0 else { return nil }
            var vals: [Int64] = []
            for _ in 0..<len { guard let v = readI64() else { return nil }; vals.append(v) }
            return .longArray(vals)
        default:
            return nil // tag lạ — không rõ cách đọc, coi như hỏng
        }
    }

    /// Đọc 1 tag "gốc" đầy đủ: TagID + Name + Payload. Dùng cho NBT gắn kèm trong Slot.
    mutating func readRootTag() -> MCNBT? {
        guard let tagId = readU8() else { return nil }
        if tagId == 0 { return .end }
        guard readNBTString() != nil else { return nil } // tên root thường rỗng, bỏ qua
        return readPayload(tagId: tagId)
    }
}

private extension MCNBT {
    func get(_ key: String) -> MCNBT? {
        if case .compound(let dict) = self { return dict[key] }
        return nil
    }
    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}

// MARK: - Slot data (định dạng pre-1.13 dùng bởi protocol 340 / 1.12.2)

enum MCSlotParser {
    /// Parse 1 Slot bắt đầu tại `offset`, trả về (item hoặc nil nếu ô trống, offset mới).
    /// `hotbarIndex` chỉ dùng để gắn vào kết quả khi gọi từ chỗ biết trước vị trí hotbar.
    static func parse(_ data: Data, from offset: Int, hotbarIndex: Int) -> (MCItemSlot?, Int)? {
        guard let (blockId, next1) = data.readI16BE(from: offset) else { return nil }
        if blockId == -1 { return (nil, next1) } // ô trống
        guard let (countByte, next2) = data.readU8(from: next1),
              let (_, next3) = data.readI16BE(from: next2) // item damage — không cần cho việc hiển thị tên
        else { return nil }

        var reader = MCNBTReader(data: data, offset: next3)
        guard let firstByte = data.readU8(from: next3)?.0 else { return nil }
        var displayNameSegments: [MCChatSegment]?
        var finalOffset = next3

        if firstByte == 0 {
            // Không có NBT — 1 byte TAG_End
            finalOffset = next3 + 1
        } else {
            guard let root = reader.readRootTag() else { return nil }
            finalOffset = reader.offset
            if let name = root.get("display")?.get("Name")?.asString {
                // 1.12.2: display.Name là chuỗi thô kiểu cũ, có thể chứa mã màu §.
                displayNameSegments = chatSegments(from: name)
            }
        }

        let item = MCItemSlot(hotbarIndex: hotbarIndex, itemId: blockId, count: Int(countByte),
                               nameSegments: displayNameSegments)
        return (item, finalOffset)
    }
}
