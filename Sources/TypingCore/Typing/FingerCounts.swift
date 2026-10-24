import Foundation

/// Словарь «палец → число» для хранения в `Data` (поля сессии `fingerPresses` / `fingerErrors`, фаза 5):
/// JSON-объект, ключи — `Finger.rawValue`, отсортированы, поэтому одинаковые словари дают одинаковые байты.
public enum FingerCounts {
    public static func data(_ counts: [Finger: Int]) -> Data {
        data(raw: Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }))
    }

    public static func data(raw: [String: Int]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Словарь строк и чисел кодируется всегда.
        return (try? encoder.encode(raw)) ?? Data("{}".utf8)
    }

    /// nil для nil и нечитаемых данных; незнакомые ключи пропускаются.
    public static func counts(_ data: Data?) -> [Finger: Int]? {
        guard let raw = raw(data) else { return nil }
        var result: [Finger: Int] = [:]
        for (key, value) in raw {
            if let finger = Finger(rawValue: key) { result[finger] = value }
        }
        return result
    }

    /// Как записано (для архива), в том числе незнакомые ключи; nil для nil и нечитаемых данных.
    public static func raw(_ data: Data?) -> [String: Int]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: Int].self, from: data)
    }
}
