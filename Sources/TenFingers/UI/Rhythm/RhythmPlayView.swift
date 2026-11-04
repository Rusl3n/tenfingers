import AppKit
import SwiftData
import SwiftUI
import TypingCore

/// Нажатие, переданное из монитора клавиш.
struct RhythmKeyInput {
    let characters: String?
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let isRepeat: Bool
    let timestamp: TimeInterval
    /// Событие пришло в лист, алерт или панель (ошибка сохранения): клавиши игре не отдаются.
    let isBlocked: Bool
}

/// Локальный монитор `keyDown` (как в `ExerciseView`); обработчик сообщает, забрал ли он событие.
@MainActor
final class RhythmKeyMonitor {
    private var monitor: Any?

    func install(_ handler: @escaping @MainActor (RhythmKeyInput) -> Bool) {
        uninstall()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let characters = event.characters
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags
            let isRepeat = event.isARepeat
            let timestamp = event.timestamp
            let consumed = MainActor.assumeIsolated { () -> Bool in
                let target = EscapeTarget(window: event.window)
                let blocked = target.isSheetOrPanel || target.hasAttachedSheet
                return handler(RhythmKeyInput(characters: characters, keyCode: keyCode, modifiers: modifiers,
                                              isRepeat: isRepeat, timestamp: timestamp, isBlocked: blocked))
            }
            return consumed ? nil : event
        }
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Заход игры «Ритм»: отсчёт, поле, пауза по Esc и итоги. Скрытый запуск (другой раздел) и потеря фокуса окна ставят
/// паузу; выход с экрана записывает прерванный заход, если оценена хотя бы одна нота.
struct RhythmPlayView: View {
    let run: RhythmRun
    let onExit: () -> Void
    /// «Потренировать слабые» на итогах: запуск слабых мест с буквами захода.
    var onTrainWeak: ([Character]) -> Void = { _ in }

    private enum Phase {
        case loading, unavailable(String), playing, paused, saving, result(RhythmSummary)
    }

    @Environment(ContentLibrary.self) private var library
    @Environment(\.modelContext) private var modelContext
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @Environment(KeyboardLayoutService.self) private var layout
    /// Нет в окружении (превью, тесты) — экран считается видимым.
    @Environment(RunPresence.self) private var presence: RunPresence?
    @Environment(\.palette) private var palette
    @State private var phase: Phase = .loading
    @State private var coordinator: RhythmCoordinator?
    @State private var model: RhythmPlayModel?
    @State private var keys = RhythmKeyMonitor()
    /// Рекорды сочетания до этого захода: по ним итог отмечает новый рекорд.
    @State private var previousRecords = RhythmRecords.empty
    /// Прежние рекорды бесконечного режима (до этого захода) — для «Нового рекорда!» по времени.
    @State private var previousEndlessRecords = RhythmEndlessRecords.empty
    /// Звук игры выключен кнопкой на поле; помнится между заходами.
    @AppStorage(SettingsKey.rhythmMuted) private var muted = false

    private var isVisible: Bool { presence?.isVisible ?? true }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear(perform: appear)
            .onChange(of: isVisible) { visibilityChanged() }
            // На итогах меню разворачивается, «Ещё раз» сворачивает его.
            .onChange(of: isResult) { presence?.resultChanged(isResult) }
            .onDisappear(perform: disappear)
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                pause(.focusLoss)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                abandonSilently(quitting: true)
            }
            .background {
                if let coordinator { Color.clear.saveErrorAlert(coordinator.saver) }
            }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .loading, .saving:
            ProgressView()
        case .unavailable(let reason):
            VStack(spacing: 16) {
                Image(systemName: "music.note").font(.system(size: 34)).foregroundStyle(.secondary)
                Text(reason).font(.title3)
                Button("Назад", action: onExit).buttonStyle(.borderedProminent)
            }
        case .playing, .paused:
            field
        case .result(let summary):
            RhythmResultView(summary: summary, newAchievements: coordinator?.saver.newAchievements ?? [],
                             fullFlame: coordinator?.saver.newFullFlame, onAgain: begin, onBack: onExit,
                             onTrainWeak: onTrainWeak)
        }
    }

    private var isResult: Bool {
        if case .result = phase { true } else { false }
    }

    private var isPaused: Bool {
        if case .paused = phase { true } else { false }
    }

    private var field: some View {
        // На паузе кадры не идут: поле стоит, как было. Кадры только рисуют и зовут `tick`; оценка идёт по часам.
        TimelineView(.animation(paused: isPaused)) { timeline in
            let uptime = ProcessInfo.processInfo.systemUptime
            RhythmFieldCanvas(frame: model?.frame(at: uptime) ?? RhythmFieldFrame())
                .onChange(of: timeline.date) { frameTick() }
        }
        .overlay(alignment: .topTrailing) {
            if Self.beatEnabled { muteButton.padding(12) }
        }
        .overlay {
            if isPaused { if layoutMismatch { layoutPrompt } else { pauseMenu } }
        }
        // Раскладку отслеживает и экран на паузе: возврат на нужный язык снимает паузу `.layout` сам.
        .onChange(of: layout.snapshot.language) { applyLayout() }
    }

    /// Раскладка есть и не совпадает с языком захода (по тому же признаку, что у модели).
    private var layoutMismatch: Bool {
        RhythmPlayModel.mismatch(layout.snapshot.language, run.language)
    }

    private var layoutPrompt: some View {
        VStack(spacing: 14) {
            LayoutMismatchBanner(language: run.language)
            Button("Выйти", action: exit)
        }
    }

    /// Выключает и включает звук игры (бит и щелчки), не трогая звуки приложения. Клавиатура остаётся у игры.
    private var muteButton: some View {
        Button {
            muted.toggle()
            model?.setMuted(muted)
        } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.title3)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .help(muted ? Text("Включить звук игры") : Text("Выключить звук игры"))
        .accessibilityLabel(muted ? Text("Включить звук игры") : Text("Выключить звук игры"))
    }

    private var pauseMenu: some View {
        VStack(spacing: 14) {
            Text("Пауза").font(.title2.bold())
            Button("Продолжить", action: resume)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            Button("Заново", action: restart)
            Button("Выйти", action: exit)
        }
        .frame(minWidth: 180)
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Жизненный цикл

    private func appear() {
        guard coordinator == nil else { return }
        coordinator = RhythmCoordinator.live(context: modelContext, sound: sound, toasts: toasts,
                                             reminders: reminders, library: library, layout: layout)
        sound.prewarm()
        begin()
    }

    private func disappear() {
        presence?.resultChanged(false)
        keys.uninstall()
        abandonSilently(quitting: false)
        model?.stop(at: ProcessInfo.processInfo.systemUptime)
        sound.stop()
    }

    /// Новый заход с новым зерном (первый, «Ещё раз», «Заново»).
    private func begin() {
        guard let coordinator else { return }
        do {
            let (chart, fingers) = try coordinator.prepare(run: run)
            previousRecords = coordinator.records(language: run.language, mode: run.mode, level: run.level)
            previousEndlessRecords = coordinator.endlessRecords(language: run.language, mode: run.mode)
            let audio = RhythmAudio(style: run.style, bpm: chart.level.bpm, enabled: Self.beatEnabled,
                                  endless: chart.level.id == .endless)
            audio.isMuted = muted
            let next = RhythmPlayModel(run: run, chart: chart, fingers: fingers, audio: audio,
                                       soundOffset: Self.soundOffset, layoutLanguage: layout.snapshot.language)
            model = next
            coordinator.saver.onRetrySucceeded = nil
            coordinator.saver.onSaveCancelled = nil
            phase = .playing
            next.start(at: ProcessInfo.processInfo.systemUptime)
            // Раскладка чужая — отсчёта нет: заход уже на паузе `.layout`, подсказка видна, а старт — сам.
            if next.isPaused { phase = .paused }
            if isVisible {
                installMonitor()
                if next.isPaused { presence?.pauseChanged(true, reason: .layout) }
            } else {
                next.pause(at: ProcessInfo.processInfo.systemUptime, reason: .hidden)
            }
            if !isVisible { phase = .paused }
        } catch {
            phase = .unavailable(RhythmCoordinator.reason(error, mode: run.mode))
        }
    }

    /// Бит играет, пока включён хотя бы один звук приложения.
    private static var beatEnabled: Bool {
        SoundSettings.activeEvents.contains { SoundSettings.isEnabled($0) }
    }

    /// «Сдвиг звука» (−200…+200 мс в настройках, здесь секунды) сдвигает бит относительно нот; на оценку не влияет.
    private static var soundOffset: TimeInterval { RhythmSoundOffset.seconds() }

    private func visibilityChanged() {
        if isVisible {
            if case .playing = phase { installMonitor() }
            if case .paused = phase { installMonitor() }
            applyLayout()   // раскладка могла сменяться, пока запуск был скрыт
        } else {
            keys.uninstall()
            if case .paused = phase { model?.markHidden() } else { pause(.hidden) }
        }
    }

    // MARK: - Пауза и выход

    /// Причина паузы доходит до `RootView`: Esc разворачивает боковую панель, потеря фокуса и скрытие её не трогают.
    private func pause(_ reason: PauseReason) {
        guard case .playing = phase, let model else { return }
        model.pause(at: ProcessInfo.processInfo.systemUptime, reason: reason)
        phase = .paused
        presence?.pauseChanged(true, reason: reason)
    }

    private func resume() {
        guard case .paused = phase, let model else { return }
        // Пока раскладка чужая, пауза остаётся: продолжит сам возврат раскладки (`applyLayout`).
        guard let reason = model.resume(at: ProcessInfo.processInfo.systemUptime) else { return }
        phase = .playing
        presence?.pauseChanged(false, reason: reason)
    }

    /// Раскладка сменилась: чужая ставит паузу `.layout`, возврат снимает её с обычным отсчётом 3-2-1.
    private func applyLayout() {
        guard isVisible, let model, !model.isEnded else { return }
        switch model.applyLayout(layout.snapshot.language, at: ProcessInfo.processInfo.systemUptime) {
        case .none: break
        case .paused:
            phase = .paused
            presence?.pauseChanged(true, reason: .layout)
        case .resumed:
            phase = .playing
            presence?.pauseChanged(false, reason: .layout)
        }
    }

    /// «Заново»: текущий заход записывается прерванным (решение 11), начинается новый с новым зерном.
    private func restart() {
        let reason = model?.pauseReason ?? .escape
        abandonSilently(quitting: false)
        presence?.pauseChanged(false, reason: reason)
        begin()
    }

    /// «Выйти»: прерванный заход записывается; при ошибке сохранения — алерт, после него выход.
    private func exit() {
        guard let model, let coordinator else { return onExit() }
        keys.uninstall()
        model.stop(at: ProcessInfo.processInfo.systemUptime)
        model.isRecorded = true
        coordinator.saver.onExitAfterAlert = onExit
        let canLeave = coordinator.abandon(game: model.game, chart: model.chart, run: run, clock: model.clock,
                                           startedAt: model.startedAt,
                                           wrongLayoutAttempted: model.wrongLayoutAttempted, interactive: true)
        if canLeave { onExit() }
    }

    /// Уход без кнопки (другое занятие, закрытие окна, «Заново»): прерванный заход пишется молча.
    private func abandonSilently(quitting: Bool) {
        guard let model, let coordinator, !model.isRecorded else { return }
        model.isRecorded = true
        let uptime = ProcessInfo.processInfo.systemUptime
        model.stop(at: uptime)
        coordinator.abandon(game: model.game, chart: model.chart, run: run, clock: model.clock,
                            startedAt: model.startedAt, wrongLayoutAttempted: model.wrongLayoutAttempted,
                            quitting: quitting, uptime: uptime)
    }

    // MARK: - Кадры и ввод

    private func frameTick() {
        guard case .playing = phase, let model else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        model.tick(at: uptime)
        if model.isEnded { finish(model) }
    }

    /// Заход закончен (пройден или проигран): запись и экран итога; при ошибке сохранения итог — после алерта.
    private func finish(_ model: RhythmPlayModel) {
        guard !model.isRecorded, let coordinator else { return }
        model.isRecorded = true
        let uptime = ProcessInfo.processInfo.systemUptime
        model.stop(at: uptime)
        keys.uninstall()
        let summary = RhythmSummary.make(game: model.game, chart: model.chart, run: run, previous: previousRecords,
                                       previousEndless: previousEndlessRecords)
        if summary.cleared, !muted { sound.play(.exerciseDone) }
        let saved = coordinator.finish(game: model.game, chart: model.chart, run: run, clock: model.clock,
                                       startedAt: model.startedAt,
                                       wrongLayoutAttempted: model.wrongLayoutAttempted, uptime: uptime)
        if case .saved = saved {
            phase = .result(summary)
            return
        }
        // Сохранение не удалось: итог — после «Повторить» или «Отмена».
        phase = .saving
        coordinator.saver.onRetrySucceeded = { phase = .result(summary) }
        coordinator.saver.onSaveCancelled = { phase = .result(summary) }
    }

    private func installMonitor() {
        keys.install { input in handle(input) }
    }

    /// Esc — пауза и продолжение; буквы — нажатия по нотам. Повтор клавиши и клавиши с Command и Control игре не нужны.
    private func handle(_ input: RhythmKeyInput) -> Bool {
        guard isVisible, !input.isBlocked else { return false }
        guard input.modifiers.intersection([.command, .control]).isEmpty else { return false }
        if input.keyCode == ExerciseSession.escapeKeyCode {
            if !input.isRepeat {
                switch phase {
                case .playing: pause(.escape)
                case .paused: resume()
                default: return false
                }
            }
            return true
        }
        switch phase {
        case .paused:
            // В чужой раскладке попытка ввода считается (счётчик, как у упражнений), но игре не достаётся.
            if !input.isRepeat, let character = Self.character(of: input.characters), let model {
                _ = model.press(character, at: input.timestamp)
            }
            // Return нажимает «Продолжить»; остальные клавиши на паузе не нужны никому.
            return !Self.isReturn(input.keyCode)
        case .playing:
            if !input.isRepeat, let character = Self.character(of: input.characters), let model {
                press(character, at: input.timestamp, model: model)
            }
            return true
        default:
            return false
        }
    }

    private func press(_ character: Character, at timestamp: TimeInterval, model: RhythmPlayModel) {
        guard let event = model.press(character, at: timestamp), !muted else { return }
        if let judgement = event.judgement {
            sound.play(judgement.isHit ? .keyClick : .error)
        } else if event.isStray {
            sound.play(.error)
        }
    }

    private static func isReturn(_ keyCode: UInt16) -> Bool { keyCode == 36 || keyCode == 76 }

    /// Символ нажатия: строчный, печатаемый. Служебные клавиши (стрелки, Return, Tab, Backspace) — `nil`.
    static func character(of characters: String?) -> Character? {
        guard let text = characters?.lowercased(), text.count == 1, let character = text.first,
              let scalar = character.unicodeScalars.first else { return nil }
        let isControl = scalar.value < 0x20 || scalar.value == 0x7F || (0xF700...0xF8FF).contains(scalar.value)
        return isControl ? nil : character
    }
}
