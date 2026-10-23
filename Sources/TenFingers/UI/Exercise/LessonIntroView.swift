import SwiftUI
import TypingCore

/// Знакомство с новыми клавишами: каким пальцем и куда тянуться. Подсветка мигает между исходной и новой клавишей.
struct LessonIntroView: View {
    let lesson: Lesson
    let language: Language
    let onStart: () -> Void

    @Environment(KeyboardLayoutService.self) private var layout
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @State private var showTarget = false
    @State private var keyboardAreaWidth = 0.0

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
            }
            KeyboardView(snapshot: layout.snapshot, marks: marks, unit: CGFloat(keyboardUnitValue))
                .offset(x: CGFloat(KeyboardSizing.effectiveOffset(requested: keyboardOffset, unit: keyboardUnitValue,
                                                                  availableWidth: keyboardAreaWidth)))
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { keyboardAreaWidth = Double($0) }
            Button("Начать", action: onStart)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
        }
        .padding(28)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(800))
                showTarget.toggle()
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
