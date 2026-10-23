import AppKit
import SwiftUI
import TypingCore

struct ExerciseView: View {
    let session: ExerciseSession
    let title: String
    let step: Int
    let totalSteps: Int
    let onExit: () -> Void

    @Environment(KeyboardLayoutService.self) private var layout
    @AppStorage(SettingsKey.speedUnit) private var speedUnit = SpeedUnit.cpm.rawValue
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @State private var monitor: Any?
    @State private var keyboardAreaWidth = 0.0

    private var unit: SpeedUnit { SpeedUnit(rawValue: speedUnit) ?? .cpm }
    private var keyboardUnitValue: Double { KeyboardSizing.clampedUnit(keyboardUnit) }

    var body: some View {
        VStack(spacing: 22) {
            header
            if !session.layoutMismatch, !missingCharacters.isEmpty {
                Label("В текущей раскладке нет символов: \(missingCharacters)",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ProgressView(value: Double(session.engine.position), total: Double(max(session.engine.target.count, 1)))
            TypingTextView(target: session.engine.target, position: session.engine.position,
                           errorAtCursor: session.errorFlash)
            Spacer(minLength: 0)
            if session.hint == .hidden {
                Label("Клавиатура скрыта: печатайте вслепую", systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 22) {
                    KeyboardView(snapshot: layout.snapshot, marks: KeyboardView.marks(for: highlight),
                                 shiftDown: session.shiftDown, unit: CGFloat(keyboardUnitValue))
                    FingerLegend()
                }
                .offset(x: CGFloat(KeyboardSizing.effectiveOffset(requested: keyboardOffset, unit: keyboardUnitValue,
                                                                  availableWidth: keyboardAreaWidth)))
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { keyboardAreaWidth = Double($0) }
            }
        }
        .padding(28)
        .overlay { overlay }
        .onAppear(perform: install)
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
                          errorFlash: session.errorFlash)
    }

    private var header: some View {
        HStack(spacing: 18) {
            Text(title).font(.headline)
            StepDotsView(current: step, total: totalSteps)
            Text("Шаг \(step) из \(totalSteps)").monospacedDigit()
            Spacer()
            Text(unit.format(session.engine.cpm)).monospacedDigit()
            Text(Formatting.percent(session.engine.accuracy)).monospacedDigit()
            Text(Formatting.clock(session.engine.activeTime)).monospacedDigit()
            Text(layout.snapshot.language?.shortName ?? "?")
                .padding(.horizontal, 6)
                .background(session.layoutMismatch ? Color.red.opacity(0.25) : Color.secondary.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 4))
            Button("Выйти", action: onExit)
        }
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var overlay: some View {
        if session.layoutMismatch {
            banner(icon: "keyboard", title: LayoutPrompt.switchTo(session.language),
                   subtitle: String(localized: "Нажатия в другой раскладке не засчитываются"))
        } else if session.isPaused {
            banner(icon: "pause.circle", title: String(localized: "Пауза"),
                   subtitle: String(localized: "Нажмите любую клавишу, чтобы продолжить"))
        }
    }

    private func banner(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34))
            Text(title).font(.title2.bold())
            Text(subtitle).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
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
