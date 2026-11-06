import SwiftUI
import TypingCore

/// Знакомство с новыми клавишами: каким пальцем и куда тянуться. Кончики пальцев по очереди нажимают новые клавиши (без анимации — подсветка мигает между исходной и новой).
struct LessonIntroView: View {
    let lesson: Lesson
    let language: Language
    /// Самый первый урок курса: рассказать, каким большим пальцем жать пробел.
    var teachesSpaceThumb = false
    let onStart: () -> Void
    /// Просмотр с карты курса: без запуска урока, вместо «Начать» — «Готово».
    var isPreview = false
    /// «Выйти» до начала урока (как в упражнении): урок закрывается и не остаётся «Текущим уроком».
    var onExit: (() -> Void)? = nil

    @Environment(KeyboardLayoutService.self) private var layout
    @Environment(RunPresence.self) private var presence: RunPresence?
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @AppStorage(SettingsKey.fingerAnimation) private var fingerAnimation = SettingsDefault.fingerAnimation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTarget = false
    @State private var handsPress: HandsPress?
    @State private var pressStartedAt = Date.distantPast
    @State private var animationPaused = false
    /// Какая половина пробела подсвечена в показе большого пальца.
    @State private var spaceHalf: Hand = .left

    private var movesTips: Bool { HandsOverlayModel.movesTips(setting: fingerAnimation, reduceMotion: reduceMotion) }

    private struct LoopID: Hashable {
        let visible: Bool
        let moves: Bool
        let paused: Bool
    }

    private var keyboardUnitValue: Double { KeyboardSizing.clampedUnit(keyboardUnit) }

    private var layoutMismatch: Bool {
        guard let layoutLanguage = layout.snapshot.language else { return false }
        return layoutLanguage != language
    }

    /// Новые символы, которых нет в текущей раскладке, через пробел.
    private var missing: String {
        guard !layoutMismatch else { return "" }
        return layout.snapshot.missingCharacters(in: lesson.newCharacters).map(String.init).joined(separator: " ")
    }

    private var presses: [(Character, TypingCore.KeyPress)] {
        lesson.newCharacters.compactMap { c in layout.snapshot.keyPress(for: c).map { (c, $0) } }
    }

    var body: some View {
        VStack(spacing: 24) {
            Text(lesson.localizedTitle).font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 10) {
                ForEach(presses, id: \.0) { character, press in
                    Text(line(character, press)).font(.title3)
                }
                if layoutMismatch {
                    Label(LayoutPrompt.switchTo(language), systemImage: "keyboard")
                        .font(.title3)
                        .foregroundStyle(.orange)
                } else if !missing.isEmpty {
                    Label("В текущей раскладке нет символов: \(missing)",
                          systemImage: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                if lesson.capitals == true {
                    Text("Заглавная буква: зажмите Shift мизинцем противоположной руки и нажмите букву.")
                        .font(.title3)
                }
                if teachesSpaceThumb {
                    Text("Пробел — большим пальцем руки, противоположной последней букве: так обе руки работают по очереди и печать быстрее")
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            ScaledKeyboardView(snapshot: layout.snapshot, marks: marks, unit: keyboardUnitValue,
                               spaceHalf: teachesSpaceThumb ? spaceHalf : nil,
                               hands: HandsState(press: handsPress, startedAt: pressStartedAt, moves: movesTips))
                .keyboardPlacement(offset: keyboardOffset, unit: keyboardUnitValue)
            HStack(spacing: 12) {
                if let onExit, !isPreview {
                    Button("Выйти", action: onExit)
                }
                if movesTips {
                    Button {
                        animationPaused.toggle()
                    } label: {
                        Label(animationPaused ? "Продолжить" : "Пауза анимации",
                              systemImage: animationPaused ? "play.fill" : "pause.fill")
                    }
                }
                Button(isPreview ? "Готово" : "Начать", action: onStart)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .onExitCommand { if isPreview { onStart() } }
        // Пока запуск скрыт другим разделом (или анимация на паузе), ничего не крутится.
        .task(id: LoopID(visible: presence?.isVisible ?? true, moves: movesTips, paused: animationPaused)) {
            guard presence?.isVisible ?? true, !animationPaused else { return }
            if movesTips {
                showTarget = false
                defer { handsPress = nil }
                var index = 0
                while !Task.isCancelled {
                    guard !presses.isEmpty else {
                        try? await Task.sleep(for: .milliseconds(700))
                        continue
                    }
                    let press = presses[index % presses.count].1
                    handsPress = HandsPress(keyCode: press.keyCode, shift: press.shift)
                    pressStartedAt = Date()
                    try? await Task.sleep(for: .milliseconds(Int(FingerPress.durationMs)))
                    handsPress = nil
                    try? await Task.sleep(for: .milliseconds(700))
                    index += 1
                }
            } else {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(800))
                    showTarget.toggle()
                }
            }
        }
        // Половины пробела по очереди, по секунде.
        .task(id: (presence?.isVisible ?? true) && teachesSpaceThumb) {
            guard presence?.isVisible ?? true, teachesSpaceThumb else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                spaceHalf = spaceHalf == .left ? .right : .left
            }
        }
    }

    private var marks: [UInt16: KeyMark] {
        var marks: [UInt16: KeyMark] = [:]
        for (_, press) in presses {
            let home = FingerMap.finger(for: press.keyCode)?.homeKeyCode ?? press.keyCode
            marks[showTarget ? press.keyCode : home] = .intro
            if press.shift && showTarget { marks[FingerMap.shiftKey(for: press.keyCode)] = .intro }
        }
        if lesson.capitals == true {
            marks[KeyboardGeometry.leftShift] = .intro
            marks[KeyboardGeometry.rightShift] = .intro
        }
        if teachesSpaceThumb { marks[KeyboardGeometry.space] = .intro }
        return marks
    }

    private func line(_ character: Character, _ press: TypingCore.KeyPress) -> String {
        let finger = FingerMap.finger(for: press.keyCode)
        let home = finger.flatMap { layout.snapshot.plain[$0.homeKeyCode] }?.uppercased() ?? ""
        let reach = ReachDescription.describe(keyCode: press.keyCode, shape: layout.snapshot.shape)
        let key = String(character).uppercased()
        let name = finger?.displayName ?? ""
        let isHome = finger?.homeKeyCode == press.keyCode
        let from = isHome ? reach : String(localized: "от \(home) \(reach)")
        return press.shift
            ? String(localized: "«\(key)» — \(name), с Shift: \(from)")
            : String(localized: "«\(key)» — \(name): \(from)")
    }
}
