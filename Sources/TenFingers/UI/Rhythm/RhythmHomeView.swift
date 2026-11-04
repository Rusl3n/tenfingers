import SwiftData
import SwiftUI
import TypingCore

/// Последний выбор экрана «Ритм» (`UserDefaults`): режим, уровень, стиль. Неизвестные значения — умолчания.
enum RhythmSelection {
    static func mode(_ raw: String) -> RhythmNoteMode { RhythmNoteMode(rawValue: raw) ?? .open }
    static func level(_ raw: String) -> RhythmLevelID { RhythmLevelID(rawValue: raw) ?? .easy }
    static func style(_ raw: String) -> RhythmBeatStyle { RhythmBeatStyle(rawValue: raw) ?? .pulse }

    /// Режим, который показывается выбранным: сохранённый, а если для него нот нет — первый доступный.
    static func effectiveMode(saved: RhythmNoteMode,
                              unavailable: [RhythmNoteMode: RhythmNoteSource.Unavailable]) -> RhythmNoteMode {
        if unavailable[saved] == nil { return saved }
        return RhythmNoteMode.allCases.first { unavailable[$0] == nil } ?? saved
    }
}

/// Экран «Ритм»: режим нот, уровень, стиль бита, рекорды сочетания и «Играть».
struct RhythmHomeView: View {
    let start: (RunKind) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ContentLibrary.self) private var library
    @Environment(SoundPlayer.self) private var sound
    @Environment(ToastCenter.self) private var toasts
    @Environment(ReminderScheduler.self) private var reminders
    @Environment(KeyboardLayoutService.self) private var layout
    @Environment(\.palette) private var palette
    @AppStorage(SettingsKey.activeLanguage) private var activeLanguage = Language.ru.rawValue
    @AppStorage(SettingsKey.rhythmLastMode) private var lastMode = RhythmNoteMode.open.rawValue
    @AppStorage(SettingsKey.rhythmLastLevel) private var lastLevel = RhythmLevelID.easy.rawValue
    @AppStorage(SettingsKey.rhythmLastStyle) private var lastStyle = RhythmBeatStyle.pulse.rawValue
    @State private var coordinator: RhythmCoordinator?
    @State private var unavailable: [RhythmNoteMode: RhythmNoteSource.Unavailable] = [:]
    @State private var records = RhythmRecords.empty
    @State private var endlessRecords = RhythmEndlessRecords.empty
    @State private var latestIsBest = false
    @State private var level = RhythmLevel.preset(.easy)
    @State private var hasSpeedHistory = false

    private var language: Language { Language(rawValue: activeLanguage) ?? .ru }
    private var mode: RhythmNoteMode {
        RhythmSelection.effectiveMode(saved: RhythmSelection.mode(lastMode), unavailable: unavailable)
    }
    private var levelID: RhythmLevelID { RhythmSelection.level(lastLevel) }
    private var style: RhythmBeatStyle { RhythmSelection.style(lastStyle) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Ритм: \(language.displayName)").font(.largeTitle.bold())
                section("Режим нот") { modeRow }
                section("Уровень") {
                    choices(RhythmLevelID.allCases, selected: levelID, title: \.title) { lastLevel = $0.rawValue }
                    Text(levelSummary).font(.callout).foregroundStyle(.secondary)
                }
                section("Стиль бита") {
                    choices(RhythmBeatStyle.allCases, selected: style, title: \.title) { lastStyle = $0.rawValue }
                }
                recordsCard
                Button { play() } label: {
                    Label("Играть", systemImage: "play.fill").frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(unavailable[mode] != nil)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: reload)
        .onChange(of: activeLanguage) { reload() }
        .onChange(of: layout.snapshot) { reload() }
        .onChange(of: lastMode) { refreshRecords() }
        .onChange(of: lastLevel) { refreshRecords() }
    }

    // MARK: - Блоки

    private func section<Content: View>(_ title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private var modeRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(RhythmNoteMode.allCases, id: \.self) { item in
                let reason = unavailable[item].map { RhythmCoordinator.reason($0, mode: item) }
                VStack(spacing: 4) {
                    choiceButton(item.title, isSelected: item == mode, isEnabled: reason == nil) {
                        lastMode = item.rawValue
                    }
                    if let reason {
                        Text(reason).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    private func choices<Item: Hashable>(_ items: [Item], selected: Item, title: KeyPath<Item, String>,
                                         pick: @escaping (Item) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.self) { item in
                choiceButton(item[keyPath: title], isSelected: item == selected, isEnabled: true) { pick(item) }
            }
        }
    }

    private func choiceButton(_ title: String, isSelected: Bool, isEnabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isSelected ? Color.white : (isEnabled ? Color.primary : Color.secondary))
                .background(isSelected ? Color.accentColor : palette.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var levelSummary: String {
        if levelID == .endless {
            return String(localized: "Темп растёт от \(RhythmEndless.startNotesPerMinute) до \(RhythmEndless.ceilingNotesPerMinute) нот в минуту, пока хватает здоровья")
        }
        let tempo = String(localized: "Нот в минуту: \(level.bpm * level.notesPerBeat)")
        if levelID == .personal, !hasSpeedHistory {
            return tempo + " · " + String(localized: "Нет истории скорости: как «Лёгкий»")
        }
        return tempo
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Рекорды").font(.headline)
            if levelID == .endless {
                if let seconds = endlessRecords.bestSeconds, let score = endlessRecords.bestScore {
                    let time = Formatting.minutesSeconds(seconds), points = score.formatted()
                    Text("Лучшее: \(time) · очки: \(points)")
                        .font(.title2.bold()).monospacedDigit()
                } else {
                    Text("Сыграйте в бесконечный режим, чтобы поставить первый рекорд").foregroundStyle(.secondary)
                }
            } else if let score = records.bestScore, let accuracy = records.bestAccuracy, let combo = records.bestCombo {
                HStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 2) {
                        record("Лучшие очки", "\(score)")
                        if latestIsBest {
                            Label("Новый рекорд!", systemImage: "trophy.fill").font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    record("Лучшая точность", Formatting.percent(accuracy))
                    record("Макс. комбо", "\(combo)")
                    if let grade = records.bestGrade {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Лучшая оценка").font(.caption).foregroundStyle(.secondary)
                            Text(grade.rawValue).font(.title2.bold()).foregroundStyle(grade.color)
                        }
                    }
                }
            } else {
                Text("Пройдите трек, чтобы поставить первый рекорд").foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func record(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }
    }

    // MARK: - Данные

    private func reload() {
        let coordinator = self.coordinator ?? RhythmCoordinator.live(
            context: modelContext, sound: sound, toasts: toasts, reminders: reminders, library: library,
            layout: layout)
        self.coordinator = coordinator
        unavailable = coordinator.availability(language: language)
        refreshRecords()
    }

    private func refreshRecords() {
        guard let coordinator else { return }
        records = coordinator.records(language: language, mode: mode, level: levelID)
        endlessRecords = coordinator.endlessRecords(language: language, mode: mode)
        latestIsBest = coordinator.latestSetBest(language: language, mode: mode, level: levelID)
        hasSpeedHistory = coordinator.personalCpm(language: language) != nil
        level = coordinator.level(for: levelID, language: language)
    }

    private func play() {
        guard unavailable[mode] == nil else { return }
        start(.rhythm(RhythmRun(language: language, mode: mode, level: levelID, style: style)))
    }
}
