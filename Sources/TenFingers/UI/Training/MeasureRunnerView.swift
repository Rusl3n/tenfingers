import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Запуск замера скорости: новый `id` на каждый запуск.
struct MeasureRun: Identifiable, Equatable {
    let id = UUID()
    let variant: MeasureVariant
}

/// Замер скорости (§9): текст из открытых клавиш, таймер с первого нажатия (или «Текст 300 знаков» до конца), без
/// Backspace (движок его не принимает), Esc и «Выйти» — без сохранения. Итог пишется как `SpeedMeasurement` и сессия.
struct MeasureRunnerView: View {
    let run: MeasureRun
    /// Повтор сохранённого замера по `SpeedMeasurement.id` (экран повтора — задача 17): без обработчика кнопки нет.
    var onReplay: ((UUID) -> Void)? = nil
    let onExit: () -> Void

    private struct Final {
        let outcome: MeasureOutcome
        let history: [MeasureHistoryEntry]
        let measurementId: UUID?
    }

    private enum Phase {
        case loading, unavailable, exercise, saving, empty, final(Final)
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @Environment(RunPresence.self) private var presence: RunPresence?
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @State private var phase: Phase = .loading
    @State private var coordinator: ExerciseCoordinator?
    @State private var tick = 0

    var body: some View {
        content
            .onAppear(perform: prepare)
            .task {
                sound.prewarm()
                // Раз в четверть секунды: остаток времени на экране и остановка по времени без нажатия.
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard case .exercise = phase, presence?.isVisible ?? true else { continue }
                    coordinator?.session?.expireIfNeeded()
                    tick &+= 1
                }
            }
            .onDisappear {
                discard()
                sound.stop()
            }
            .background {
                if let coordinator { Color.clear.saveErrorAlert(coordinator) }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading, .saving:
            ProgressView()
        case .unavailable:
            message(String(localized: "Пока нельзя составить текст для этого замера"))
        case .empty:
            message(String(localized: "Не набрано ни одного знака, замер не сохранён"))
        case .exercise:
            if let session = coordinator?.session {
                let _ = tick
                ExerciseView(session: session, title: String(localized: "Замер скорости"), step: 0, totalSteps: 0,
                             timeText: timeText(session), progressOverride: progress(session), onExit: exit)
            }
        case .final(let final):
            let comparison = MeasureHistory.comparison(final.history)
            MeasureResultView(outcome: final.outcome, comparison: comparison, history: final.history,
                              newAchievements: coordinator?.newAchievements ?? [],
                              fullFlame: coordinator?.newFullFlame,
                              onReplay: replayAction(final), onDone: onExit)
        }
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 16) {
            Text(text).font(.title2.bold())
            Button("Готово", action: onExit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
        }
    }

    private func replayAction(_ final: Final) -> (() -> Void)? {
        guard let onReplay, let id = final.measurementId else { return nil }
        return { onReplay(id) }
    }

    /// Остаток времени у замера по таймеру; у «Текста 300 знаков» — `nil` (идёт время упражнения).
    private func timeText(_ session: ExerciseSession) -> String? {
        session.measureTimer.map { Formatting.clock(($0.remaining(at: session.clock())).rounded(.up)) }
    }

    private func progress(_ session: ExerciseSession) -> Double? {
        session.measureTimer.map { min(1, $0.elapsed(at: session.clock()) / $0.limit) }
    }

    private func prepare() {
        guard coordinator == nil else { return }
        let coordinator = ExerciseCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                                     reminders: reminders)
        coordinator.onExitAfterAlert = onExit
        self.coordinator = coordinator
        begin()
    }

    private func begin() {
        guard let coordinator else { return }
        let variant = run.variant
        let language = variant.language
        let reader = StatsReader(context: modelContext)
        let keys = (try? reader.measureKeys(language: language, course: library.courses[language],
                                            legacy: library.legacyCourses[language]))
            ?? MeasureKeys(open: Set(AdaptiveTrainer(language: language)
                                        .unlockedLetters(count: AdaptiveTrainer.initialLetters)),
                           capitalsLearned: false)
        var rng = SystemRandomNumberGenerator()
        guard let generator = library.planners[language]?.generator,
              let text = MeasureText.make(variant: variant, open: keys.open, capitalsLearned: keys.capitalsLearned,
                                          generator: generator, seed: rng.next()) else {
            phase = .unavailable
            return
        }
        let spec = ExerciseSpec(id: 1, kind: .words, title: "Замер скорости", text: text)
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(.full)
        let session = coordinator.start(spec: spec, language: language, mode: .measure, lessonId: nil, hint: hint,
                                        source: "measure:\(variant.key)") { session, result in
            finish(session: session, result: result)
        }
        session.configureMeasure(limit: variant.duration.timerSeconds.map(Double.init))
        session.onEscape = exit
        phase = .exercise
        sound.prewarm()
    }

    private func finish(session: ExerciseSession, result: ExerciseResult) {
        sound.play(.exerciseDone)
        // Ни одного верного знака: сохранять нечего.
        guard result.chars > 0, let coordinator else {
            session.markRecorded()
            phase = .empty
            return
        }
        let cpm = measuredCpm(session, result)
        let measurement = (variant: run.variant, replay: session.keyLog?.replay(text: result.text), cpm: Optional(cpm))
        if coordinator.recordFinish(session, result, measurement: measurement) {
            showFinal(result, cpm: cpm)
            return
        }
        // Сохранение не удалось: «Повторить» показывает итог, «Отмена» уходит без замера.
        phase = .saving
        coordinator.onRetrySucceeded = { showFinal(result, cpm: cpm) }
        coordinator.onSaveCancelled = onExit
    }

    /// Скорость замера — по полному времени с первого нажатия (паузы внутри не выкидываются).
    private func measuredCpm(_ session: ExerciseSession, _ result: ExerciseResult) -> Double {
        MeasureSpeed.cpm(chars: result.chars, keys: session.keyLog?.keys ?? [],
                         limit: session.measureTimer?.limit,
                         stoppedByTimer: result.chars < result.text.count)
    }

    private func showFinal(_ result: ExerciseResult, cpm: Double) {
        let history = (try? StatsReader(context: modelContext).measurements(variant: run.variant)) ?? []
        phase = .final(Final(outcome: MeasureOutcome(cpm: cpm, accuracy: result.accuracy,
                                                     errors: result.errorCount, chars: result.chars),
                             history: history,
                             measurementId: history.last(where: { $0.date == result.endedAt })?.id ?? history.last?.id))
    }

    /// Уход без итога: замер не сохраняется (и сессия не пишется).
    private func discard() {
        guard let session = coordinator?.session, !session.isRecorded else { return }
        session.stop()
        session.onFinish = nil
        session.markRecorded()
    }

    private func exit() {
        discard()
        onExit()
    }
}
