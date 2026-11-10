import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Ведёт урок: знакомство → упражнения → результат. Сохраняет каждое упражнение.
/// Брошенное упражнение записывается при завершении запуска: кнопка «Выйти», начало другого урока
/// или тренировки, закрытие окна, выход из приложения. Переход в другой раздел запуск только скрывает
/// (раннер остаётся в иерархии, `onDisappear` не вызывается).
struct LessonRunnerView: View {
    let run: LessonRun
    let onExit: () -> Void
    /// «К курсу» на итоге урока или шага: раздел «Курс» с этим уроком.
    let onToCourse: () -> Void
    let onStart: (LessonRun) -> Void
    /// Запуск по рекомендации «Куда дальше» на итоге урока («Пальцы», «Слабые места», следующий урок).
    let onGo: (RunKind) -> Void

    private enum Phase: Equatable {
        case loading, intro, exercise(Int), interim(Int, ExerciseSummary, StepReviewScreen)
        case result(ExerciseSummary, stars: Int, steps: [StepStat], speedup: SpeedupReference.Outcome?, review: LessonReviewModel)
        case stepResult(StepOutcome)
    }

    /// Итог повтора одного шага.
    private struct StepOutcome: Equatable {
        /// Номер шага в плане урока (`ExerciseSpec.id`) и его вид.
        let stepIndex: Int
        let kind: ExerciseKind
        /// Название шага из плана («Разминка» у проверки этапа).
        let title: String
        let summary: ExerciseSummary
        let errors: Int
        let improved: Bool
        let stars: Int?
        /// Звёзды урока, если этот повтор шага (не проверки) их увеличил: вернулась пятая.
        let lessonStarsGained: Int?
        let steps: [StepStat]
        /// Проверка засчитала этап или курс.
        let completion: ShareEvent?
        /// Вместе с карточкой курса — «Сертификат» (`ShareEvent.certificateOffer`).
        let certificate: ShareEvent?
        /// Итог повтора проверки «Ускорения» против ориентира до попытки.
        let speedup: SpeedupReference.Outcome?
        /// Порог проверки этапа не взят (`GateHint.text`) и «Повтор» этапа для кнопки «Потренировать слабые буквы».
        let gateText: String?
        let reviewLessonId: String?
        /// Разбор шага (§2.2).
        let review: StepReviewScreen
    }

    /// Прогресс курса для гейта на итоге урока.
    private struct GateProgress: Equatable {
        /// Засчитанные уроки языка до этой попытки и звёзды проверок этапов по истории (после её записи: у обычного
        /// урока они от попытки не меняются, у проверки этапа попытка уже учтена).
        var passed: Set<String> = []
        var checkStars: [String: Int] = [:]
        /// Звёзды проверки в этой попытке (без правила «чистого урока»); 0 — не проверка или не засчитана.
        var attemptStars = 0
        /// Средняя скорость проверок этапов, если эта попытка закрывает курс и даёт «Сертификат»
        /// (`Certificate.eligibleAverage`); иначе `nil`.
        var certificateAverage: Double?
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @Query private var progress: [LessonProgress]
    @State private var phase: Phase = .loading
    @State private var exercises: [ExerciseSpec] = []
    @State private var coordinator: ExerciseCoordinator?
    /// Урок продолжен с этого шага (с нуля); на нём показывается плашка «Продолжаем с шага N из M».
    @State private var resumedStep: Int?
    /// Повтор одного шага (`LessonRun.onlyStepIndex`), если шаг с таким номером есть в плане урока.
    @State private var singleStep: ExerciseSpec?
    /// Ориентир «Ускорения» по истории до этой попытки; `nil` — урок не «Ускорение» или проверок ещё нет.
    @State private var speedupReference: Double?
    /// Гейт этапов на итоге урока: «Следующий урок», порог проверки и карточка этапа (`GateHint`).
    @State private var gate = GateProgress()
    /// Шаги этого прохода с перебором ошибок: к проверке урока не пускают, пока они есть.
    @State private var pass = LessonPass()
    /// Начало текущего прохода и шаг, с которого он продолжен: по ним разбор урока отбирает записи (§2.3).
    @State private var passStart = Date.now
    @State private var passResumeStart = 0
    /// Ошибки по буквам шагов прохода (в базе их нет): для «Подтянуть» на итоге урока.
    @State private var passLetters: [Int: [Character: Int]] = [:]

    private var course: Course? { library.courses[run.language] }
    private var context: LessonContext? { course?.context(for: run.lessonId) }
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }

    var body: some View {
        content
            .onAppear(perform: prepare)
            .task { sound.prewarm() }
            .onDisappear {
                coordinator?.recordAbandonIfNeeded()
                sound.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                coordinator?.recordAbandonIfNeeded(quitting: true)
            }
            .background {
                if let coordinator { Color.clear.saveErrorAlert(coordinator) }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
        case .intro:
            if let context {
                LessonIntroView(lesson: context.lesson, language: run.language,
                                teachesSpaceThumb: course?.lessons.first?.id == run.lessonId, onStart: { begin(0) },
                                onExit: exit)
            }
        case .exercise(let index):
            if let session = coordinator?.session {
                ExerciseView(session: session,
                             title: "\(context?.lesson.localizedTitle ?? "") · \(exercises[index].localizedTitle)",
                             step: singleStep == nil ? index + 1 : 0, totalSteps: singleStep == nil ? exercises.count : 0,
                             targetCpm: speedTarget,
                             resumedStep: resumedStep == index ? index + 1 : nil,
                             errorLimit: stepLimit(index),
                             banner: speedupReference.map { LessonRunPlan.speedupBanner(reference: $0, unit: unit) },
                             onRestart: { restartStep(index) }, onExit: exit)
                    // Новая сессия того же шага («Шаг заново») — новый экран: монитор клавиш держит свою сессию.
                    .id(ObjectIdentifier(session))
            }
        case .interim(let index, let summary, let review):
            let interim = StepInterim(errors: summary.errors, limit: stepLimit(index))
            VStack(spacing: 16) {
                Text("Готово: шаг \(index + 1) из \(exercises.count)").font(.largeTitle.bold())
                let speed = unit.format(summary.cpm)
                Text("\(speed) · ошибок: \(summary.errors)")
                    .font(.title2).monospacedDigit()
                StepDotsView(current: index + 1, total: exercises.count)
                SpeedSegmentsChart(screen: review, unit: unit)
                StepReviewLines(screen: review)
                if let line = interim.toleranceLine {
                    Text(line).font(.title3).foregroundStyle(.red)
                } else {
                    Text("Дальше: \(exercises[index + 1].localizedTitle)").foregroundStyle(.secondary)
                }
                NewAchievementCards(achievements: coordinator?.newAchievements ?? [], fullFlame: coordinator?.newFullFlame)
                if interim.showsRetry {
                    Button("Повторить шаг") { resumedStep = nil; redraw(index); begin(index) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
                if interim.showsNext {
                    Button("Дальше") { resumedStep = nil; begin(index + 1) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        case .result(let summary, let stars, let steps, let speedup, let lessonReview):
            let next = nextRun(stars: stars)
            let review = course.flatMap { GateHint.reviewLesson(course: $0, checkLessonId: run.lessonId) }
            let completion = course.flatMap {
                ShareEvent.completion(course: $0, lessonId: run.lessonId, stars: stars,
                                      passed: gate.passed, checkStars: gate.checkStars)
            }
            let advice = ReviewDestination.run(for: lessonReview.review.advice, language: run.language,
                                               next: run.planSlot == nil && stars > 0 ? next : nil)
            LessonResultView(summary: summary, stars: stars, steps: steps, targetCpm: context?.targetCpm ?? 0,
                             // Урок из плана: «Следующего урока» нет, дальше ведёт план (решение 16).
                             hasNext: next != nil && run.planSlot == nil, newAchievements: coordinator?.runAchievements ?? [],
                             fullFlame: coordinator?.runFullFlame,
                             completion: completion,
                             certificate: ShareEvent.certificateOffer(after: completion, language: run.language,
                                                                      average: gate.certificateAverage),
                             speedup: speedup,
                             review: lessonReview,
                             adviceTitle: advice == nil ? nil : ReviewDestination.title(for: lessonReview.review.advice),
                             onAdvice: advice.map { kind in { onGo(kind) } },
                             gateText: course.flatMap {
                                 GateHint.text(course: $0, lessonId: run.lessonId, attemptStars: gate.attemptStars,
                                               storedCheckStars: gate.checkStars, unit: unit)
                             },
                             onPracticeWeak: review.map { review in
                                 { onStart(LessonRun(language: run.language, lessonId: review.id)) }
                             },
                             statsRequest: course.flatMap {
                                 LessonStatsRequest.make(course: $0, lessonId: run.lessonId, language: run.language)
                             },
                             onRetry: prepare,
                             onNext: { if let next { onStart(next) } }, onExit: onToCourse)
        case .stepResult(let outcome):
            StepResultView(title: StepTitle.numbered(outcome.stepIndex, outcome.title),
                           summary: outcome.summary, errors: outcome.errors,
                           improved: outcome.improved, stars: outcome.stars,
                           lessonStarsGained: outcome.lessonStarsGained, steps: outcome.steps, targetCpm: context?.targetCpm ?? 0,
                           newAchievements: coordinator?.newAchievements ?? [], fullFlame: coordinator?.newFullFlame,
                           completion: outcome.completion, certificate: outcome.certificate,
                           speedup: outcome.speedup,
                           review: outcome.review,
                           gateText: outcome.gateText,
                           onPracticeWeak: outcome.reviewLessonId.map { reviewId in
                               { onStart(LessonRun(language: run.language, lessonId: reviewId)) }
                           },
                           onRetry: prepare, onExit: onToCourse)
        }
    }

    /// Допуск ошибок шага `index`; `nil` — допуск не действует (проверки, урок-проверка этапа, повтор одного шага,
    /// последний шаг урока: он записывает урок).
    private func stepLimit(_ index: Int) -> Int? {
        guard singleStep == nil, let context, exercises.indices.contains(index), index < exercises.count - 1,
              StepTolerance.applies(kind: exercises[index].kind, lessonKind: context.lesson.resolvedKind)
        else { return nil }
        return StepTolerance.limit(length: exercises[index].text.count)
    }

    /// Цель индикатора скорости: у «Ускорения» со средней — средняя + 10%, иначе цель урока.
    private var speedTarget: Double? {
        if let speedupReference { return Double(SpeedupReference.goal(reference: speedupReference)) }
        return context.flatMap { $0.targetCpm > 0 ? Double($0.targetCpm) : nil }
    }

    /// Следующий урок, если он открыт по гейту с учётом этой попытки (проверка ниже порога не ведёт в закрытый этап).
    private func nextRun(stars: Int) -> LessonRun? {
        guard let course,
              let next = GateHint.nextLesson(course: course, after: run.lessonId, stars: stars,
                                             passed: gate.passed, checkStars: gate.checkStars) else { return nil }
        return LessonRun(language: run.language, lessonId: next.id)
    }

    /// Засчитанные уроки языка по записанному прогрессу. Читать до записи попытки: после неё `@Query` мог её уже
    /// показать, и «до попытки» (`ShareEvent.completion`) было бы неверным.
    private func passedLessons() -> Set<String> {
        Set(progress.filter { $0.language == run.language.rawValue && $0.passedAt != nil }.map(\.lessonId))
    }

    /// Прогресс курса для итога: `passedBefore` — засчитанные уроки до попытки (`passedLessons()`), звёзды проверок
    /// этапов по истории (издание 1 порога не знает) читаются после записи попытки. «Сертификат» считается, только
    /// если эта попытка закрывает курс издания 2 (любой урок, не только итоговая проверка); историю читаем лишь тогда.
    private func loadGateProgress(passedBefore: Set<String>, attemptStars: Int = 0) -> GateProgress {
        var checks: [String: Int] = [:]
        if let course, course.edition >= 2 {
            checks = (try? ProgressSnapshot(context: modelContext).stageCheckStars(course: course)) ?? [:]
        }
        var certificate: Double?
        if let course, course.edition >= 2 {
            // Попытка уже в базе, но @Query мог её ещё не показать: урок засчитан, только если у попытки есть звёзды
            // (`CourseGate.withAttempt`, как `ShareEvent.completion`).
            let attempt = CourseGate.withAttempt(course: course, lessonId: run.lessonId, stars: attemptStars,
                                                   passed: passedBefore, checkStars: checks)
            if course.isCompleted(passed: attempt.passed, checkStars: attempt.checkStars) {
                certificate = try? ProgressSnapshot(context: modelContext)
                    .certificateAverage(course: course, passed: attempt.passed)
            }
        }
        return GateProgress(passed: passedBefore, checkStars: checks, attemptStars: attemptStars,
                            certificateAverage: certificate)
    }

    private func prepare() { prepare(fresh: false) }

    /// `fresh` — начать с первого шага, забыв пройденные шаги.
    private func prepare(fresh: Bool) {
        guard let context, let planner = library.planners[run.language] else { return }
        if coordinator == nil {
            let coordinator = ExerciseCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                                         reminders: reminders)
            self.coordinator = coordinator
        }
        coordinator?.onExitAfterAlert = onExit
        // Новый проход урока: на его итоге — ачивки только этого прохода.
        coordinator?.resetRunAchievements()
        // «Повтор», «Ускорение» и шаги `focus` строятся по статистике клавиш и сочетаний пользователя.
        // Буквы «трудных» уроков курса весят ×2 в «Повторе» (решение 8 фазы 6c).
        let learner = (try? StatsReader(context: modelContext).learnerStats(language: run.language, course: course))
            ?? .empty
        var rng = SystemRandomNumberGenerator()
        let plan = LessonRunPlan.exercises(planner: planner, context: context, learner: learner,
                                           onlyStepIndex: run.onlyStepIndex, refresh: run.refresh, rng: &rng)
        // Ориентир «Ускорения» — по истории до этой попытки (решение 16), один раз на проход урока.
        speedupReference = context.lesson.resolvedKind == .speedup ? course.flatMap(loadSpeedupReference(in:)) : nil
        resumedStep = nil
        pass = LessonPass()
        passStart = .now
        passResumeStart = 0
        passLetters = [:]
        // Повтор одного шага и «Освежить»: без знакомства и без продолжения урока.
        if plan.singleStep, let spec = plan.exercises.first {
            singleStep = spec
            exercises = [spec]
            begin(0)
            return
        }
        singleStep = nil
        exercises = plan.exercises
        let resume = LessonResume()
        if fresh { resume.clear(lessonId: run.lessonId) }
        let start = resume.start(lessonId: run.lessonId, totalSteps: exercises.count)
        if start > 0 {
            // Продолжение: знакомство с клавишами уже было.
            resumedStep = start
            passResumeStart = start
            begin(start)
            return
        }
        if LessonRunPlan.showsIntro(introducesSomething: context.lesson.introducesSomething, resumeStart: start,
                                    singleStep: false, restart: fresh) {
            phase = .intro
        } else {
            begin(0)
        }
    }

    private func begin(_ requested: Int) {
        guard let context, let coordinator else { return }
        // К проверке урока не пускаем, пока в проходе есть шаг с перебором.
        let index = pass.entry(requested: requested, lastIndex: exercises.count - 1)
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(context.hint)
        _ = coordinator.start(spec: exercises[index], language: run.language, mode: .course,
                              lessonId: run.lessonId, hint: hint, planSlot: run.planSlot) { session, result in
            finish(index: index, session: session, result: result)
        }
        phase = .exercise(index)
        // Движок мог остановиться после паузы: запускаем его заранее, не на первом нажатии.
        sound.prewarm()
    }

    private func finish(index: Int, session: ExerciseSession, result: ExerciseResult) {
        if let singleStep {
            finishSingleStep(singleStep, session: session, result: result)
            return
        }
        let summary = ExerciseSummary(result)
        passLetters[index] = result.errorsByCharacter
        let isLast = index == exercises.count - 1
        // В базу идут звёзды проверки; на экране — звёзды урока: пятая только при чистых шагах.
        let checkStars = isLast ? LessonScoring.stars(cpm: result.cpm, accuracy: result.accuracy,
                                                      targetCpm: context?.targetCpm ?? 0) : 0
        let steps = isLast ? lessonSteps() : []
        let stepPassed = stepLimit(index) == nil || StepTolerance.passed(errorCount: result.errorCount, length: exercises[index].text.count)
        pass.record(step: index, passed: stepPassed)
        let stars = LessonScoring.lessonStars(checkStars: checkStars, steps: steps)
        sound.play(isLast && stars > 0 ? .lessonDone : .exerciseDone)
        let passedBefore = passedLessons()
        let saved = coordinator?.recordFinish(session, result) { recorder in
            if isLast { try recorder.recordLesson(result, stars: checkStars) }
        } ?? false
        // Шаг считается пройденным только после записи в базу (в том числе после «Повторить» в алерте).
        // Последний шаг — иначе: итог урока показан, продолжать нечего, даже если запись не удалась
        // и её отменили (иначе урок снова открылся бы на проверке).
        let lessonId = run.lessonId, totalSteps = exercises.count
        if isLast {
            LessonResume().clear(lessonId: lessonId)
            coordinator?.onRetrySucceeded = nil
        } else {
            let markStep = { LessonResume().stepFinished(lessonId: lessonId, index: index, totalSteps: totalSteps,
                                                         passed: stepPassed) }
            coordinator?.onRetrySucceeded = saved ? nil : markStep
            if saved { markStep() }
        }
        let speedup = isLast
            ? LessonRunPlan.speedupOutcome(kind: exercises[index].kind, cpm: result.cpm, reference: speedupReference)
            : nil
        if isLast { gate = loadGateProgress(passedBefore: passedBefore, attemptStars: checkStars) }
        if isLast {
            let model = LessonReviewModel.make(records: passRecords(), letters: passLetters,
                                               resumeStart: passResumeStart, passStart: passStart,
                                               errorWordsAvailable: errorWordsAvailable())
            phase = .result(summary, stars: stars, steps: steps, speedup: speedup, review: model)
        } else {
            phase = .interim(index, summary, stepReview(result))
        }
    }

    /// Повтор шага записывается как обычно; повтор проверки и «Освежить» — полноценная проверка урока (со звёздами,
    /// `isLessonCheck`). Продолжение урока (`LessonResume`) не меняется.
    private func finishSingleStep(_ spec: ExerciseSpec, session: ExerciseSession, result: ExerciseResult) {
        // Шаги до этой попытки: «Лучший результат!» сравнивается с ними (с шагом того же номера, а у истории без
        // номеров — того же вида); для звёзд проверки остальные шаги этой попыткой не меняются.
        let steps = lessonSteps()
        let kind = spec.kind
        let previous = steps.first { $0.stepIndex == spec.id } ?? steps.first { $0.stepIndex == nil && $0.kind == kind }
        let isCheck = kind.isLessonCheck
        let checkStars = isCheck ? LessonScoring.stars(cpm: result.cpm, accuracy: result.accuracy,
                                                       targetCpm: context?.targetCpm ?? 0) : nil
        let stars = checkStars.map { LessonScoring.lessonStars(checkStars: $0, steps: steps) }
        sound.play((stars ?? 0) > 0 ? .lessonDone : .exerciseDone)
        // Чистый повтор нечекового шага может вернуть пятую звезду: сравниваем звёзды урока до и после записи.
        let starsBefore = isCheck ? nil : currentLessonStars()
        coordinator?.onRetrySucceeded = nil
        let passedBefore = passedLessons()
        let saved = coordinator?.recordFinish(session, result) { recorder in
            if let checkStars { try recorder.recordLesson(result, stars: checkStars) }
        } ?? false
        // Прогресс курса нужен только проверке (этап или курс засчитывает она).
        let progressNow = isCheck ? loadGateProgress(passedBefore: passedBefore, attemptStars: checkStars ?? 0)
            : GateProgress()
        let gateText = course.flatMap {
            GateHint.text(course: $0, lessonId: run.lessonId, attemptStars: checkStars ?? 0,
                          storedCheckStars: progressNow.checkStars, unit: unit)
        }
        let review = course.flatMap { GateHint.reviewLesson(course: $0, checkLessonId: run.lessonId) }
        let gained = starsBefore.flatMap { before in
            saved ? currentLessonStars().flatMap { LessonOverview.starsGained(before: before, after: $0) } : nil
        }
        let completion = course.flatMap {
            ShareEvent.stepCompletion(course: $0, lessonId: run.lessonId, kind: kind, stars: stars,
                                      passed: progressNow.passed, checkStars: progressNow.checkStars)
        }
        phase = .stepResult(StepOutcome(
            stepIndex: spec.id, kind: kind, title: spec.localizedTitle, summary: ExerciseSummary(result),
            errors: result.errorCount,
            improved: LessonStepStats.isImprovement(accuracy: result.accuracy, cpm: result.cpm, over: previous),
            stars: stars, lessonStarsGained: gained, steps: steps,
            completion: completion,
            certificate: ShareEvent.certificateOffer(after: completion, language: run.language,
                                                     average: progressNow.certificateAverage),
            speedup: LessonRunPlan.speedupOutcome(kind: kind, cpm: result.cpm, reference: speedupReference),
            gateText: gateText, reviewLessonId: gateText == nil ? nil : review?.id,
            review: stepReview(result)))
    }

    /// Действующие звёзды урока по истории (как на карте курса); `nil` — истории не прочитать или урока нет в курсе.
    private func currentLessonStars() -> Int? {
        guard let context, let history = try? ProgressSnapshot(context: modelContext).lessonSessions(lessonId: run.lessonId)
        else { return nil }
        let record = progress.first { $0.lessonId == run.lessonId }
        return LessonOverview.make(lessonId: run.lessonId, targetCpm: context.targetCpm, sessions: history,
                                   storedStars: record?.bestStars ?? 0, isPassed: record?.passedAt != nil).stars
    }

    /// Ориентир «Ускорения» по сессиям языка курса (чужой язык не читается); не прочитать историю — без ориентира
    /// (урок идёт как обычный).
    private func loadSpeedupReference(in course: Course) -> Double? {
        (try? ProgressSnapshot(context: modelContext).speedupReference(course: course)) ?? nil
    }

    /// Разбор шага (§2.2): отрезки те же, что пишет запись шага.
    private func stepReview(_ result: ExerciseResult) -> StepReviewScreen {
        StepReviewScreen.make(text: result.text, result: result, targetCpm: speedTarget,
                              segments: SpeedSegments.split(text: result.text, timings: result.timings))
    }

    /// В списке языка хватает слов с ошибками (подходящих под настройку букв), чтобы советовать занятие по ним.
    private func errorWordsAvailable() -> Bool {
        let reader = StatsReader(context: modelContext)
        guard let open = try? reader.openLetters(language: run.language, course: library.courses[run.language],
                                                 legacy: library.legacyCourses[run.language]),
              let entries = try? reader.errorWords(language: run.language) else { return false }
        let allowed = TrainingLetters.stored().letters(open: open, language: run.language)
        return ErrorWordsText.eligible(entries: entries, allowed: allowed).count >= DayPlanner.errorWordsThreshold
    }

    /// Записи шагов этого урока для разбора (проход отбирает `LessonReviewModel.make`).
    private func passRecords() -> [PassRecord] {
        let lessonId = run.lessonId
        let descriptor = FetchDescriptor<SessionRecord>(predicate: #Predicate { $0.lessonId == lessonId })
        return ((try? modelContext.fetch(descriptor)) ?? []).compactMap(PassRecord.init)
    }

    /// Лучшие попытки шагов урока по истории (до текущей попытки).
    private func lessonSteps() -> [StepStat] {
        let history = (try? ProgressSnapshot(context: modelContext).lessonSessions(lessonId: run.lessonId)) ?? []
        return LessonStepStats.summarize(sessions: history, lessonId: run.lessonId)
    }

    /// «Шаг заново» на плашке продолжения: начатая попытка записывается как брошенная, тот же шаг начинается
    /// с начала и с новым текстом; пройденные шаги урока и плашка остаются.
    private func restartStep(_ index: Int) {
        coordinator?.recordAbandonIfNeeded(announce: true)
        redraw(index)
        begin(index)
    }

    /// Новый текст шага `index` перед повтором — как при входе в шаг заново с карты курса (`LessonRunPlan.redrawnStep`).
    private func redraw(_ index: Int) {
        guard singleStep == nil, exercises.indices.contains(index), let context,
              let planner = library.planners[run.language] else { return }
        let learner = (try? StatsReader(context: modelContext).learnerStats(language: run.language, course: course))
            ?? .empty
        var rng = SystemRandomNumberGenerator()
        exercises[index] = LessonRunPlan.redrawnStep(planner: planner, context: context, learner: learner,
                                                     current: exercises[index], rng: &rng)
    }

    private func exit() {
        if coordinator?.exit() ?? true { onExit() }
    }
}

/// План запуска урока и надписи «Ускорения» (чистые функции: проверяются без отрисовки).
enum LessonRunPlan {
    /// Упражнения запуска; `singleStep` — повтор одного шага. План строится целиком одним генератором: текст шага
    /// зависит от предыдущих (общий генератор, неповторяющиеся отрывки), поэтому повтор шага N — шаг N полного плана,
    /// а не шаг, спланированный отдельно. Номера нет в плане (или он не задан) — весь урок.
    /// `refresh` — «Освежить»: один шаг `refresh` (проверка урока заново, с номером проверки в плане); в плане урока
    /// проверки нет — запуск как обычно.
    static func exercises<G: RandomNumberGenerator>(planner: LessonPlanner, context: LessonContext, learner: LearnerStats,
                                                    onlyStepIndex: Int?, refresh: Bool = false, rng: inout G)
        -> (exercises: [ExerciseSpec], singleStep: Bool) {
        if refresh, let spec = planner.refreshSpec(for: context, learner: learner, rng: &rng) { return ([spec], true) }
        let plan = planner.exercises(for: context, learner: learner, rng: &rng)
        if let index = onlyStepIndex, plan.indices.contains(index) { return ([plan[index]], true) }
        return (plan, false)
    }

    /// Шаг `current` с новым текстом для повтора внутри урока: шаг с тем же номером из заново построенного плана
    /// (как при входе в шаг с карты курса). Текст совпал с прежним — до 5 попыток; шага с этим номером нет или вид
    /// другой — прежний шаг.
    static func redrawnStep<G: RandomNumberGenerator>(planner: LessonPlanner, context: LessonContext,
                                                      learner: LearnerStats, current: ExerciseSpec,
                                                      rng: inout G) -> ExerciseSpec {
        var fallback = current
        for _ in 0..<5 {
            let plan = planner.exercises(for: context, learner: learner, rng: &rng)
            guard plan.indices.contains(current.id), plan[current.id].kind == current.kind else { return fallback }
            let spec = plan[current.id]
            if spec.text != current.text { return spec }
            fallback = spec
        }
        return fallback
    }

    /// Знакомство с клавишами перед уроком: при первом прохождении и когда пройденный урок запускается заново целиком
    /// с первого шага. Не показывать: продолжение (`resumeStart` > 0), отдельный шаг и «Освежить» (`singleStep`),
    /// перезапуск внутри урока (`restart`).
    static func showsIntro(introducesSomething: Bool, resumeStart: Int, singleStep: Bool, restart: Bool) -> Bool {
        introducesSomething && resumeStart == 0 && !singleStep && !restart
    }

    /// Итог проверки «Ускорения» против цели от средней до попытки; `nil` — не проверка или средней нет (урок не
    /// «Ускорение», шагов курса ещё мало). Одинаков для итога урока и для итога повтора одной проверки.
    static func speedupOutcome(kind: ExerciseKind, cpm: Double, reference: Double?) -> SpeedupReference.Outcome? {
        guard kind.isLessonCheck, let reference else { return nil }
        return SpeedupReference.outcome(cpm: cpm, goal: SpeedupReference.goal(reference: reference))
    }

    /// «Ваша средняя: 196 зн/мин → цель 216 зн/мин» — плашка над текстом шагов «Ускорения» (§6.2).
    static func speedupBanner(reference: Double, unit: SpeedUnit) -> String {
        let average = unit.format(reference)
        let goal = unit.format(Double(SpeedupReference.goal(reference: reference)))
        return String(localized: "Ваша средняя: \(average) → цель \(goal)")
    }
}
