import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Ведёт урок: знакомство → упражнения → результат. Сохраняет каждое упражнение.
/// Брошенное упражнение записывается при любом уходе с экрана: кнопка «Выйти», переход
/// в боковой панели, закрытие окна, выход из приложения.
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
    @AppStorage(SettingsKey.dayStartHour) private var dayStartHour = SettingsDefault.dayStartHour
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @Query private var progress: [LessonProgress]
    @State private var phase: Phase = .loading
    @State private var exercises: [ExerciseSpec] = []
    @State private var session: ExerciseSession?
    @State private var saveError: String?
    @State private var showSaveError = false
    @State private var pendingSave: (() throws -> Void)?
    @State private var exitAfterSave = false

    private var course: Course? { library.courses[run.language] }
    private var context: LessonContext? { course?.context(for: run.lessonId) }
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }
    private var recorder: ResultRecorder { ResultRecorder(context: modelContext, dayStartHour: dayStartHour) }

    var body: some View {
        content
            .onAppear(perform: prepare)
            .task { sound.prewarm() }
            .onDisappear {
                recordAbandonIfNeeded()
                sound.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                recordAbandonIfNeeded()
            }
            .alert("Не удалось сохранить результат", isPresented: $showSaveError) {
                Button("Повторить") {
                    if save(pendingSave), exitAfterSave { onExit() }
                }
                Button("Отмена", role: .cancel) {
                    pendingSave = nil
                    if exitAfterSave { onExit() }
                }
            } message: {
                Text(saveError ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
        case .intro:
            if let context { LessonIntroView(lesson: context.lesson, language: run.language, onStart: { begin(0) }) }
        case .exercise(let index):
            if let session {
                ExerciseView(session: session,
                             title: "\(context?.lesson.localizedTitle ?? "") · \(exercises[index].localizedTitle)",
                             step: index + 1, totalSteps: exercises.count,
                             onExit: exit)
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
        guard let context else { return }
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(context.hint)
        let next = ExerciseSession(spec: exercises[index], language: run.language, mode: .course,
                                   lessonId: run.lessonId, hint: hint)
        next.onSound = { [sound] in sound.play($0) }
        next.onFinish = { [weak next] result in
            guard let next else { return }
            finish(index: index, session: next, result: result)
        }
        session = next
        phase = .exercise(index)
        // Движок мог остановиться после паузы: запускаем его заранее, не на первом нажатии.
        sound.prewarm()
    }

    private func finish(index: Int, session: ExerciseSession, result: ExerciseResult) {
        session.onFinish = nil
        session.markRecorded()
        let recorder = self.recorder
        let summary = ExerciseSummary(result)
        let isLast = index == exercises.count - 1
        let stars = isLast ? LessonScoring.stars(cpm: result.cpm, accuracy: result.accuracy,
                                                 targetCpm: context?.targetCpm ?? 0) : 0
        sound.play(isLast && stars > 0 ? .lessonDone : .exerciseDone)
        exitAfterSave = false
        save {
            try recorder.record(result)
            try Self.recordCounters(session, recorder)
            if isLast { try recorder.recordLesson(result, stars: stars) }
        }
        phase = isLast ? .result(summary, stars: stars) : .interim(index, summary)
    }

    private func exit() {
        guard let session, !session.isRecorded else {
            onExit()
            return
        }
        // Пока открыт алерт об ошибке, монитор клавиш не должен забирать Return и Esc.
        session.stop()
        session.onFinish = nil
        session.markRecorded()
        exitAfterSave = true
        if save(Self.abandonment(of: session, recorder)) { onExit() }
    }

    /// Уход с экрана без кнопки «Выйти»: показать ошибку уже негде, поэтому сохраняем молча.
    private func recordAbandonIfNeeded() {
        guard let session, !session.isRecorded else { return }
        session.stop()
        session.onFinish = nil
        session.markRecorded()
        try? recorder.commit(Self.abandonment(of: session, recorder))
    }

    private static func abandonment(of session: ExerciseSession,
                                    _ recorder: ResultRecorder) -> () throws -> Void {
        let abandoned = session.shouldRecordAbandon ? session.makeResult() : nil
        return {
            if let abandoned { try recorder.record(abandoned) }
            try recordCounters(session, recorder)
        }
    }

    private static func recordCounters(_ session: ExerciseSession, _ recorder: ResultRecorder) throws {
        if session.wrongLayoutAttempted { try recorder.increment(CounterName.wrongLayoutStarts) }
        if session.capsLockPressed { try recorder.increment(CounterName.capsLockPresses) }
    }

    /// Сохраняет всё одной транзакцией. Возвращает `true`, если сохранение удалось (или сохранять нечего).
    @discardableResult
    private func save(_ body: (() throws -> Void)?) -> Bool {
        guard let body else { return true }
        do {
            try recorder.commit(body)
            pendingSave = nil
            return true
        } catch {
            pendingSave = body
            saveError = error.localizedDescription
            // Показываем в следующем проходе: при «Повторить» алерт ещё закрывается.
            Task { showSaveError = true }
            return false
        }
    }
}
