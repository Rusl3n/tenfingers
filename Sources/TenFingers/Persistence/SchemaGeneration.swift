import Foundation

/// Монотонный номер поколения схемы, записанный рядом с базой (`<база>.generation`).
/// Защита по именам сущностей ловит только новые модели; откат на версию, которая не знает
/// нового поля существующей модели, она не видит. Маркер ловит любое изменение моделей.
enum SchemaGeneration {
    /// Увеличивать на 1 при КАЖДОМ изменении моделей (новая модель или новое поле) — в том же коммите
    /// (спецификация §20). 1 — схема фазы 2 (до `AdaptiveUnlock` и `SessionRecord.source`),
    /// 2 — схема начала фазы 3, 3 — фаза 4: новая модель `AchievementRecord`, 4 — фаза 5: поля `fingerPresses`,
    /// `fingerErrors`, `yoPresses` в `SessionRecord`, 5 — фаза 5: цель дня `DayRecord.goalSeconds`, 6 — фаза 6a: модель
    /// `AchievementGrant`, поля `stepIndex`, `planSlot`, `textTraits` в `SessionRecord`, 7 — игра «Ритм»: модель
    /// `RhythmResult`, 8 — подфаза 8a: необязательное поле `SessionRecord.speedSegments` (текущая `SchemaV1`).
    static let current = 8

    /// Файл-маркер лежит в той же папке, что и база, и попадает в резервные копии вместе с ней.
    static func markerURL(forStore storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appending(path: storeURL.lastPathComponent + ".generation")
    }

    /// Файл маркера есть, но прочитать из него номер поколения нельзя (не текст, не число, отрицательное число,
    /// папка вместо файла). Базу в таком случае не открываем: неизвестно, какая версия её записала.
    struct UnreadableMarker: Error, Equatable {}

    /// Поколение, записанное рядом с базой. `nil` — файла нет (база создана до введения маркера или ещё не создана).
    /// Файл есть, но не читается как неотрицательное число — бросает `UnreadableMarker` (закрыто по умолчанию).
    static func read(at storeURL: URL) throws -> Int? {
        let url = markerURL(forStore: storeURL)
        guard (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil else { return nil }
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              value >= 0 else { throw UnreadableMarker() }
        return value
    }

    static func write(_ generation: Int, at storeURL: URL) throws {
        try "\(generation)\n".write(to: markerURL(forStore: storeURL), atomically: true, encoding: .utf8)
    }

    /// Открыть можно, если маркера нет или он не новее текущего поколения.
    static func canOpen(stored: Int?, current: Int) -> Bool {
        guard let stored else { return true }
        return stored <= current
    }
}
