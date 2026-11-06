import Foundation

/// Одно нажатие в записи замера: позиция в тексте, набранный символ, смещение от начала (мс).
public struct ReplayKey: Equatable, Sendable {
    public var position: Int
    public var typed: Character
    public var offsetMs: UInt32

    public init(position: Int, typed: Character, offsetMs: UInt32) {
        self.position = position
        self.typed = typed
        self.offsetMs = offsetMs
    }
}

/// Запись замера для повтора: целевой текст (до последней набранной позиции) и нажатия.
/// В `Data`: версия (1 — как есть, 2 — LZFSE) + тело. Тело: длина текста в знаках, текст UTF-8,
/// число нажатий, дельты времени (varint), затем исключения — нажатия, где позиция не «предыдущая + 1»
/// или символ не совпадает с целевым.
public struct MeasureReplay: Equatable, Sendable {
    public let text: String
    public let keys: [ReplayKey]

    public init(text: String, keys: [ReplayKey]) {
        let last = keys.map(\.position).max() ?? -1
        self.text = String(text.prefix(max(0, last == Int.max ? Int.max : last + 1)))
        self.keys = keys
    }

    /// Те же смещения и символы, что записаны (с ошибками и паузами).
    public var asRecorded: [ReplayKey] { keys }

    /// Только верные символы текста до последней позиции, ровно через 60000/cpm мс; первое — в 0.
    public func timeline(cpm: Int) -> [ReplayKey] {
        guard cpm > 0 else { return [] }
        return text.enumerated().map { index, char in
            ReplayKey(position: index, typed: char,
                      offsetMs: UInt32((Double(index) * 60000 / Double(cpm)).rounded()))
        }
    }

    // MARK: - Кодирование

    public func encoded() -> Data {
        let chars = Array(text)
        var body = Data()
        putVarint(UInt64(chars.count), &body)
        let utf8 = Data(text.utf8)
        putVarint(UInt64(utf8.count), &body)
        body.append(utf8)
        putVarint(UInt64(keys.count), &body)
        var previous: UInt32 = 0
        for key in keys {
            putVarint(UInt64(key.offsetMs &- previous), &body)
            previous = key.offsetMs
        }
        var exceptions = Data()
        var count = 0
        var lastException = 0
        var expected = 0
        for (index, key) in keys.enumerated() {
            let samePosition = key.position == expected
            let sameChar = key.position >= 0 && key.position < chars.count && chars[key.position] == key.typed
            if !samePosition || !sameChar {
                count += 1
                putVarint(UInt64(index - lastException), &exceptions)
                lastException = index
                exceptions.append((samePosition ? 0 : 1) | (sameChar ? 0 : 2))
                if !samePosition { putVarint(UInt64(max(0, key.position)), &exceptions) }
                if !sameChar {
                    let bytes = Data(String(key.typed).utf8)
                    putVarint(UInt64(bytes.count), &exceptions)
                    exceptions.append(bytes)
                }
            }
            expected = key.position + 1
        }
        putVarint(UInt64(count), &body)
        body.append(exceptions)

        if let packed = try? (body as NSData).compressed(using: .lzfse) as Data, packed.count < body.count {
            return Data([2]) + packed
        }
        return Data([1]) + body
    }

    public init?(data: Data) {
        guard let version = data.first, version == 1 || version == 2 else { return nil }
        var body = data.dropFirst()
        if version == 2 {
            guard let raw = try? (Data(body) as NSData).decompressed(using: .lzfse) as Data else { return nil }
            body = raw[...]
        }
        var reader = Reader(bytes: Array(body))
        guard let charCount = reader.varint(), let utf8Count = reader.varint(),
              let utf8Length = Int(exactly: utf8Count),
              let utf8 = reader.take(utf8Length), let text = String(data: Data(utf8), encoding: .utf8),
              UInt64(text.count) == charCount, let keyCount = reader.varint(), keyCount <= UInt64(body.count)
        else { return nil }
        var offsets: [UInt32] = []
        var previous: UInt32 = 0
        for _ in 0..<keyCount {
            guard let delta = reader.varint(), delta <= UInt64(UInt32.max) else { return nil }
            previous = previous &+ UInt32(delta)
            offsets.append(previous)
        }
        guard let exceptionCount = reader.varint(), exceptionCount <= keyCount else { return nil }
        let chars = Array(text)
        var keys: [ReplayKey] = []
        var exceptionIndex = 0
        var remaining = exceptionCount
        var nextException: (index: Int, flags: UInt8, position: Int?, typed: Character?)?
        func readException() -> Bool {
            guard remaining > 0 else { nextException = nil; return true }
            remaining -= 1
            guard let gap = reader.varint(), let flags = reader.byte() else { return false }
            guard gap <= UInt64(keyCount), let gapInt = Int(exactly: gap) else { return false }
            let (sum, overflow) = exceptionIndex.addingReportingOverflow(gapInt)
            guard !overflow else { return false }
            exceptionIndex = sum
            var position: Int?
            var typed: Character?
            if flags & 1 != 0 {
                guard let p = reader.varint(), p < UInt64(Int32.max) else { return false }
                position = Int(p)
            }
            if flags & 2 != 0 {
                guard let n = reader.varint(), let length = Int(exactly: n), let bytes = reader.take(length),
                      let s = String(data: Data(bytes), encoding: .utf8), s.count == 1 else { return false }
                typed = s.first
            }
            nextException = (exceptionIndex, flags, position, typed)
            return true
        }
        guard readException() else { return nil }
        var expected = 0
        for index in 0..<Int(keyCount) {
            var position = expected
            var typed: Character? = nil
            if let e = nextException, e.index == index {
                if let p = e.position { position = p }
                typed = e.typed
                guard readException() else { return nil }
            }
            if typed == nil {
                guard position >= 0, position < chars.count else { return nil }
                typed = chars[position]
            }
            keys.append(ReplayKey(position: position, typed: typed!, offsetMs: offsets[index]))
            expected = position + 1
        }
        self.text = text
        self.keys = keys
    }

    private func putVarint(_ value: UInt64, _ data: inout Data) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0
        init(bytes: [UInt8]) { self.bytes = bytes }
        mutating func byte() -> UInt8? {
            guard index < bytes.count else { return nil }
            defer { index += 1 }
            return bytes[index]
        }
        mutating func take(_ n: Int) -> [UInt8]? {
            guard n >= 0, n <= bytes.count - index else { return nil }
            defer { index += n }
            return Array(bytes[index..<index + n])
        }
        mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while let b = byte() {
                guard shift < 64 else { return nil }
                result |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }
    }
}
