import Foundation
import SwiftData

/// Позиция в своём тексте. Меняется только внутри транзакции записи (`ExerciseCoordinator.recordFinish(extra:)`
/// или `commitStandalone`), поэтому позиция и запись о сессии сохраняются или откатываются вместе.
enum CustomTextProgress {
    /// Ставит позицию текста с этим `id`. Текст мог быть удалён, пока запуск был скрыт: тогда двигать нечего.
    @MainActor
    static func set(_ offset: Int, forTextWithId id: UUID, recorder: ResultRecorder) throws {
        let descriptor = FetchDescriptor<CustomText>(predicate: #Predicate { $0.id == id })
        if let text = try recorder.context.fetch(descriptor).first { recorder.advanceCustomText(text, to: offset) }
    }
}

/// Чтение текстового файла: сначала UTF-16 без BOM (его байты часто проходят как «UTF-8» из управляющих
/// символов), затем система сама определяет кодировку (BOM, метаданные), затем UTF-16 с BOM, UTF-8
/// и Windows-1251 (старые русские тексты). Результат, где больше 5% управляющих символов, — не текст.
enum TextFileDecoder {
    static let maxControlShare = 0.05
    /// Доля «старших» байтов UTF-16 на чётных или нечётных позициях, начиная с которой файл считается UTF-16.
    static let utf16HighByteShare = 0.3

    static func decode(_ data: Data) -> String? {
        if let text = bomlessUTF16(data) { return text }
        // `.utf16` без BOM принял бы любые байты чётной длины за иероглифы, поэтому только с BOM.
        let encodings: [String.Encoding] = hasUTF16BOM(data) ? [.utf16] : [.utf8, .windowsCP1251]
        for encoding in encodings {
            if let text = String(data: data, encoding: encoding), isPlainText(text) { return text }
        }
        return nil
    }

    static func read(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = bomlessUTF16(data) { return text }
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding), isPlainText(text) { return text }
        return decode(data)
    }

    /// UTF-16 без BOM: старший байт латиницы — 0x00, кириллицы — 0x04. Если такие байты занимают
    /// не меньше 30% одной из позиций (нечётных — little-endian, чётных — big-endian), это UTF-16.
    static func bomlessUTF16(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2, !hasUTF16BOM(data) else { return nil }
        let pairs = bytes.count / 2
        var even = 0, odd = 0
        for index in 0..<pairs {
            if isUTF16HighByte(bytes[2 * index]) { even += 1 }
            if isUTF16HighByte(bytes[2 * index + 1]) { odd += 1 }
        }
        let threshold = utf16HighByteShare * Double(pairs)
        let encoding: String.Encoding
        if Double(odd) >= threshold, odd > even {
            encoding = .utf16LittleEndian
        } else if Double(even) >= threshold, even > odd {
            encoding = .utf16BigEndian
        } else {
            return nil
        }
        guard let text = String(data: Data(bytes.prefix(pairs * 2)), encoding: encoding), isPlainText(text)
        else { return nil }
        return text
    }

    /// Не больше 5% управляющих символов, не считая перевода строки, возврата каретки и табуляции.
    static func isPlainText(_ text: String) -> Bool {
        var total = 0, control = 0
        for scalar in text.unicodeScalars {
            total += 1
            if scalar.properties.generalCategory == .control, !["\n", "\r", "\t"].contains(scalar) { control += 1 }
        }
        return total == 0 || Double(control) / Double(total) <= maxControlShare
    }

    private static func hasUTF16BOM(_ data: Data) -> Bool {
        data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
    }

    private static func isUTF16HighByte(_ byte: UInt8) -> Bool {
        byte == 0x00 || byte == 0x04
    }
}
