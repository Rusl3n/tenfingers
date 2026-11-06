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
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(KeyboardLayoutService.self) private var layout
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.trainingLetters) private var trainingLetters = SettingsDefault.trainingLetters
    @AppStorage(SettingsKey.firstWeekday) private var firstWeekday = SettingsDefault.firstWeekday
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = SettingsDefault.dailyGoalMinutes
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var targetCpm = SettingsDefault.adaptiveTargetCpm
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @AppStorage(SettingsKey.profileNickname) private var nickname = ""
    @Query private var progress: [LessonProgress]
    @Query(sort: \AchievementRecord.unlockedAt, order: .reverse) private var achievementRecords: [AchievementRecord]
    @State private var data: HomeData?
    /// Звёзды проверок этапов курса (гейт этапов): читаются вместе с остальным в `reload`.
    @State private var checkStars: [String: Int] = [:]
    /// Последнее чтение из базы не удалось.
    @State private var loadFailed = false
    /// Открытая карточка «Мой прогресс».
    @State private var share: ShareCard?
    /// План на сегодня (пересобирается в каждом `reload`); `nil` — прочитать не удалось: карточка «Продолжить курс».
    @State private var plan: DayPlan?
    /// Снимок года (уровень, испытания); `nil` — прочитать не удалось: главная без уровня и «Испытаний».
    @State private var year: YearState?
    /// Часы Mac для приветствия: обновляются тем же минутным таймером, что и данные (`reload`).
    @State private var now = Date()

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }

    var body: some View {
        Group {
            if let data {
                HomeContent(data: data, greeting: GreetingLine.text(part: GreetingLine.part(at: now), nickname: nickname),
                            continueInfo: continueInfo, unit: SpeedUnit(rawValue: speedUnit) ?? .cpm,
                            level: year.map { LevelLine.make($0) },
                            challenges: year.flatMap {
                                ChallengesCardModel.make(week: $0.week, month: $0.month, today: $0.today,
                                                         unit: SpeedUnit(rawValue: speedUnit) ?? .cpm)
                            },
                            dayPlan: plan.map {
                                DayPlanCardModel.make(plan: $0, course: library.courses[language],
                                                      canContinue: planRun(for: $0) != nil)
                            },
                            startPlan: { if let plan, let run = planRun(for: plan) { start(run) } },
                            startLesson: { start(.lesson($0)) },
                            openTraining: { navigate(.training) },
                            startWeakSpots: { start(.weakSpots(TrainingRun(language: language))) },
                            startErrorWords: { start(.errorWords(TrainingRun(language: language))) },
                            openPractice: { navigate(.practice) },
                            latestAchievement: latestAchievement,
                            openAchievements: { navigate(.achievements) },
                            shareProgress: openProgressCard)
            } else if loadFailed {
                LoadErrorView(retry: reload)
            } else {
                Color.clear
            }
        }
        .shareSheet($share)
        .onAppear {
            reload()
            announcePendingFullDay()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fullDayPending)) { _ in
            reload()
            announcePendingFullDay()
        }
        .onChange(of: activeLanguage) { reload() }
        .onChange(of: dayStartHour) { reload() }
        .onChange(of: firstWeekday) { reload() }
        .onChange(of: dailyGoal) { reload() }
        .onChange(of: targetCpm) { reload() }
        .onChange(of: trainingLetters) { reload() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in reload() }
    }

    /// «Поделиться» у серии: карточка «Мой прогресс» из свежих данных базы; ошибка чтения — тост.
    private func openProgressCard() {
        share = ShareCard.openProgress(context: modelContext, goalSeconds: Double(dailyGoal) * 60,
                                       dayStartHour: dayStartHour, toasts: toasts)
    }

    /// День стал полным при выходе без кнопки (меню, закрытие окна): тост и звук серии при показе главной
    /// (`FullDayPending`).
    private func announcePendingFullDay() {
        guard FullDayPending().take(today: LogicalDay.key(for: .now, dayStartHour: dayStartHour)) else { return }
        toasts.showFullFlame()
        sound.play(.streak)
    }

    private var planLoader: DayPlanLoader {
        DayPlanLoader(context: modelContext, library: library, settings: .stored(layout: layout))
    }

    /// Запуск первого незасчитанного пункта плана; `nil` — план выполнен или запускать нечего.
    private func planRun(for plan: DayPlan) -> RunKind? {
        plan.next.flatMap { planLoader.run(for: $0, language: language) }
    }

    /// Последняя полученная видимая ачивка (скрытые «взрослые» при выключенном юморе не в счёт).
    private var latestAchievement: AchievementEntry? {
        AchievementsListing.latest(catalog: AchievementCatalog.all,
                                   earned: achievementRecords.map(StoredAchievement.init), adultHumor: adultHumor)
    }

    private var continueInfo: ContinueInfo? {
        guard let course = library.courses[language] else { return nil }
        let passed = Set(progress.filter { $0.language == language.rawValue && $0.passedAt != nil }.map(\.lessonId))
        return ContinueInfo.make(course: course, language: language, passed: passed, checkStars: checkStars)
    }

    /// Дни читаются один раз (из них и серия, и время), сессии — только за неделю, дата первого занятия —
    /// отдельным запросом на одну запись.
    private func reload() {
        now = .now
        let snapshot = ProgressSnapshot(context: modelContext)
        let today = LogicalDay.key(for: .now, dayStartHour: dayStartHour)
        do {
            let days = try snapshot.dayActivities()
            let streak = StreakCalculator.summarize(days: days, today: today, goalSeconds: Double(dailyGoal) * 60)
            let sessions = try snapshot.sessionSummaries(fromDay: StreakCalculator.dayKey(today, offset: -6))
            let first = try snapshot.firstSessionDate()
            let training = trainingSnapshot()
            // Звёзды проверок нужны только гейту издания 2; прежний курс порога не знает.
            if let course = library.courses[language], course.edition >= 2 {
                checkStars = try snapshot.stageCheckStars(course: course)
            } else {
                checkStars = [:]
            }
            data = HomeData.make(language: language, streak: streak, days: days, sessions: sessions, today: today,
                                 goalMinutes: dailyGoal, focus: training?.letters.first(where: \.isFocus)?.character,
                                 weakKeys: training?.weakKeys ?? [], canStartWeakSpots: training?.canStartWeakSpots ?? false,
                                 firstSessionDate: first, firstWeekday: StoredSettings.firstWeekday(),
                                 errorWords: errorWordsModel())
            loadFailed = false
            // План — отдельно: его ошибка не прячет главную, вместо карточки плана — «Продолжить курс».
            plan = try? planLoader.plan(language: language, today: today)
            // Год — тоже отдельно: кэш снимка не пересчитывает опыт, пока история и день те же.
            year = try? YearLoader(context: modelContext).state()
            if plan?.isDone == true { toasts.announcePlanDone(today: today) }
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
              let open = try? reader.openLetters(language: language, course: library.courses[language],
                                                 legacy: library.legacyCourses[language])
        else { return nil }
        return TrainingSnapshot.make(language: language, unlockedCount: count, keyMastery: keys,
                                     bigramMastery: bigrams, targetCpm: Double(targetCpm),
                                     openLetters: trainingLettersSetting.letters(open: open, language: language))
    }

    private var trainingLettersSetting: TrainingLetters { TrainingLetters(rawValue: trainingLetters) ?? .open }

    private func errorWordsModel() -> ErrorWordsCardModel {
        let reader = StatsReader(context: modelContext)
        let open = (try? reader.openLetters(language: language, course: library.courses[language],
                                            legacy: library.legacyCourses[language])) ?? []
        return ErrorWordsCardModel.make(entries: (try? reader.errorWords(language: language)) ?? [],
                                        fixed: (try? reader.fixedWords()) ?? 0,
                                        allowed: trainingLettersSetting.letters(open: open, language: language))
    }
}

/// Раскладка главной сверху вниз: серия (с уровнем и плашкой починки), неделя, метрики, вкладки («План на сегодня»,
/// «Испытания», «Продолжить курс», «Тренировка и практика»; вкладка есть, когда есть её содержимое), последняя ачивка.
/// Выбор вкладки помнится (`SettingsKey.homeTab`), по умолчанию — план.
struct HomeContent: View {
    let data: HomeData
    /// Приветствие первой строкой; `nil` — без него (проверки раскладки).
    var greeting: String?
    let continueInfo: ContinueInfo?
    let unit: SpeedUnit
    var level: LevelLine?
    var challenges: ChallengesCardModel?
    var dayPlan: DayPlanCardModel?
    var startPlan: () -> Void = {}
    let startLesson: (LessonRun) -> Void
    let openTraining: () -> Void
    let startWeakSpots: () -> Void
    var startErrorWords: () -> Void = {}
    let openPractice: () -> Void
    var latestAchievement: AchievementEntry?
    var openAchievements: () -> Void = {}
    var shareProgress: (() -> Void)?
    /// Вкладка принудительно (проверка раскладки через `ImageRenderer`); `nil` — выбранная пользователем.
    var tabOverride: HomeTab?
    /// Кружки на вкладках принудительно (проверка раскладки); `nil` — по `HomeTabNews`.
    var dotsOverride: Set<HomeTab>?
    /// Плашка обновления (7b) только на самой «Главной»: у проверок раскладки и карточек «Поделиться» его нет.
    @Environment(UpdateChecker.self) private var updateChecker: UpdateChecker?
    @AppStorage(SettingsKey.homeTab) private var storedTab = SettingsDefault.homeTab
    /// Увиденные отпечатки вкладок (`HomeTabNews`); `nil` — ещё не прочитаны или первый запуск.
    @State private var seenTabs: [String: String]?

    private var availableTabs: [HomeTab] {
        HomeTabs.available(hasPlan: dayPlan != nil, hasChallenges: challenges != nil, hasCourse: continueInfo != nil)
    }

    private var selectedTab: Binding<HomeTab> {
        Binding(get: { tabOverride ?? HomeTabs.resolved(stored: storedTab, available: availableTabs) },
                set: { storedTab = $0.rawValue })
    }

    private var fingerprints: [HomeTab: String] {
        HomeTabNews.fingerprints(plan: dayPlan, challenges: challenges, course: continueInfo)
    }

    private var dots: Set<HomeTab> {
        dotsOverride ?? HomeTabNews.dots(fingerprints: fingerprints, seen: seenTabs, selected: selectedTab.wrappedValue)
    }

    /// Показанная вкладка считается увиденной: при появлении, смене вкладки и смене её содержимого.
    private func markSeen() {
        guard tabOverride == nil, dotsOverride == nil else { return }
        seenTabs = HomeTabNews.markSeen(selected: selectedTab.wrappedValue, fingerprints: fingerprints)
    }

    var body: some View {
        ScrollView { column }
            .scrollContentBackground(.hidden)
            .onAppear(perform: markSeen)
            .onChange(of: selectedTab.wrappedValue) { markSeen() }
            .onChange(of: fingerprints) { markSeen() }
    }

    /// Содержимое без прокрутки (его же рисует проверка через `ImageRenderer`: прокрутку тот не отрисовывает).
    var column: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let greeting { Text(verbatim: greeting).font(.title.bold()) }
            // Плашка обновления — сразу под приветствием, выше огня и «Искры» (просьба пользователя: в середине её приходилось искать).
            if let updateChecker, updateChecker.showsBanner { UpdateBanner(checker: updateChecker) }
            StreakHeader(streak: data.streak, todaySeconds: data.todaySeconds, goalMinutes: data.goalMinutes,
                         level: level, shareProgress: shareProgress)
            if let banner = RepairBannerModel.make(streak: data.streak, todaySeconds: data.todaySeconds) {
                RepairBanner(model: banner)
            }
            WeekStrip(days: data.week)
            MetricsCard(data: data, unit: unit)
            HomeTabsSection(tabs: availableTabs, selection: selectedTab, dots: dots) {
                switch selectedTab.wrappedValue {
                case .plan:
                    if let dayPlan { DayPlanCard(model: dayPlan, start: startPlan) }
                case .challenges:
                    if let challenges { ChallengesCard(model: challenges) }
                case .course:
                    if let continueInfo { ContinueCard(info: continueInfo, start: startLesson) }
                case .quick:
                    QuickLinks(data: data, openTraining: openTraining, startWeakSpots: startWeakSpots,
                               startErrorWords: startErrorWords, openPractice: openPractice)
                }
            }
            if let latestAchievement { LatestAchievementCard(entry: latestAchievement, open: openAchievements) }
        }
        .padding(24)
        .frame(maxWidth: 820, alignment: .leading)
    }
}
