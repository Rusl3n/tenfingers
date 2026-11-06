import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Занятие «Слова с ошибками»: одно упражнение (~200 знаков) из слов списка, затем итог.
/// Записывается как обычная тренировка (`ExerciseMode.errorWords`); брошенное упражнение записывается при выходе.
struct ErrorWordsRunnerView: View {
    let language: Language
    /// Пункт плана дня (`TrainingRun.planSlot`): пишется в сессию.
    var planSlot: PlanSlot? = nil
    /// Длина текста, знаков: из плана дня — как у «Повтора».
    var chars = ErrorWordsRunnerView.targetChars
    let onExit: () -> Void

    static let targetChars = 200

    private struct FinalSummary {
        let totals: WeakSpotsSessionTotals
    }

    private enum Phase {
        case loading, unavailable, exercise, saving, final(FinalSummary)
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var targetCpm = SettingsDefault.adaptiveTargetCpm
    @AppStorage(SettingsKey.trainingLetters) private var trainingLetters = SettingsDefault.trainingLetters
    @State private var phase: Phase = .loading
    @State private var coordinator: ExerciseCoordinator?
    @State private var totals = WeakSpotsSessionTotals()

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
        case .loading, .saving:
            ProgressView()
        case .unavailable:
            VStack(spacing: 16) {
                Text("Пока мало слов").font(.title2.bold())
                Button("Готово", action: onExit).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        case .exercise:
            if let session = coordinator?.session {
                ExerciseView(session: session, title: String(localized: "Слова с ошибками"),
                             step: 1, totalSteps: 0, targetCpm: Double(targetCpm), onExit: exit)
            }
        case .final(let summary):
            RunSummaryView(title: String(localized: "Тренировка завершена"),
                           leadingMetrics: [.init(title: "Время", value: Formatting.clock(summary.totals.seconds))],
                           speedTitle: "Средняя скорость",
                           cpm: summary.totals.cpm, accuracy: summary.totals.accuracy, errors: summary.totals.errors,
                           newAchievements: coordinator?.runAchievements ?? [],
                           fullFlame: coordinator?.runFullFlame,
                           primaryTitle: "Готово", onPrimary: onExit)
        }
    }

    private func prepare() {
        guard coordinator == nil else { return }
        let coordinator = ExerciseCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                                     reminders: reminders)
        coordinator.onExitAfterAlert = finishOrExit
        self.coordinator = coordinator
        begin()
    }

    private func begin() {
        guard let coordinator else { return }
        let reader = StatsReader(context: modelContext)
        let open = (try? reader.openLetters(language: language, course: library.courses[language],
                                            legacy: library.legacyCourses[language]))
            ?? Set(AdaptiveTrainer(language: language).unlockedLetters(count: AdaptiveTrainer.initialLetters))
        let allowed = (TrainingLetters(rawValue: trainingLetters) ?? .open).letters(open: open, language: language)
        let entries = (try? reader.errorWords(language: language)) ?? []
        var rng = SystemRandomNumberGenerator()
        guard let text = ErrorWordsText.make(entries: entries, allowed: allowed, targetChars: chars,
                                             seed: rng.next()) else {
            phase = .unavailable
            return
        }
        let spec = ExerciseSpec(id: 1, kind: .words, title: "Слова с ошибками", text: text)
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(.full)
        _ = coordinator.start(spec: spec, language: language, mode: .errorWords, lessonId: nil,
                              hint: hint, source: "errorWords", planSlot: planSlot) { session, result in
            finish(session: session, result: result)
        }
        phase = .exercise
        sound.prewarm()
    }

    private func finish(session: ExerciseSession, result: ExerciseResult) {
        sound.play(.exerciseDone)
        totals.add(result)
        if coordinator?.recordFinish(session, result) ?? false {
            phase = .final(FinalSummary(totals: totals))
            return
        }
        // Сохранение не удалось: «Повторить» показывает итог, «Отмена» — тоже.
        phase = .saving
        coordinator?.onRetrySucceeded = { phase = .final(FinalSummary(totals: totals)) }
        coordinator?.onSaveCancelled = { finishOrExit() }
    }

    private func finishOrExit() {
        if totals.chars > 0 { phase = .final(FinalSummary(totals: totals)) } else { onExit() }
    }

    private func exit() {
        guard let coordinator else { return onExit() }
        if let session = coordinator.session, !session.isRecorded, session.shouldRecordAbandon {
            totals.add(session.makeResult())
        }
        if coordinator.exit(announce: totals.chars > 0) { finishOrExit() }
    }
}
