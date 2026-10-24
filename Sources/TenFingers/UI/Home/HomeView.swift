import SwiftData
import SwiftUI
import TypingCore

/// Главная: данные читаются из базы при появлении, смене настроек и раз в минуту (сменился логический день);
/// сама раскладка — в `HomeContent`.
struct HomeView: View {
    let start: (RunKind) -> Void
    let navigate: (SidebarItem) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ContentLibrary.self) private var library
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var targetCpm = SettingsDefault.adaptiveTargetCpm
    @Query private var progress: [LessonProgress]
    @State private var data: HomeData?
    /// Последнее чтение из базы не удалось.
    @State private var loadFailed = false

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }

    var body: some View {
        Group {
            if let data {
                HomeContent(data: data, continueInfo: continueInfo, unit: SpeedUnit(rawValue: speedUnit) ?? .cpm,
                            startLesson: { start(.lesson($0)) },
                            openTraining: { navigate(.training) },
                            startWeakSpots: { start(.weakSpots(TrainingRun(language: language))) },
                            openPractice: { navigate(.practice) })
            } else if loadFailed {
                LoadErrorView(retry: reload)
            } else {
                Color.clear
            }
        }
        .onAppear(perform: reload)
        .onChange(of: activeLanguage) { reload() }
        .onChange(of: dayStartHour) { reload() }
        .onChange(of: dailyGoal) { reload() }
        .onChange(of: targetCpm) { reload() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in reload() }
    }

    private var continueInfo: ContinueInfo? {
        guard let course = library.courses[language] else { return nil }
        let passed = Set(progress.filter { $0.language == language.rawValue && $0.passedAt != nil }.map(\.lessonId))
        let percent = Int(course.completion(passed: passed) * 100)
        guard let lesson = course.nextLesson(passed: passed) else {
            return ContinueInfo(lessonTitle: nil, stageTitle: "", percent: percent, lessonRun: nil)
        }
        return ContinueInfo(lessonTitle: lesson.localizedTitle,
                            stageTitle: course.stage(of: lesson.id)?.localizedTitle ?? "", percent: percent,
                            lessonRun: LessonRun(language: language, lessonId: lesson.id))
    }

    /// Дни читаются один раз (из них и серия, и время), сессии — только за неделю, дата первого занятия —
    /// отдельным запросом на одну запись.
    private func reload() {
        let snapshot = ProgressSnapshot(context: modelContext)
        let today = LogicalDay.key(for: .now, dayStartHour: dayStartHour)
        do {
            let days = try snapshot.dayActivities()
            let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: Double(dailyGoal) * 60)
            let sessions = try snapshot.sessionSummaries(fromDay: StreakCalculator.dayKey(today, offset: -6))
            let first = try snapshot.firstSessionDate()
            let training = trainingSnapshot()
            data = HomeData.make(language: language, streak: streak, days: days, sessions: sessions, today: today,
                                 goalMinutes: dailyGoal, focus: training?.letters.first(where: \.isFocus)?.character,
                                 weakKeys: training?.weakKeys ?? [], canStartWeakSpots: training?.canStartWeakSpots ?? false,
                                 firstSessionDate: first)
            loadFailed = false
        } catch {
            data = nil
            loadFailed = true
        }
    }

    private func trainingSnapshot() -> TrainingSnapshot? {
        let reader = StatsReader(context: modelContext)
        guard let count = try? reader.unlockedCount(language: language),
              let keys = try? reader.keyMastery(language: language),
              let bigrams = try? reader.bigramMastery(language: language),
              let open = try? reader.openLetters(language: language, course: library.courses[language])
        else { return nil }
        return TrainingSnapshot.make(language: language, unlockedCount: count, keyMastery: keys,
                                     bigramMastery: bigrams, targetCpm: Double(targetCpm), openLetters: open)
    }
}

/// Раскладка главной сверху вниз: серия, неделя, метрики, продолжение курса, быстрые ссылки.
struct HomeContent: View {
    let data: HomeData
    let continueInfo: ContinueInfo?
    let unit: SpeedUnit
    let startLesson: (LessonRun) -> Void
    let openTraining: () -> Void
    let startWeakSpots: () -> Void
    let openPractice: () -> Void

    var body: some View {
        ScrollView { column }
            .scrollContentBackground(.hidden)
    }

    /// Содержимое без прокрутки (его же рисует проверка через `ImageRenderer`: прокрутку тот не отрисовывает).
    var column: some View {
        VStack(alignment: .leading, spacing: 16) {
            StreakHeader(streak: data.streak, todaySeconds: data.todaySeconds, goalMinutes: data.goalMinutes)
            WeekStrip(days: data.week)
            MetricsCard(data: data, unit: unit)
            if let continueInfo { ContinueCard(info: continueInfo, start: startLesson) }
            QuickLinks(data: data, openTraining: openTraining, startWeakSpots: startWeakSpots,
                       openPractice: openPractice)
        }
        .padding(24)
        .frame(maxWidth: 820, alignment: .leading)
    }
}
