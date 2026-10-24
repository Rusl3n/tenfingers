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
        case loading, intro, exercise(Int), interim(Int, ExerciseSummary), result(ExerciseSummary, stars: Int)
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @Query private var progress: [LessonProgress]
    @State private var phase: Phase = .loading
    @State private var exercises: [ExerciseSpec] = []
    @State private var coordinator: ExerciseCoordinator?

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
            if let context { LessonIntroView(lesson: context.lesson, language: run.language, onStart: { begin(0) }) }
        case .exercise(let index):
            if let session = coordinator?.session {
                ExerciseView(session: session,
                             title: "\(context?.lesson.localizedTitle ?? "") · \(exercises[index].localizedTitle)",
                             step: index + 1, totalSteps: exercises.count,
                             targetCpm: context.flatMap { $0.targetCpm > 0 ? Double($0.targetCpm) : nil }, onExit: exit)
                    .id(index)
            }
        case .interim(let index, let summary):
            VStack(spacing: 16) {
                Text("Готово: шаг \(index + 1) из \(exercises.count)").font(.largeTitle.bold())
                Text("\(unit.format(summary.cpm)) · \(Formatting.percent(summary.accuracy))")
                    .font(.title2).monospacedDigit()
                StepDotsView(current: index + 1, total: exercises.count)
                Text("Дальше: \(exercises[index + 1].localizedTitle)").foregroundStyle(.secondary)
                Button("Дальше") { begin(index + 1) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .result(let summary, let stars):
            LessonResultView(summary: summary, stars: stars, targetCpm: context?.targetCpm ?? 0,
                             hasNext: nextRun != nil, onRetry: prepare,
                             onNext: { if let nextRun { onStart(nextRun) } }, onExit: onExit)
        }
    }

    private var nextRun: LessonRun? {
        guard let course,
              let index = course.lessons.firstIndex(where: { $0.id == run.lessonId }),
              index + 1 < course.lessons.count else { return nil }
        return LessonRun(language: run.language, lessonId: course.lessons[index + 1].id)
    }

    private func prepare() {
        guard let context, let planner = library.planners[run.language] else { return }
        if coordinator == nil {
            let coordinator = ExerciseCoordinator(
                recorder: ResultRecorder.live(context: modelContext),
                playSound: { [sound] in sound.play($0) })
            self.coordinator = coordinator
        }
        coordinator?.onExitAfterAlert = onExit
        var rng = SystemRandomNumberGenerator()
        exercises = planner.exercises(for: context, rng: &rng)
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
        let summary = ExerciseSummary(result)
        let isLast = index == exercises.count - 1
        let stars = isLast ? LessonScoring.stars(cpm: result.cpm, accuracy: result.accuracy,
                                                 targetCpm: context?.targetCpm ?? 0) : 0
        sound.play(isLast && stars > 0 ? .lessonDone : .exerciseDone)
        coordinator?.recordFinish(session, result) { recorder in
            if isLast { try recorder.recordLesson(result, stars: stars) }
        }
        phase = isLast ? .result(summary, stars: stars) : .interim(index, summary)
    }

    private func exit() {
        if coordinator?.exit() ?? true { onExit() }
    }
}
