import Foundation
import Testing

private let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func strings(_ lang: String) throws -> [String: String] {
    let url = root.appendingPathComponent("Localization/\(lang).lproj/Localizable.strings")
    let data = try Data(contentsOf: url)
    return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
}

private func hasCyrillic(_ s: String) -> Bool { s.unicodeScalars.contains { (0x400...0x4FF).contains($0.value) } }

/// Приводит интерполяции Swift и форматные спецификаторы к общему виду, чтобы сравнивать литералы с ключами.
private func normalize(_ s: String) -> String {
    var r = s.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "∗", options: .regularExpression)
    r = r.replacingOccurrences(of: #"%(\d+\$)?(lld|ld|d|@|lf|f|\.\d+f)"#, with: "∗", options: .regularExpression)
    // Знак процента в литерале `String(localized:)` попадает в ключ удвоенным: «+\(n)%» → «+%lld%%».
    return r.replacingOccurrences(of: "%%", with: "%")
}

@Test func englishHasNoCyrillicAndRussianKeysMatch() throws {
    let en = try strings("en"), ru = try strings("ru")
    #expect(en.count > 80)
    #expect(Set(en.keys) == Set(ru.keys))
    for (key, value) in en { #expect(!hasCyrillic(value), "en: «\(key)» не переведено") }
}

@Test func everyCyrillicLiteralInAppHasTranslation() throws {
    let keys = Set(try strings("en").keys.map(normalize))
    let sources = root.appendingPathComponent("Sources/TenFingers")
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
    var missing: [String] = []
    for file in files {
        for line in try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines) {
            let code = line.components(separatedBy: "//").first ?? ""
            for match in literal.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let text = String(code[Range(match.range(at: 1), in: code)!])
                if hasCyrillic(text), !keys.contains(normalize(text)) { missing.append("\(file.lastPathComponent): \(text)") }
            }
        }
    }
    #expect(missing.isEmpty, "Нет перевода:\n\(missing.joined(separator: "\n"))")
}
