import Foundation

/// Текст занятия «Слова с ошибками».
public enum ErrorWordsText {
    public static let minimumEntries = 5

    /// Записи, целиком состоящие из разрешённых букв (пробел, дефис и апостроф не буквы и разрешены); `nil` — любые.
    public static func eligible(entries: [ErrorWordEntry], allowed: Set<Character>?) -> [ErrorWordEntry] {
        let allowedLower = allowed.map { Set($0.flatMap { $0.lowercased() }) }
        return entries.filter { entry in
            guard let allowedLower else { return true }
            return entry.text.allSatisfy { $0 == " " || $0 == "-" || $0 == "'" || $0 == "\u{2019}" || allowedLower.contains($0) }
        }
    }

    /// Слова и фразы из списка, по весу ошибок и давности, каждое 2–3 раза вперемешку.
    /// `nil`, если подходящих записей меньше `minimumEntries`.
    public static func make(
        entries: [ErrorWordEntry], allowed: Set<Character>?, targetChars: Int, seed: UInt64
    ) -> String? {
        let eligible = Self.eligible(entries: entries, allowed: allowed)
        .sorted { $0.text != $1.text ? $0.text < $1.text : !$0.isPhrase && $1.isPhrase }
        guard eligible.count >= minimumEntries else { return nil }

        var rng = SeededGenerator(seed: seed)
        // Давность: 0 у самой старой записи, 1 у самой новой.
        let byDate = eligible.sorted { $0.lastSeen < $1.lastSeen }
        var recency: [Int: Double] = [:]
        for (rank, entry) in byDate.enumerated() {
            let i = eligible.firstIndex(of: entry) ?? 0
            recency[i] = byDate.count > 1 ? Double(rank) / Double(byDate.count - 1) : 1
        }
        // Взвешенный выбор без возвращения: ключ u^(1/w), больше — раньше.
        var keyed: [(Int, Double)] = eligible.indices.map { i in
            let w = Double(max(1, eligible[i].errors)) + (recency[i] ?? 0)
            let u = max(Double.random(in: 0..<1, using: &rng), 1e-12)
            return (i, pow(u, 1 / w))
        }
        keyed.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }

        var tokens: [String] = []
        var length = 0
        for (i, _) in keyed {
            if length >= targetChars { break }
            let reps = Int.random(in: 2...3, using: &rng)
            for _ in 0..<reps { tokens.append(eligible[i].text) }
            length += (eligible[i].text.count + 1) * reps
        }
        tokens.shuffle(using: &rng)
        return tokens.joined(separator: " ")
    }
}
