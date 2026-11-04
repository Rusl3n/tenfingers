import Foundation
import os
import SwiftData
import TypingCore
import WidgetKit
import WidgetSnapshot

private let widgetLog = Logger(subsystem: "local.tenfingers", category: "widget")

/// Собирает снимок для виджета из тех же источников, что «Главная» (`HomeData`, серия и «Искра», цель дня,
/// `ContinueInfo`, полученные ачивки), и атомарно пишет его в `widget.json` рядом с базой.
@MainActor
enum WidgetSnapshotWriter {
    /// Сколько последних ачивок попадает в файл.
    static let achievementLimit = 5

    /// Логический день и момент последней успешной записи в этом запуске: по ним `WidgetRefreshWatcher` решает,
    /// пора ли писать снова.
    static private(set) var lastWrittenDay: String?
    static private(set) var lastWrittenAt: Date?

    /// Папка данных приложения: там же лежит база.
    static var defaultDirectory: URL { ModelStore.defaultStoreURL.deletingLastPathComponent() }

    /// Код языка интерфейса приложения (`ru` или `en`): тот, на котором показан интерфейс, а не язык системы.
    static func interfaceLanguageCode(bundle: Bundle = .main) -> String {
        Formatting.interfaceLocale(bundle: bundle).identifier.hasPrefix("ru") ? "ru" : "en"
    }

    /// `courses` и `language` заданы по умолчанию для приложения; тесты подставляют свои.
    static func makeSnapshot(context: ModelContext, defaults: UserDefaults, now: Date,
                             courses: [Language: Course] = AchievementService.bundledCourses,
                             language: String = WidgetSnapshotWriter.interfaceLanguageCode(),
                             calendar: Calendar = .current) throws -> WidgetSnapshot {
        let dayStartHour = StoredSettings.dayStartHour(defaults)
        let today = LogicalDay.key(for: now, dayStartHour: dayStartHour, calendar: calendar)
        let goalMinutes = Int(StoredSettings.dailyGoalSeconds(defaults) / 60)
        let adultHumor = StoredSettings.adultHumor(defaults)
        let courseLanguage = defaults.string(forKey: SettingsKey.activeLanguage).flatMap(Language.init(rawValue:)) ?? .ru

        let progress = ProgressSnapshot(context: context)
        let days = try progress.dayActivities()
        let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: Double(goalMinutes) * 60)
        // Как на «Главной»: огонь и цель дня читаются из `HomeData`, «Искра» — из `StreakHeader.spark`.
        let home = HomeData.make(language: courseLanguage, streak: streak, days: days, sessions: [], today: today,
                                 goalMinutes: goalMinutes, firstWeekday: StoredSettings.firstWeekday(defaults))
        let spark = StreakHeader.spark(home.streak)

        return WidgetSnapshot(
            writtenAt: now, logicalDay: today, dayStartHour: dayStartHour, language: language, adultHumor: adultHumor,
            fire: .init(days: home.streak.current, today: fireToday(home.streak.today), freezes: home.streak.freezes),
            spark: .init(days: spark?.days ?? 0, today: spark?.isLitToday ?? false),
            goal: .init(goalMinutes: home.goalMinutes, doneMinutes: Int(home.todaySeconds / 60)),
            next: try next(progress: progress, context: context, course: courses[courseLanguage], language: courseLanguage),
            achievements: try latestAchievements(context: context))
    }

    private static func fireToday(_ status: DayStatus) -> WidgetSnapshot.FireToday {
        switch status {
        case .full: .full
        case .half: .half
        default: .none
        }
    }

    /// Урок «Продолжить» так же, как карточка на «Главной»; курс пройден или не загружен — `nil`.
    private static func next(progress: ProgressSnapshot, context: ModelContext, course: Course?,
                             language: Language) throws -> WidgetSnapshot.Next? {
        guard let course else { return nil }
        let code = language.rawValue
        let records = try context.fetch(FetchDescriptor<LessonProgress>(predicate: #Predicate { $0.language == code }))
        let passed = Set(records.filter { $0.passedAt != nil }.map(\.lessonId))
        let checkStars = course.edition >= 2 ? try progress.stageCheckStars(course: course) : [:]
        guard let title = ContinueInfo.make(course: course, language: language, passed: passed,
                                            checkStars: checkStars)?.lessonTitle else { return nil }
        return .init(title: title, courseLanguage: code)
    }

    /// Только полученные, новые первыми (при равных датах — более поздняя в каталоге). Скрытые «взрослые» тоже идут
    /// в файл с флагом `adult`: показывать их или нет, решает виджет по своей настройке.
    private static func latestAchievements(context: ModelContext) throws -> [WidgetSnapshot.Item] {
        latestAchievements(from: try context.fetch(FetchDescriptor<AchievementRecord>()))
    }

    /// Дубли одной ачивки убираются после сортировки по дате: побеждает более новая запись.
    static func latestAchievements(from allRecords: [AchievementRecord]) -> [WidgetSnapshot.Item] {
        let catalog = AchievementCatalog.all
        let position = Dictionary(catalog.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let records = allRecords
            .filter { position[$0.achievementId] != nil }
            .sorted { (lhs, rhs) in
                (lhs.unlockedAt, position[lhs.achievementId] ?? 0) > (rhs.unlockedAt, position[rhs.achievementId] ?? 0)
            }
            .filter { seen.insert($0.achievementId).inserted }
        return records.prefix(achievementLimit).compactMap { record in
            position[record.achievementId].map { index in
                let achievement = catalog[index]
                return WidgetSnapshot.Item(id: achievement.id, title: achievement.title, symbol: achievement.icon,
                                           date: record.unlockedAt, adult: achievement.adult)
            }
        }
    }

    /// Атомарная запись: временный файл рядом, затем замена. Временных файлов после записи не остаётся.
    static func write(_ snapshot: WidgetSnapshot, to directory: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appending(path: WidgetSnapshot.fileName)
        let temporary = directory.appending(path: ".\(WidgetSnapshot.fileName).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporary) }
        try snapshot.encoded().write(to: temporary)
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: target)
        }
    }

    /// Собрать, записать и попросить виджеты перечитать файл. Ошибка только в журнал: приложению она не мешает.
    /// В тестах не вызывается с реальной папкой.
    static func refresh(context: ModelContext, defaults: UserDefaults = .standard, now: Date = .now,
                        directory: URL = WidgetSnapshotWriter.defaultDirectory) {
        do {
            let snapshot = try makeSnapshot(context: context, defaults: defaults, now: now)
            try write(snapshot, to: directory)
            lastWrittenDay = snapshot.logicalDay
            lastWrittenAt = now
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            widgetLog.error("Widget snapshot not written: \(String(describing: error), privacy: .public)")
        }
    }
}
