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
    let onStart: (LessonRun) -> Void

    private enum Phase: Equatable {
        case loading, intro, exercise(Int), interim(Int, ExerciseSummary), result(ExerciseSummary, stars: Int, steps: [StepStat])
        case stepResult(StepOutcome)
    }

    /// Итог повтора одного шага.
    private struct StepOutcome: Equatable {
        let kind: ExerciseKind
        let summary: ExerciseSummary
        let errors: Int
        let improved: Bool
        let stars: Int?
        /// Звёзды урока, если этот повтор шага (не проверки) их увеличил: вернулась пятая.
        let lessonStarsGained: Int?
        let steps: [StepStat]
        /// Проверка засчитала последний урок этапа или курса.
        let completion: ShareEvent?
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
    /// Повтор одного шага (`LessonRun.onlyStep`), если такой шаг есть в плане урока.
    @State private var singleStep: ExerciseKind?

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
                coordinator?.recordAbandonIfNeeded()
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
                                teachesSpaceThumb: course?.lessons.first?.id == run.lessonId, onStart: { begin(0) })
            }
        case .exercise(let index):
            if let session = coordinator?.session {
                ExerciseView(session: session,
                             title: "\(context?.lesson.localizedTitle ?? "") · \(exercises[index].localizedTitle)",
                             step: singleStep == nil ? index + 1 : 0, totalSteps: singleStep == nil ? exercises.count : 0,
                             targetCpm: context.flatMap { $0.targetCpm > 0 ? Double($0.targetCpm) : nil },
                             resumedStep: resumedStep == index ? index + 1 : nil, onRestart: restart, onExit: exit)
                    .id(index)
            }
        case .interim(let index, let summary):
            VStack(spacing: 16) {
                Text("Готово: шаг \(index + 1) из \(exercises.count)").font(.largeTitle.bold())
                let speed = unit.format(summary.cpm)
                Text("\(speed) · ошибок: \(summary.errors)")
                    .font(.title2).monospacedDigit()
                StepDotsView(current: index + 1, total: exercises.count)
                Text("Дальше: \(exercises[index + 1].localizedTitle)").foregroundStyle(.secondary)
                NewAchievementCards(achievements: coordinator?.newAchievements ?? [], fullFlame: coordinator?.newFullFlame)
                Button("Дальше") { begin(index + 1) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .result(let summary, let stars, let steps):
            LessonResultView(summary: summary, stars: stars, steps: steps, targetCpm: context?.targetCpm ?? 0,
                             hasNext: nextRun != nil, newAchievements: coordinator?.runAchievements ?? [],
                             fullFlame: coordinator?.runFullFlame,
                             completion: course.flatMap { ShareEvent.completion(course: $0, lessonId: run.lessonId, stars: stars) },
                             onRetry: prepare,
                             onNext: { if let nextRun { onStart(nextRun) } }, onExit: onExit)
        case .stepResult(let outcome):
            StepResultView(kind: outcome.kind, summary: outcome.summary, errors: outcome.errors,
                           improved: outcome.improved, stars: outcome.stars,
                           lessonStarsGained: outcome.lessonStarsGained, steps: outcome.steps, targetCpm: context?.targetCpm ?? 0,
                           newAchievements: coordinator?.newAchievements ?? [], fullFlame: coordinator?.newFullFlame,
                           completion: outcome.completion,
                           onRetry: prepare, onExit: onExit)
        }
    }

    private var nextRun: LessonRun? {
        guard let course,
              let index = course.lessons.firstIndex(where: { $0.id == run.lessonId }),
              index + 1 < course.lessons.count else { return nil }
        return LessonRun(language: run.language, lessonId: course.lessons[index + 1].id)
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
        var rng = SystemRandomNumberGenerator()
        let plan = planner.exercises(for: context, rng: &rng)
        resumedStep = nil
        // Повтор одного шага: без знакомства и без продолжения урока.
        if let only = run.onlyStep, let spec = plan.first(where: { $0.kind == only }) {
            singleStep = only
            exercises = [spec]
            begin(0)
            return
        }
        singleStep = nil
        exercises = plan
        let resume = LessonResume()
        if fresh { resume.clear(lessonId: run.lessonId) }
        let start = resume.start(lessonId: run.lessonId, totalSteps: exercises.count)
        if start > 0 {
            // Продолжение: знакомство с клавишами уже было.
            resumedStep = start
            begin(start)
            return
        }
        let firstAttempt = !progress.contains { $0.lessonId == run.lessonId }
        if context.lesson.introducesSomething && firstAttempt {
            phase = .intro
        } else {
            begin(0)
        }
    }

    private func begin(_ index: Int) {
        guard let context, let coordinator else { return }
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(context.hint)
        _ = coordinator.start(spec: exercises[index], language: run.language, mode: .course,
                              lessonId: run.lessonId, hint: hint) { session, result in
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
        let isLast = index == exercises.count - 1
        // В базу идут звёзды проверки; на экране — звёзды урока: пятая только при чистых шагах.
        let checkStars = isLast ? LessonScoring.stars(cpm: result.cpm, accuracy: result.accuracy,
                                                      targetCpm: context?.targetCpm ?? 0) : 0
        let steps = isLast ? lessonSteps() : []
        let stars = LessonScoring.lessonStars(checkStars: checkStars, steps: steps)
        sound.play(isLast && stars > 0 ? .lessonDone : .exerciseDone)
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
            let markStep = { LessonResume().stepFinished(lessonId: lessonId, index: index, totalSteps: totalSteps) }
            coordinator?.onRetrySucceeded = saved ? nil : markStep
            if saved { markStep() }
        }
        phase = isLast ? .result(summary, stars: stars, steps: steps) : .interim(index, summary)
    }

    /// Повтор шага записывается как обычно; повтор проверки — полноценная проверка урока (со звёздами).
    /// Продолжение урока (`LessonResume`) не меняется.
    private func finishSingleStep(_ kind: ExerciseKind, session: ExerciseSession, result: ExerciseResult) {
        // Шаги до этой попытки: «Лучший результат!» сравнивается с ними; для звёзд проверки остальные шаги
        // этой попыткой не меняются.
        let steps = lessonSteps()
        let previous = steps.first { $0.kind == kind }
        let isCheck = kind == .check
        let checkStars = isCheck ? LessonScoring.stars(cpm: result.cpm, accuracy: result.accuracy,
                                                       targetCpm: context?.targetCpm ?? 0) : nil
        let stars = checkStars.map { LessonScoring.lessonStars(checkStars: $0, steps: steps) }
        sound.play((stars ?? 0) > 0 ? .lessonDone : .exerciseDone)
        // Чистый повтор нечекового шага может вернуть пятую звезду: сравниваем звёзды урока до и после записи.
        let starsBefore = isCheck ? nil : currentLessonStars()
        coordinator?.onRetrySucceeded = nil
        let saved = coordinator?.recordFinish(session, result) { recorder in
            if let checkStars { try recorder.recordLesson(result, stars: checkStars) }
        } ?? false
        let gained = starsBefore.flatMap { before in
            saved ? currentLessonStars().flatMap { LessonOverview.starsGained(before: before, after: $0) } : nil
        }
        phase = .stepResult(StepOutcome(
            kind: kind, summary: ExerciseSummary(result), errors: result.errorCount,
            improved: LessonStepStats.isImprovement(accuracy: result.accuracy, cpm: result.cpm, over: previous),
            stars: stars, lessonStarsGained: gained, steps: steps,
            completion: course.flatMap {
                ShareEvent.stepCompletion(course: $0, lessonId: run.lessonId, kind: kind, stars: stars)
            }))
    }

    /// Действующие звёзды урока по истории (как на карте курса); `nil` — истории не прочитать или урока нет в курсе.
    private func currentLessonStars() -> Int? {
        guard let context, let history = try? ProgressSnapshot(context: modelContext).lessonSessions(lessonId: run.lessonId)
        else { return nil }
        let record = progress.first { $0.lessonId == run.lessonId }
        return LessonOverview.make(lessonId: run.lessonId, targetCpm: context.targetCpm, sessions: history,
                                   storedStars: record?.bestStars ?? 0, isPassed: record?.passedAt != nil).stars
    }

    /// Лучшие попытки шагов урока по истории (до текущей попытки).
    private func lessonSteps() -> [StepStat] {
        let history = (try? ProgressSnapshot(context: modelContext).lessonSessions(lessonId: run.lessonId)) ?? []
        return LessonStepStats.summarize(sessions: history, lessonId: run.lessonId)
    }

    /// «Начать урок заново» на плашке продолжения: начатый шаг записывается как брошенный.
    private func restart() {
        coordinator?.recordAbandonIfNeeded(announce: true)
        prepare(fresh: true)
    }

    private func exit() {
        if coordinator?.exit() ?? true { onExit() }
    }
}
