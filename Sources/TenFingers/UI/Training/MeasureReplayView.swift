import SwiftData
import SwiftUI
import TypingCore

/// Запрос на повтор: открывает лист по `SpeedMeasurement.id`.
struct ReplayRequest: Identifiable, Equatable {
    let measurementId: UUID
    var id: UUID { measurementId }
}

/// Чистая часть экрана повтора: подписи темпов, нажатия для кончиков пальцев.
enum MeasureReplayModel {
    /// Подпись темпа: «Как было», «×1,5», «×2», «×3», «Мастер».
    static func title(_ tempo: ReplayTempo) -> String {
        switch tempo {
        case .asRecorded: String(localized: "Как было")
        case .x1_5: String(localized: "×1,5")
        case .x2: String(localized: "×2")
        case .x3: String(localized: "×3")
        case .master: String(localized: "Мастер")
        }
    }

    /// Нажатия кончиков вровень с `keys`. Знака нет в раскладке — `nil`. Пробел жмёт большой палец руки, противоположной
    /// последней букве (как учит первый урок); до первой буквы — правый.
    static func presses(keys: [ReplayKey], snapshot: LayoutSnapshot) -> [HandsPress?] {
        var lastHand: Hand = .left
        return keys.map { key in
            guard let press = snapshot.keyPress(for: key.typed) else { return nil }
            if press.keyCode == KeyboardGeometry.space {
                return HandsPress(keyCode: press.keyCode, shift: false, spaceHalf: lastHand == .left ? .right : .left)
            }
            if let hand = FingerMap.finger(for: press.keyCode)?.hand { lastHand = hand }
            return HandsPress(keyCode: press.keyCode, shift: press.shift)
        }
    }
}

/// Повтор замера: текст и клавиатура с кончиками пальцев. «Как было» — один в один с ошибками и паузами, остальные
/// темпы — те же знаки без ошибок ровно с выбранной скоростью. Смена темпа начинает сначала.
struct MeasureReplayView: View {
    let measurementId: UUID
    let onClose: () -> Void

    private struct Loaded {
        let replay: MeasureReplay
        let cpm: Double
    }

    private enum Phase {
        case loading, unavailable, ready(Loaded)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(KeyboardLayoutService.self) private var layout
    @Environment(RunPresence.self) private var presence: RunPresence?
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @AppStorage(SettingsKey.fingerAnimation) private var fingerAnimation = SettingsDefault.fingerAnimation
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .loading
    @State private var tempo: ReplayTempo = .asRecorded
    @State private var playback: ReplayPlayback?
    @State private var sequence: HandsSequence?

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }
    private var unitValue: Double { KeyboardSizing.clampedUnit(keyboardUnit) }
    private var moves: Bool { HandsOverlayModel.movesTips(setting: fingerAnimation, reduceMotion: reduceMotion) }
    private var isVisible: Bool { presence?.isVisible ?? true }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Запись набора").font(.title2.bold())
                Spacer()
                Button("Закрыть", action: onClose).keyboardShortcut(.cancelAction)
            }
            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView("Записи набора нет", systemImage: "play.slash")
            case .ready(let loaded):
                content(loaded)
            }
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 620)
        .task { load() }
        .onChange(of: isVisible) { _, visible in if !visible { pause() } }
        .onDisappear(perform: pause)
        // Конец проигрывания: ждём остаток и замираем на последнем кадре; крутится только пока идёт показ.
        .task(id: sequence.flatMap { $0.isRunning ? $0.startedAt : nil }) {
            guard let sequence, sequence.isRunning else { return }
            let left = sequence.playback.endMs - sequence.elapsedMs(now: .now)
            try? await Task.sleep(for: .milliseconds(max(Int(left.rounded(.up)), 0)))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func content(_ loaded: Loaded) -> some View {
        VStack(spacing: 18) {
            textView
            ScaledKeyboardView(snapshot: layout.snapshot, unit: unitValue,
                               hands: HandsState(moves: moves, sequence: sequence))
                .keyboardPlacement(offset: keyboardOffset, unit: unitValue)
            tempoPicker(loaded)
            HStack(spacing: 12) {
                Button {
                    toggle()
                } label: {
                    Label(sequence?.isRunning == true ? "Пауза" : "Играть",
                          systemImage: sequence?.isRunning == true ? "pause.fill" : "play.fill")
                }
                .keyboardShortcut(.space, modifiers: [])
                Button { restart(loaded) } label: { Label("Сначала", systemImage: "backward.end.fill") }
            }
        }
    }

    /// Текст, как в упражнении: набранное серым, курсор, красный после ошибки. Часы идут только во время показа.
    @ViewBuilder private var textView: some View {
        if let playback, let sequence {
            if sequence.isRunning {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    text(playback.frame(atMs: sequence.elapsedMs(now: context.date)), playback)
                }
            } else {
                text(playback.frame(atMs: sequence.frozenAtMs ?? 0), playback)
            }
        } else {
            Color.clear.frame(minHeight: 60)
        }
    }

    private func text(_ frame: ReplayPlayback.Frame, _ playback: ReplayPlayback) -> some View {
        TypingTextView(target: playback.text, position: frame.position, errorAtCursor: frame.errorAtCursor)
    }

    private func tempoPicker(_ loaded: Loaded) -> some View {
        HStack(spacing: 8) {
            Text("Темп").foregroundStyle(.secondary)
            ForEach(ReplayTempo.allCases, id: \.self) { item in
                Button {
                    guard item != tempo else { return }
                    tempo = item
                    restart(loaded)
                } label: {
                    VStack(spacing: 2) {
                        Text(MeasureReplayModel.title(item)).font(.callout.weight(.medium))
                        Text(unit.format(Double(item.cpm(base: loaded.cpm)))).font(.caption).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(item == tempo ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == tempo ? .isSelected : [])
            }
        }
    }

    // MARK: - Ход

    private func load() {
        let id = measurementId
        var descriptor = FetchDescriptor<SpeedMeasurement>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let row = try? modelContext.fetch(descriptor).first, let data = row.replay,
              let replay = MeasureReplay(data: data), !replay.keys.isEmpty
        else {
            phase = .unavailable
            return
        }
        let loaded = Loaded(replay: replay, cpm: row.cpm)
        phase = .ready(loaded)
        restart(loaded)
    }

    /// Новая запись нажатий выбранного темпа, показ с начала.
    private func restart(_ loaded: Loaded) {
        let keys = tempo.keys(of: loaded.replay, baseCpm: loaded.cpm)
        let built = ReplayPlayback(text: loaded.replay.text, keys: keys)
        playback = built
        sequence = HandsSequence(id: UUID(), playback: built,
                                 presses: MeasureReplayModel.presses(keys: keys, snapshot: layout.snapshot),
                                 startedAt: .now, frozenAtMs: nil)
    }

    private func toggle() {
        guard var current = sequence, case .ready(let loaded) = phase else { return }
        if current.isRunning {
            pause()
        } else if (current.frozenAtMs ?? 0) >= current.playback.endMs {
            restart(loaded)
        } else {
            current.startedAt = Date.now.addingTimeInterval(-(current.frozenAtMs ?? 0) / 1000)
            current.frozenAtMs = nil
            sequence = current
        }
    }

    private func pause() {
        guard var current = sequence, current.isRunning else { return }
        current.frozenAtMs = min(current.elapsedMs(now: .now), current.playback.endMs)
        sequence = current
    }

    private func finish() {
        guard var current = sequence, current.isRunning else { return }
        current.frozenAtMs = current.playback.endMs
        sequence = current
    }
}
