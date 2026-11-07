import Foundation

/// Красный кружок «есть новое» на вкладках «Главной». У вкладки есть «отпечаток» содержимого (строка); последний
/// увиденный хранится в `UserDefaults` одним словарём (`SettingsKey.homeTabSeen`, вне архива прогресса). Кружок горит
/// у невыбранной вкладки, чей отпечаток не равен увиденному; показ вкладки записывает её отпечаток как увиденный.
/// Первый запуск (словаря ещё нет): ничего не горит, текущие отпечатки записываются как увиденные.
enum HomeTabNews {
    /// Отпечатки вкладок; у «Тренировки и практики» отпечатка нет (кружка нет), у недоступной вкладки — тоже.
    /// План — логический день (ход выполнения внутри дня кружок не зажигает); испытания — периоды, их испытания и
    /// выполненные (`ChallengesCardModel.fingerprint`); курс — id следующего урока или проверки.
    static func fingerprints(plan: DayPlanCardModel?, challenges: ChallengesCardModel?,
                             course: ContinueInfo?) -> [HomeTab: String] {
        var result: [HomeTab: String] = [:]
        if let plan { result[.plan] = plan.day }
        if let challenges { result[.challenges] = challenges.fingerprint }
        if let course { result[.course] = course.lessonRun?.lessonId ?? "completed" }
        // Одноразовая новость 2.9.0 — «Замер скорости» на вкладке тренировки. Отпечаток постоянный: у тех, кто уже
        // открывал «Главную» прежних версий, вкладка не записана и загорается один раз; на первом запуске (словаря
        // ещё нет) он записывается сразу как увиденный. Пока нет прочего содержимого, его тоже нет: иначе первая
        // запись оставила бы остальные вкладки незаписанными, и они загорелись бы.
        if !result.isEmpty { result[.quick] = measureNews }
        return result
    }

    /// Отпечаток новости о замере скорости (2.9.0).
    static let measureNews = "measure-2.9.0"

    /// Новость вкладки ещё не видна пользователю: словарь уже есть (не первый запуск), а вкладка записана иначе.
    static func isPending(_ tab: HomeTab, fingerprints: [HomeTab: String], seen: [String: String]?) -> Bool {
        guard let seen, let fingerprint = fingerprints[tab] else { return false }
        return seen[tab.rawValue] != fingerprint
    }

    /// Вкладки с кружком; `seen == nil` — первый запуск.
    static func dots(fingerprints: [HomeTab: String], seen: [String: String]?, selected: HomeTab) -> Set<HomeTab> {
        guard let seen else { return [] }
        return Set(fingerprints.compactMap { tab, fingerprint in
            tab != selected && seen[tab.rawValue] != fingerprint ? tab : nil
        })
    }

    static func seen(_ defaults: UserDefaults = ProfileDefaults.current) -> [String: String]? {
        defaults.dictionary(forKey: SettingsKey.homeTabSeen) as? [String: String]
    }

    /// Вкладка показана: её отпечаток записывается как увиденный; на первом запуске записываются все. Возвращает
    /// увиденное после записи.
    @discardableResult
    static func markSeen(selected: HomeTab, fingerprints: [HomeTab: String],
                         _ defaults: UserDefaults = ProfileDefaults.current) -> [String: String] {
        let stored = seen(defaults)
        // Данных ещё нет: пустой словарь не записываем, иначе появившиеся позже вкладки сразу загорятся.
        if stored == nil, fingerprints.isEmpty { return [:] }
        var updated = stored ?? [:]
        if stored == nil {
            for (tab, fingerprint) in fingerprints { updated[tab.rawValue] = fingerprint }
        } else if let fingerprint = fingerprints[selected] {
            updated[selected.rawValue] = fingerprint
        }
        if stored == nil || updated != stored { defaults.set(updated, forKey: SettingsKey.homeTabSeen) }
        return updated
    }
}
