import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Занятие по пальцу («Точность пальца» — 3 порции, «Скорость пальца» — 4): порции идут одна за другой с итогом
/// порции («Ещё» / «Хватит»), в конце — итоговая сводка. Запись — `mode = weak`, `source = finger:<палец>:<занятие>`.
/// Начатая и брошенная порция записывается при завершении запуска (переход в другой раздел запуск только скрывает).
struct FingerRunnerView: View {
    let run: FingerRun
    let onExit: () -> Void

    private struct PortionSummary {
        let portion: Int
        let cpm: Double
        let accuracy: Double
        let errors: Int
    }

    private struct FinalSummary {
        let totals: WeakSpotsSessionTotals
    }

    private enum Phase {
        case loading, exercise(Int), saving, summary(PortionSummary), final(FinalSummary)
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @Environment(KeyboardLayoutService.self) private var layout
    @AppStorage(SettingsKey.hintMode) private var hintMode = HintMode.auto.rawValue
    @AppStorage(SettingsKey.adaptiveTargetCpm) private var adaptiveTargetCpm = SettingsDefault.adaptiveTargetCpm
    @State private var phase: Phase = .loading
    @State private var coordinator: ExerciseCoordinator?
    /// Порции текущего круга (в круге 3 или 4); «Ещё» после итога круга собирает новый.
    @State private var portions: [ExerciseSpec] = []
    /// Цель занятия на скорость: скорость пальца × 1,1 на начало круга; у точности её нет.
    @State private var targetCpm: Double?
    @State private var totals = WeakSpotsSessionTotals()
    /// Карточки, уже показанные на итоге порции: на итоговой сводке круга они не повторяются.
    @State private var shownAchievements: Set<String> = []
    @State private var flameShown = false

    /// «Цель: 0 ошибок» вместо индикатора скорости у занятия на точность; у скорости — индикатор с целью.
    static func goalText(_ drill: FingerDrill) -> String? {
        drill == .accuracy ? String(localized: "Цель: 0 ошибок") : nil
    }

    private var drillTitle: String {
        run.drill == .accuracy ? String(localized: "Точность пальца") : String(localized: "Скорость пальца")
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
                ExerciseView(session: session, title: drillTitle, step: portion, totalSteps: 0, targetCpm: targetCpm,
                             goalText: Self.goalText(run.drill), onExit: exit)
                    .id(portion)
            }
        case .summary(let summary):
            RunSummaryView(title: String(localized: "Порция \(summary.portion) готова"),
                           cpm: summary.cpm, accuracy: summary.accuracy, errors: summary.errors,
                           lines: [fingerLine],
                           newAchievements: coordinator?.newAchievements ?? [],
                           fullFlame: coordinator?.newFullFlame,
                           primaryTitle: "Ещё", onPrimary: { begin(summary.portion + 1) },
                           secondaryTitle: "Хватит", onSecondary: finishRound)
        case .final(let summary):
            finalView(summary)
        }
    }

    /// Итоговая сводка круга. Из плана — ровно его порции: «Ещё раз» нет, дальше ведёт план.
    private func finalView(_ summary: FinalSummary) -> RunSummaryView {
        let planned = run.portions != nil
        return RunSummaryView(title: String(localized: "Тренировка завершена"),
                              leadingMetrics: [.init(title: "Время", value: Formatting.clock(summary.totals.seconds))],
                              speedTitle: "Средняя скорость",
                              cpm: summary.totals.cpm, accuracy: summary.totals.accuracy,
                              errors: summary.totals.errors,
                              lines: [fingerLine],
                              newAchievements: (coordinator?.runAchievements ?? [])
                                  .filter { !shownAchievements.contains($0.id) },
                              fullFlame: flameShown ? nil : coordinator?.runFullFlame,
                              primaryTitle: "Готово", onPrimary: onExit,
                              secondaryTitle: planned ? nil : "Ещё раз", onSecondary: planned ? nil : { startRound() })
    }

    private var fingerLine: String {
        let name = run.finger.displayName
        return String(localized: "Палец: \(name)")
    }

    private func prepare() {
        guard coordinator == nil else { return }
        let coordinator = ExerciseCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                                     reminders: reminders)
        coordinator.onExitAfterAlert = finishOrExit
        self.coordinator = coordinator
        startRound()
    }

    /// Новый круг: свежие порции, цель скорости по сегодняшним данным, пустые итоги и копилки ачивок круга.
    private func startRound() {
        guard let coordinator, let generator = library.planners[run.language]?.generator else { return }
        let reader = StatsReader(context: modelContext)
        let language = run.language
        let trainer = AdaptiveTrainer(language: language, targetCpm: Double(adaptiveTargetCpm))
        // Текст — только из открытых букв: неоткрытые в занятие не попадают.
        let open = (try? reader.openLetters(language: language, course: library.courses[language],
                                            legacy: library.legacyCourses[language]))
            ?? Set(trainer.unlockedLetters(count: AdaptiveTrainer.initialLetters))
        let fingerOf = (try? reader.fingerLetters(language: language, layout: layout.fingerOf(language: language)))
            ?? layout.fingerOf(language: language)
        var rng = SystemRandomNumberGenerator()
        portions = Self.planPortions(limit: run.portions) {
            FingerTraining.portions(run.drill, finger: run.finger, open: open, fingerOf: fingerOf,
                                    generator: generator, rng: &rng)
        }
        // Занятия нет (букв пальца среди открытых нет): не оставлять экран на загрузке.
        guard !portions.isEmpty else { return onExit() }
        targetCpm = run.drill == .speed
            ? reports(reader, fingerOf: fingerOf, thresholdMs: trainer.thresholdMs)
                .first { $0.finger == run.finger }
                .flatMap { FingerTraining.targetCpm(speedCpm: $0.speedCpm) }
                .map(Double.init)
            : nil
        totals = WeakSpotsSessionTotals()
        shownAchievements = []
        flameShown = false
        coordinator.resetRunAchievements()
        begin(1)
    }

    /// Порции круга: вне плана (`limit == nil`) — один круг; из плана — ровно `limit`: круг обрезается или
    /// дополняется следующими кругами, номера порций сквозные. Пустой круг (букв пальца нет) — пусто.
    static func planPortions(limit: Int?, round: () -> [ExerciseSpec]) -> [ExerciseSpec] {
        var specs = round()
        guard let limit, !specs.isEmpty else { return specs }
        while specs.count < limit {
            let more = round()
            guard !more.isEmpty else { break }
            specs += more
        }
        return specs.prefix(limit).enumerated().map { index, spec in
            ExerciseSpec(id: index + 1, kind: spec.kind, title: spec.title, text: spec.text, connected: spec.connected)
        }
    }

    private func reports(_ reader: StatsReader, fingerOf: [Character: Finger], thresholdMs: Double) -> [FingerReport] {
        (try? reader.fingerReports(language: run.language, fingerOf: fingerOf, thresholdMs: thresholdMs)) ?? []
    }

    private func begin(_ portion: Int) {
        guard let coordinator, portions.indices.contains(portion - 1) else { return }
        coordinator.onRetrySucceeded = nil
        coordinator.onSaveCancelled = nil
        let spec = portions[portion - 1]
        let hint = (HintMode(rawValue: hintMode) ?? .auto).resolve(.full)
        _ = coordinator.start(spec: spec, language: run.language, mode: .weak, lessonId: nil, hint: hint,
                              source: FingerTraining.source(run.finger, run.drill), planSlot: run.planSlot) { session, result in
            finish(portion: portion, session: session, result: result)
        }
        phase = .exercise(portion)
        sound.prewarm()
    }

    private func finish(portion: Int, session: ExerciseSession, result: ExerciseResult) {
        sound.play(.exerciseDone)
        totals.add(result)
        let summary = PortionSummary(portion: portion, cpm: result.cpm, accuracy: result.accuracy,
                                     errors: result.errorCount)
        if coordinator?.recordFinish(session, result) ?? false {
            advance(after: summary)
            return
        }
        // Сохранение не удалось: следующая порция не стартует под алертом.
        // «Повторить» продолжает занятие, «Отмена» показывает итог.
        phase = .saving
        coordinator?.onRetrySucceeded = { advance(after: summary) }
        coordinator?.onSaveCancelled = { finishOrExit() }
    }

    /// После последней порции круга — итоговая сводка, иначе итог порции с «Ещё» / «Хватит».
    private func advance(after summary: PortionSummary) {
        if summary.portion >= portions.count {
            finishRound()
        } else {
            shownAchievements.formUnion((coordinator?.newAchievements ?? []).map(\.id))
            flameShown = flameShown || coordinator?.newFullFlame != nil
            phase = .summary(summary)
        }
    }

    private func finishRound() {
        phase = .final(FinalSummary(totals: totals))
    }

    /// Итог, если что-то успели напечатать, иначе просто выход.
    private func finishOrExit() {
        if totals.chars > 0 { finishRound() } else { onExit() }
    }

    /// «Выйти» посреди порции: начатая порция тоже идёт в итог.
    private func exit() {
        guard let coordinator else { return onExit() }
        if let session = coordinator.session, !session.isRecorded, session.shouldRecordAbandon {
            totals.add(session.makeResult())
        }
        // Итог (с карточками ачивок) будет, если что-то успели напечатать.
        if coordinator.exit(announce: totals.chars > 0) { finishOrExit() }
    }
}
