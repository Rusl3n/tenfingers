import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Цикл упражнений практики по одному источнику. После каждого упражнения — итог с кнопкой «Ещё».
/// Для своего текста позиция сдвигается в той же транзакции, что и запись результата;
/// брошенное упражнение позицию не двигает. Как и в тренировке, запуск при уходе в другой раздел
/// только скрывается, а брошенное упражнение записывается при завершении запуска.
struct PracticeRunnerView: View {
    let run: PracticeRun
    let onExit: () -> Void

    private struct Summary {
        let portion: Int
        let cpm: Double
        let accuracy: Double
        let lines: [String]
        /// Свой текст дочитан до конца: вместо «Ещё» — «Начать сначала».
        let textFinished: Bool
    }

    private enum Phase {
        case loading, exercise(Int), saving, summary(Summary), textFinished
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @State private var phase: Phase = .loading
    @State private var coordinator: ExerciseCoordinator?
    @State private var customTitle = ""
    @State private var customBody = ""
    /// Позиция в своём тексте: начало следующей порции. Сохранённая позиция в базе может отставать,
    /// если сохранение не удалось и пользователь отказался повторять.
    @State private var customOffset = 0
    @State private var lastPortion = 1

    private var language: Language { run.language }

    private var isLibraryExcerpt: Bool {
        if case .library = run.source { true } else { false }
    }

    private var customId: UUID? {
        if case .custom(let id) = run.source { id } else { nil }
    }

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
                // Отрывок классики — одно упражнение: номер порции не показываем (шаг 0).
                ExerciseView(session: session, title: exerciseTitle,
                             step: isLibraryExcerpt ? 0 : portion, totalSteps: 0, targetCpm: nil, onExit: exit)
                    .id(portion)
            }
        case .summary(let summary):
            RunSummaryView(title: summaryTitle(summary),
                           cpm: summary.cpm, accuracy: summary.accuracy, lines: summary.lines,
                           newAchievements: coordinator?.newAchievements ?? [],
                           primaryTitle: primaryTitle(summary),
                           onPrimary: { summary.textFinished ? restart(after: summary.portion) : begin(summary.portion + 1) },
                           secondaryTitle: "Закончить", onSecondary: exit)
        case .textFinished:
            VStack(spacing: 20) {
                Text("Текст пройден").font(.largeTitle.bold())
                Text(customTitle).font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Закончить", action: exit)
                    Button("Начать сначала") { restart(after: lastPortion) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
        }
    }

    // MARK: - Подписи

    private var exerciseTitle: String {
        switch run.source {
        case .frequentWords: String(localized: "Частотные слова")
        case .library(let item): "\(item.title) — \(item.author)"
        case .symbols: String(localized: "Цифры и символы")
        case .custom: customTitle
        }
    }

    private func summaryTitle(_ summary: Summary) -> String {
        if case .library = run.source { return String(localized: "Отрывок готов") }
        let portion = summary.portion
        return String(localized: "Порция \(portion) готова")
    }

    private func primaryTitle(_ summary: Summary) -> LocalizedStringKey {
        if summary.textFinished { return "Начать сначала" }
        if case .library = run.source { return "Ещё раз" }
        return "Ещё"
    }

    // MARK: - Ход

    private func prepare() {
        guard coordinator == nil else { return }
        let coordinator = ExerciseCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                                     reminders: reminders)
        coordinator.onExitAfterAlert = onExit
        self.coordinator = coordinator
        if let id = customId {
            guard let text = fetchCustomText(id) else { return onExit() }
            customTitle = text.title
            customBody = text.body
            customOffset = min(max(text.offset, 0), text.body.count)
        }
        begin(1)
    }

    private func fetchCustomText(_ id: UUID) -> CustomText? {
        try? modelContext.fetch(FetchDescriptor<CustomText>(predicate: #Predicate { $0.id == id })).first
    }

    private func begin(_ portion: Int) {
        guard let coordinator, let generator = library.planners[language]?.generator,
              let allowed = library.courses[language]?.typeableCharacters else { return }
        coordinator.onRetrySucceeded = nil
        coordinator.onSaveCancelled = nil
        lastPortion = portion
        var rng = SystemRandomNumberGenerator()
        let custom = customId == nil ? nil : (body: customBody, offset: customOffset)
        let piece = PracticeTextFactory.text(for: run.source, language: language, allowed: allowed,
                                             generator: generator, custom: custom, rng: &rng)
        guard !piece.text.isEmpty else {
            if customId != nil { phase = .textFinished } else { onExit() }
            return
        }
        let spec = ExerciseSpec(id: portion, kind: .words, title: "Практика", text: piece.text)
        // «По курсу» для практики означает подсказку при ошибке: курсовой уровень здесь не определён.
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(.onError)
        _ = coordinator.start(spec: spec, language: language, mode: .practice, lessonId: nil,
                              hint: hint, source: run.source.recordName) { session, result in
            finish(portion: portion, next: piece.nextOffset, session: session, result: result)
        }
        phase = .exercise(portion)
        sound.prewarm()
    }

    private func finish(portion: Int, next: Int?, session: ExerciseSession, result: ExerciseResult) {
        sound.play(.exerciseDone)
        let cpm = result.cpm, accuracy = result.accuracy
        let id = customId
        let saved = coordinator?.recordFinish(session, result) { recorder in
            guard let id, let next else { return }
            try CustomTextProgress.set(next, forTextWithId: id, recorder: recorder)
        } ?? false
        // Позиция в памяти двигается только вместе с сохранённой: иначе после отказа повторять
        // следующая порция началась бы с места, которого нет в базе.
        if saved {
            if let next { customOffset = next }
            showSummary(portion: portion, cpm: cpm, accuracy: accuracy)
            return
        }
        // Сохранение не удалось: итог показываем после «Повторить» или «Отмена».
        phase = .saving
        coordinator?.onRetrySucceeded = {
            if let next { customOffset = next }
            showSummary(portion: portion, cpm: cpm, accuracy: accuracy)
        }
        coordinator?.onSaveCancelled = { showSummary(portion: portion, cpm: cpm, accuracy: accuracy) }
    }

    private func showSummary(portion: Int, cpm: Double, accuracy: Double) {
        var lines: [String] = []
        var finished = false
        if case .library(let item) = run.source {
            lines.append("\(item.title) — \(item.author)")
        } else if customId != nil {
            finished = customOffset >= customBody.count
            if finished {
                lines.append(String(localized: "Текст пройден"))
            } else {
                let percent = Formatting.percent(CustomTextDraft.progress(offset: customOffset,
                                                                          length: customBody.count))
                lines.append(String(localized: "Пройдено: \(percent)"))
            }
        }
        phase = .summary(Summary(portion: portion, cpm: cpm, accuracy: accuracy, lines: lines,
                                 textFinished: finished))
    }

    /// «Начать сначала»: позиция в тексте обнуляется и сохраняется.
    private func restart(after portion: Int) {
        guard let coordinator, let id = customId else { return }
        let saved = coordinator.commitStandalone { recorder in
            try CustomTextProgress.set(0, forTextWithId: id, recorder: recorder)
        }
        if saved {
            customOffset = 0
            begin(portion + 1)
            return
        }
        phase = .saving
        coordinator.onRetrySucceeded = {
            customOffset = 0
            begin(portion + 1)
        }
        coordinator.onSaveCancelled = { phase = .textFinished }
    }

    private func exit() {
        if coordinator?.exit() ?? true { onExit() }
    }
}
