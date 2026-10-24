import Foundation

extension Notification.Name {
    /// Появилось отложенное объявление «Полный огонь» (`FullDayPending.mark`): главная, если она сейчас на экране,
    /// объявляет его сразу.
    static let fullDayPending = Notification.Name("local.tenfingers.fullDayPending")
    /// Прогресс заменён загрузкой из файла (`ProgressImporter`): кэш фактов ачивок сбрасывается, ачивки
    /// проверяются заново (в архиве старого поколения их нет).
    static let progressReplaced = Notification.Name("local.tenfingers.progressReplaced")
}

/// Объявление «Полный огонь», которое не удалось показать сразу: день стал полным при выходе без кнопки
/// (меню, закрытие окна, выход из приложения), когда ни тоста, ни звука уже не показать.
/// Хранится в `UserDefaults` и переживает закрытие окна; главная объявляет его при следующем показе.
/// Это не настройка: в файл прогресса не попадает.
struct FullDayPending {
    static let key = "pendingFullDayAnnouncement"

    var defaults: UserDefaults = .standard

    /// Запоминает логический день, ставший полным.
    func mark(day: String) {
        defaults.set(day, forKey: Self.key)
    }

    /// `true`, если ожидает объявление именно за `today`. Запись при этом удаляется; устаревшая
    /// (за другой день) удаляется без объявления.
    func take(today: String) -> Bool {
        guard let day = defaults.string(forKey: Self.key) else { return false }
        defaults.removeObject(forKey: Self.key)
        return day == today
    }
}
