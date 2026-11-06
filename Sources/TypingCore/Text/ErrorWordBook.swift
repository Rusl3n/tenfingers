import Foundation

/// Запись списка «слов с ошибками» (один язык).
public struct ErrorWordEntry: Equatable, Sendable {
    public var text: String
    public var isPhrase: Bool
    public var errors: Int
    public var cleanStreak: Int
    public var firstSeen: Date
    public var lastSeen: Date

    public init(text: String, isPhrase: Bool, errors: Int, cleanStreak: Int, firstSeen: Date, lastSeen: Date) {
        self.text = text
        self.isPhrase = isPhrase
        self.errors = errors
        self.cleanStreak = cleanStreak
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// Чистое обновление списка слов с ошибками.
public enum ErrorWordBook {
    public static let limit = 200
    public static let fixedAfter = 3

    /// Возвращает новый список и число исправленных слов (фразы в число не входят).
    public static func apply(
        _ hits: [WordHit], to entries: [ErrorWordEntry], now: Date
    ) -> (entries: [ErrorWordEntry], fixed: Int) {
        var list = entries
        var fixed = 0
        var touched = Set<String>()
        for hit in hits {
            let key = hit.text.lowercased()
            touched.insert((hit.isPhrase ? "p:" : "w:") + key)
            let idx = list.firstIndex { $0.text == key && $0.isPhrase == hit.isPhrase }
            if hit.hadError {
                if let idx {
                    list[idx].errors += 1
                    list[idx].cleanStreak = 0
                    list[idx].lastSeen = now
                } else {
                    list.append(ErrorWordEntry(
                        text: key, isPhrase: hit.isPhrase, errors: 1, cleanStreak: 0,
                        firstSeen: now, lastSeen: now))
                }
            } else if let idx {
                // Хиты обрабатываются по порядку, поэтому каждое чистое вхождение продвигает слово.
                list[idx].cleanStreak += 1
                if list[idx].cleanStreak >= fixedAfter {
                    if !list[idx].isPhrase { fixed += 1 }
                    list.remove(at: idx)
                }
            }
        }
        while list.count > limit {
            // Затронутые этим вызовом записи вытесняем, только если больше некого (кривые часы).
            let spare = list.indices.filter { !touched.contains((list[$0].isPhrase ? "p:" : "w:") + list[$0].text) }
            let pool = spare.isEmpty ? Array(list.indices) : spare
            guard let oldest = pool.min(by: { list[$0].lastSeen < list[$1].lastSeen }) else { break }
            list.remove(at: oldest)
        }
        return (list, fixed)
    }
}
