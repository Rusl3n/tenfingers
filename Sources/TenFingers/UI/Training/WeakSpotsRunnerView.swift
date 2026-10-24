import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Суммарные показатели сессии «Слабые места»: пока чистое время меньше пяти минут, идут новые порции.
struct WeakSpotsSessionTotals: Equatable {
    private(set) var seconds = 0.0
    private(set) var chars = 0
    private(set) var errors = 0

    mutating func add(seconds: Double, chars: Int, errors: Int) {
        self.seconds += seconds
        self.chars += chars
        self.errors += errors
    }

    mutating func add(_ result: ExerciseResult) {
        add(seconds: result.activeSeconds, chars: result.chars, errors: result.errorCount)
    }

    var cpm: Double { seconds > 0 ? Double(chars) / seconds * 60 : 0 }
    var accuracy: Double { chars > 0 ? 1 - Double(errors) / Double(chars) : 1 }
    var isComplete: Bool { seconds >= WeakSpots.sessionSeconds }
}

/// Пятиминутная сессия: порции по 250 знаков идут одна за другой с паузой в секунду.
struct WeakSpotsRunnerView: View {
    let language: Language
    let onExit: () -> Void

    static let portionLength = 250

    private struct FinalSummary {
        let totals: WeakSpotsSessionTotals
        let keys: [Character]
    }

    private enum Phase {
        case loading, exercise(Int), saving, gap(Int), final(FinalSummary)
    }

    private struct GapTimer: Equatable {
        let portion: Int
        let isVisible: Bool
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @Environment(RunPresence.self) private var presence: RunPresence?
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var targetCpm = SettingsDefault.adaptiveTargetCpm
    @State private var phase: Phase = .loading
    @State private var coordinator: ExerciseCoordinator?
    @State private var totals = WeakSpotsSessionTotals()
    @State private var usedKeys: [Character] = []

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
                ExerciseView(session: session, title: String(localized: "Слабые места"),
                             step: portion, totalSteps: 0, targetCpm: Double(targetCpm), onExit: exit)
                    .id(portion)
            }
        case .gap(let next):
            VStack(spacing: 16) {
                ProgressView()
                Text("Ещё порция…").font(.title3).foregroundStyle(.secondary)
                Button("Закончить", action: finishSession)
            }
            // Пока запуск скрыт, следующая порция не начинается: отсчёт идёт заново после возврата.
            .task(id: GapTimer(portion: next, isVisible: presence?.isVisible ?? true)) {
                guard presence?.isVisible ?? true else { return }
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { begin(next) }
            }
        case .final(let summary):
            let keys = summary.keys.map(String.init).joined(separator: ", ")
            RunSummaryView(title: String(localized: "Тренировка завершена"),
                           leadingMetrics: [.init(title: "Время", value: Formatting.clock(summary.totals.seconds))],
                           speedTitle: "Средняя скорость",
                           cpm: summary.totals.cpm, accuracy: summary.totals.accuracy,
                           lines: keys.isEmpty ? [] : [String(localized: "Клавиши: \(keys)")],
                           primaryTitle: "Готово", onPrimary: onExit)
        }
    }

    private func prepare() {
        guard coordinator == nil else { return }
        let coordinator = ExerciseCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                                     reminders: reminders)
        coordinator.onExitAfterAlert = finishOrExit
        self.coordinator = coordinator
        begin(1)
    }

    private func begin(_ portion: Int) {
        guard let coordinator, let generator = library.planners[language]?.generator else { return }
        coordinator.onRetrySucceeded = nil
        coordinator.onSaveCancelled = nil
        let reader = StatsReader(context: modelContext)
        let thresholdMs = trainer.thresholdMs
        // Текст и цели — только из открытых букв: неоткрытые в слабые места не попадают.
        let open = (try? reader.openLetters(language: language, course: library.courses[language]))
            ?? Set(trainer.unlockedLetters(count: AdaptiveTrainer.initialLetters))
        let keys = WeakSpotsFocus.keys((try? reader.keyMastery(language: language)) ?? [:],
                                       letters: open, thresholdMs: thresholdMs)
        let bigrams = WeakSpotsFocus.bigrams((try? reader.bigramMastery(language: language)) ?? [:],
                                             letters: open, thresholdMs: thresholdMs)
        for key in keys where !usedKeys.contains(key) { usedKeys.append(key) }
        var rng = SystemRandomNumberGenerator()
        var text = generator.focusedWords(letters: open, focusKeys: keys, focusBigrams: bigrams,
                                          length: Self.portionLength, rng: &rng)
        if text.isEmpty {
            // Настоящих слов из открытых букв нет: псевдослова, как в адаптивной тренировке.
            text = generator.words(allowed: open.union([" "]), focus: Set(keys), length: Self.portionLength,
                                   capitalRate: 0, minimumRealWords: AdaptiveTrainer.minimumRealWords, rng: &rng)
        }
        let spec = ExerciseSpec(id: portion, kind: .words, title: "Слабые места", text: text)
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(.full)
        _ = coordinator.start(spec: spec, language: language, mode: .weak, lessonId: nil,
                              hint: hint, source: "weak") { session, result in
            finish(portion: portion, session: session, result: result)
        }
        phase = .exercise(portion)
        sound.prewarm()
    }

    private func finish(portion: Int, session: ExerciseSession, result: ExerciseResult) {
        sound.play(.exerciseDone)
        totals.add(result)
        if coordinator?.recordFinish(session, result) ?? false {
            advance(after: portion)
            return
        }
        // Сохранение не удалось: следующая порция не стартует под алертом.
        // «Повторить» продолжает сессию, «Отмена» показывает итог.
        phase = .saving
        coordinator?.onRetrySucceeded = { advance(after: portion) }
        coordinator?.onSaveCancelled = { finishOrExit() }
    }

    private func advance(after portion: Int) {
        if totals.isComplete {
            finishSession()
        } else {
            phase = .gap(portion + 1)
        }
    }

    private func finishSession() {
        phase = .final(FinalSummary(totals: totals, keys: usedKeys))
    }

    /// Итог, если что-то успели напечатать, иначе просто выход.
    private func finishOrExit() {
        if totals.chars > 0 { finishSession() } else { onExit() }
    }

    /// «Выйти» посреди порции: начатая порция тоже идёт в итог.
    private func exit() {
        guard let coordinator else { return onExit() }
        if let session = coordinator.session, !session.isRecorded, session.shouldRecordAbandon {
            totals.add(session.makeResult())
        }
        if coordinator.exit() { finishOrExit() }
    }
}
