import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Бесконечный цикл порций адаптивной тренировки. Каждая порция записывается отдельно,
/// вместе с числом открытых букв; брошенная порция записывается при завершении запуска
/// (переход в другой раздел запуск только скрывает).
struct AdaptiveRunnerView: View {
    let language: Language
    let onExit: () -> Void

    private struct PortionSummary {
        let portion: Int
        let cpm: Double
        let accuracy: Double
        let errors: Int
        let newLetter: Character?
        let focus: Character?
    }

    private enum Phase {
        case loading, exercise(Int), saving, summary(PortionSummary)
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var targetCpm = SettingsDefault.adaptiveTargetCpm
    @State private var phase: Phase = .loading
    @State private var coordinator: ExerciseCoordinator?

    private var trainer: AdaptiveTrainer { AdaptiveTrainer(language: language, targetCpm: Double(targetCpm)) }

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
        case .saving:
            // Алерт об ошибке сохранения открыт: дальше только после «Повторить» или «Отмена».
            ProgressView()
        case .exercise(let portion):
            if let session = coordinator?.session {
                ExerciseView(session: session, title: String(localized: "Адаптивная тренировка"),
                             step: portion, totalSteps: 0, targetCpm: Double(targetCpm), onExit: exit)
                    .id(portion)
            }
        case .summary(let summary):
            RunSummaryView(title: String(localized: "Порция \(summary.portion) готова"),
                           cpm: summary.cpm, accuracy: summary.accuracy, errors: summary.errors,
                           lines: lines(for: summary),
                           newAchievements: coordinator?.newAchievements ?? [],
                           fullFlame: coordinator?.newFullFlame,
                           primaryTitle: "Дальше", onPrimary: { begin(summary.portion + 1) },
                           secondaryTitle: "Закончить", onSecondary: exit)
        }
    }

    private func lines(for summary: PortionSummary) -> [String] {
        var result: [String] = []
        if let letter = summary.newLetter {
            let name = String(letter)
            result.append(String(localized: "Открыта новая буква: \(name)"))
        }
        if let focus = summary.focus {
            let name = String(focus)
            result.append(String(localized: "Фокус: \(name)"))
        }
        return result
    }

    private func prepare() {
        guard coordinator == nil else { return }
        let coordinator = ExerciseCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                                     reminders: reminders)
        coordinator.onExitAfterAlert = onExit
        self.coordinator = coordinator
        begin(1)
    }

    private func begin(_ portion: Int) {
        guard let coordinator, let generator = library.planners[language]?.generator else { return }
        coordinator.onRetrySucceeded = nil
        coordinator.onSaveCancelled = nil
        let reader = StatsReader(context: modelContext)
        let trainer = self.trainer
        let count = (try? reader.unlockedCount(language: language)) ?? AdaptiveTrainer.initialLetters
        let stats = (try? reader.keyMastery(language: language)) ?? [:]
        let unlocked = trainer.unlockedLetters(count: count)
        let focus = trainer.focusLetter(unlocked: unlocked, stats: stats)
        var rng = SystemRandomNumberGenerator()
        let text = trainer.exercise(generator: generator, unlocked: unlocked, focus: focus, rng: &rng)
        let spec = ExerciseSpec(id: portion, kind: .words, title: "Адаптивная тренировка", text: text)
        // В режиме «По курсу» подсказка всегда полная.
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(.full)
        _ = coordinator.start(spec: spec, language: language, mode: .adaptive, lessonId: nil,
                              hint: hint, source: "adaptive") { session, result in
            finish(portion: portion, unlockedBefore: count, session: session, result: result)
        }
        phase = .exercise(portion)
        sound.prewarm()
    }

    /// Число открытых букв до порции, как его прочитала транзакция записи (первое сохранение или повтор).
    private final class BeforeBox { var value: Int? }

    private func finish(portion: Int, unlockedBefore: Int, session: ExerciseSession, result: ExerciseResult) {
        sound.play(.exerciseDone)
        let trainer = self.trainer
        let language = self.language
        let cpm = result.cpm, accuracy = result.accuracy, errors = result.errorCount
        let endedAt = result.endedAt
        // «Новая буква» считается от `before`, который вернул `AdaptiveProgress.record` внутри транзакции,
        // а не от чтения при старте порции: оно могло не удаться или устареть.
        let box = BeforeBox()
        let saved = coordinator?.recordFinish(session, result) { recorder in
            box.value = try AdaptiveProgress.record(recorder: recorder, trainer: trainer, language: language,
                                                    at: endedAt).before
        } ?? false
        if saved {
            showSummary(portion: portion, before: box.value ?? unlockedBefore, cpm: cpm, accuracy: accuracy,
                        errors: errors, saved: true)
            return
        }
        // Сохранение не удалось: итог показываем после «Повторить» (с новой буквой) или «Отмена» (без неё).
        phase = .saving
        coordinator?.onRetrySucceeded = {
            showSummary(portion: portion, before: box.value ?? unlockedBefore, cpm: cpm, accuracy: accuracy,
                        errors: errors, saved: true)
        }
        coordinator?.onSaveCancelled = {
            showSummary(portion: portion, before: box.value ?? unlockedBefore, cpm: cpm, accuracy: accuracy,
                        errors: errors, saved: false)
        }
    }

    private func showSummary(portion: Int, before: Int, cpm: Double, accuracy: Double, errors: Int, saved: Bool) {
        let trainer = self.trainer
        let reader = StatsReader(context: modelContext)
        let after = saved ? ((try? reader.unlockedCount(language: language)) ?? before) : before
        let stats = (try? reader.keyMastery(language: language)) ?? [:]
        let unlocked = trainer.unlockedLetters(count: after)
        phase = .summary(PortionSummary(
            portion: portion, cpm: cpm, accuracy: accuracy, errors: errors,
            newLetter: after > before ? unlocked.last : nil,
            focus: trainer.focusLetter(unlocked: unlocked, stats: stats)))
    }

    private func exit() {
        if coordinator?.exit() ?? true { onExit() }
    }
}
