import Foundation

/// Отбор замеров: по каждому варианту хранится первый (самый ранний) и последние 5.
public enum MeasureRetention {
    public static let recentCount = 5

    /// Индексы элементов, которые остаются.
    public static func keepIndices<T>(
        _ items: [T], variant: (T) -> MeasureVariant, date: (T) -> Date
    ) -> Set<Int> {
        var byVariant: [MeasureVariant: [Int]] = [:]
        for index in items.indices { byVariant[variant(items[index]), default: []].append(index) }
        var kept = Set<Int>()
        for indices in byVariant.values {
            let ordered = indices.sorted {
                let a = date(items[$0]), b = date(items[$1])
                return a != b ? a < b : $0 < $1
            }
            if let first = ordered.first { kept.insert(first) }
            kept.formUnion(ordered.suffix(recentCount))
        }
        return kept
    }

    /// Что оставить (порядок исходный).
    public static func keep<T>(_ items: [T], variant: (T) -> MeasureVariant, date: (T) -> Date) -> [T] {
        let kept = keepIndices(items, variant: variant, date: date)
        return items.indices.filter(kept.contains).map { items[$0] }
    }

    /// Что удалить (порядок исходный).
    public static func discard<T>(_ items: [T], variant: (T) -> MeasureVariant, date: (T) -> Date) -> [T] {
        let kept = keepIndices(items, variant: variant, date: date)
        return items.indices.filter { !kept.contains($0) }.map { items[$0] }
    }
}
