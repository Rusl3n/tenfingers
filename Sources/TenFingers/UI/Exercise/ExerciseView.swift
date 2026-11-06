import AppKit
import SwiftUI
import TypingCore

struct ExerciseView: View {
    let session: ExerciseSession
    let title: String
    let step: Int
    let totalSteps: Int
    var targetCpm: Double?
    /// Вместо индикатора скорости — цель текстом («Цель: 0 ошибок» у занятия на точность пальца).
    var goalText: String? = nil
    /// Урок продолжен с этого шага (с единицы): над текстом плашка с кнопкой «Начать урок заново».
    var resumedStep: Int?
    /// Допуск ошибок шага (§3): рядом с индикатором скорости «Ошибки: N из M», красным при переборе; `nil` — допуска нет.
    var errorLimit: Int? = nil
    /// Строка над текстом упражнения («Обгоните себя: 142 зн/мин → цель 149 зн/мин» у шагов «Ускорения»).
    var banner: String? = nil
    /// Замер по таймеру: вместо времени упражнения — оставшееся, а полоса показывает прошедшую долю.
    var timeText: String? = nil
    var progressOverride: Double? = nil
    var onRestart: (() -> Void)?
    let onExit: () -> Void

    @Environment(KeyboardLayoutService.self) private var layout
    /// Нет в окружении (превью, тесты) — экран считается видимым.
    @Environment(RunPresence.self) private var presence: RunPresence?
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @AppStorage(SettingsKey.spaceThumbHint) private var spaceThumbHint = SettingsDefault.spaceThumbHint
    @State private var monitor: Any?

    private var isVisible: Bool { presence?.isVisible ?? true }
    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }
    private var keyboardUnitValue: Double { KeyboardSizing.clampedUnit(keyboardUnit) }

    /// Проценты в шапке упражнения — только вне курса (в курсе — одни ошибки, §5).
    nonisolated static func showsAccuracyPercent(mode: ExerciseMode) -> Bool { mode != .course }

    var body: some View {
        VStack(spacing: 22) {
            header
            if let resumedStep, let onRestart {
                HStack(spacing: 12) {
                    Label("Продолжаем с шага \(resumedStep) из \(totalSteps)", systemImage: "arrow.forward.circle")
                    Spacer()
                    Button("Начать урок заново", action: onRestart)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            if !session.layoutMismatch, !missingCharacters.isEmpty {
                Label("В текущей раскладке нет символов: \(missingCharacters)",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let banner {
                Text(banner)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let progressOverride {
                ProgressView(value: progressOverride, total: 1)
            } else {
                ProgressView(value: Double(session.engine.position), total: Double(max(session.engine.target.count, 1)))
            }
            TypingTextView(target: session.engine.target, position: session.engine.position,
                           errorAtCursor: session.errorFlash)  // занимает свободную высоту
            if session.hint == .hidden {
                Label("Клавиатура скрыта: печатайте вслепую", systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 22) {
                    let highlight = highlight
                    ScaledKeyboardView(snapshot: layout.snapshot, marks: KeyboardView.marks(for: highlight),
                                       shiftDown: session.shiftDown, unit: keyboardUnitValue,
                                       spaceHalf: KeyboardView.spaceHalf(for: highlight))
                    FingerLegend()
                }
                .keyboardPlacement(offset: keyboardOffset, unit: keyboardUnitValue)
            }
        }
        .padding(28)
        .overlay { overlay }
        // Монитор клавиш стоит только пока запуск виден: скрытый запуск остаётся в иерархии на паузе.
        .onAppear(perform: visibilityChanged)
        .onChange(of: isVisible) { visibilityChanged() }
        .onDisappear(perform: uninstall)
        .onChange(of: layout.snapshot) { _, snapshot in session.layoutLanguage = snapshot.language }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            session.pauseForFocusLoss()
        }
    }

    private var missingCharacters: String {
        layout.snapshot.missingCharacters(in: session.spec.text).map(String.init).joined(separator: " ")
    }

    private var highlight: KeyHighlight? {
        KeyHint.highlight(expected: session.engine.expected, snapshot: layout.snapshot, hint: session.hint,
                          positionHasError: session.engine.currentPositionHasError,
                          errorFlash: session.errorFlash, previous: previousCharacter, spaceThumb: spaceThumbHint)
    }

    /// Символ перед курсором: от него зависит, каким большим пальцем жать пробел.
    private var previousCharacter: Character? {
        let position = session.engine.position
        return position > 0 && position <= session.engine.target.count ? session.engine.target[position - 1] : nil
    }

    /// Три колонки: боковые равной ширины, поэтому скорость стоит в центре окна при любой длине заголовка.
    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            HStack(spacing: 18) {
                Text(title).font(.headline).lineLimit(1)
                if totalSteps > 0 {
                    StepDotsView(current: step, total: totalSteps)
                    Text("Шаг \(step) из \(totalSteps)").monospacedDigit()
                } else if step > 0 {
                    Text("Порция \(step)").monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let goalText {
                Text(goalText).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                SpeedIndicatorView(cpm: session.engine.cpm, target: targetCpm,
                                   typedChars: session.engine.position,
                                   activeSeconds: session.engine.activeTime, unit: unit)
            }
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    let errors = session.engine.errorPositions.count
                    if let errorLimit {
                        Text(ErrorCounter.text(errors: errors, limit: errorLimit)).monospacedDigit()
                            .foregroundStyle(ErrorCounter.isOver(errors: errors, limit: errorLimit) ? Color.red : .secondary)
                    } else {
                        Text("Ошибки: \(errors)").monospacedDigit()
                    }
                    if Self.showsAccuracyPercent(mode: session.mode) {
                        Text(Formatting.percent(session.engine.accuracy)).font(.caption).monospacedDigit()
                    }
                }
                Text(timeText ?? Formatting.clock(session.engine.activeTime)).monospacedDigit()
                Text(layout.snapshot.language?.shortName ?? "?")
                    .padding(.horizontal, 6)
                    .background(session.layoutMismatch ? Color.red.opacity(0.25) : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 4))
                Button("Выйти", action: onExit)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private var overlay: some View {
        if session.layoutMismatch {
            LayoutMismatchBanner(language: session.language)
        } else if session.isPaused {
            OverlayBanner(icon: "pause.circle", title: String(localized: "Пауза"),
                          subtitle: String(localized: "Нажмите любую клавишу, чтобы продолжить"))
        }
    }

    private func visibilityChanged() {
        session.onPauseChanged = { [presence] paused, reason in presence?.pauseChanged(paused, reason: reason) }
        if isVisible {
            install()
        } else {
            uninstall()
            session.pauseForHiding()
        }
    }

    private func install() {
        uninstall()
        session.layoutLanguage = layout.snapshot.language
        session.syncModifiers(NSEvent.modifierFlags)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [session] event in
            let isFlags = event.type == .flagsChanged
            let flags = event.modifierFlags
            let characters = isFlags ? nil : event.characters
            let isRepeat = isFlags ? false : event.isARepeat
            let keyCode = event.keyCode
            let timestamp = event.timestamp
            let consumed = MainActor.assumeIsolated { () -> Bool in
                if isFlags {
                    session.handleFlags(flags)
                    return false
                }
                return session.handleKey(characters: characters, keyCode: keyCode,
                                         modifiers: flags, timestamp: timestamp, isRepeat: isRepeat)
            }
            return consumed ? nil : event
        }
    }

    private func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
