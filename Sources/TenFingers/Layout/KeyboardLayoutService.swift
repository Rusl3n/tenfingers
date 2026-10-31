import Carbon
import Foundation
import Observation
import TypingCore

/// Текущая раскладка системы; обновляется при переключении источника ввода.
/// Все вызовы TIS (в том числе статические помощники) изолированы на главном акторе: TIS не потокобезопасен.
@MainActor @Observable
final class KeyboardLayoutService {
    private(set) var snapshot: LayoutSnapshot = .empty
    @ObservationIgnored private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else { return }
        snapshot = Self.snapshot(for: source, shape: Self.currentShape())
    }

    /// Буква языка → палец по текущей раскладке (`FingerMap` по клавише буквы). Букв, которых в раскладке нет
    /// (например, раскладка другого языка), в карте нет.
    func fingerOf(language: Language) -> [Character: Finger] {
        Self.fingerOf(snapshot: snapshot, language: language)
    }

    nonisolated static func fingerOf(snapshot: LayoutSnapshot, language: Language) -> [Character: Finger] {
        var result: [Character: Finger] = [:]
        for letter in language.letters {
            if let press = snapshot.keyPress(for: letter), let finger = FingerMap.finger(for: press.keyCode) {
                result[letter] = finger
            }
        }
        return result
    }

    static func currentShape() -> KeyboardShape {
        KBGetLayoutType(Int16(LMGetKbdType())) == PhysicalKeyboardLayoutType(kKeyboardISO) ? .iso : .ansi
    }

    static func source(withID id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.first
    }

    static func snapshot(for source: TISInputSource, shape: KeyboardShape) -> LayoutSnapshot {
        let id = stringProperty(source, kTISPropertyInputSourceID) ?? ""
        let languages = arrayProperty(source, kTISPropertyInputSourceLanguages)
        let language = languages.first.flatMap(Language.init(inputSourceLanguage:))
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return LayoutSnapshot(id: id, language: language, shape: shape, plain: [:], shifted: [:])
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var plain: [UInt16: String] = [:]
        var shifted: [UInt16: String] = [:]
        for code in KeyboardGeometry.characterKeys(for: shape) {
            plain[code] = translate(data, code, shift: false)
            shifted[code] = translate(data, code, shift: true)
        }
        return LayoutSnapshot(id: id, language: language, shape: shape, plain: plain, shifted: shifted)
    }

    private static func translate(_ data: Data, _ keyCode: UInt16, shift: Bool) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return nil }
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let modifiers: UInt32 = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
            let status = UCKeyTranslate(
                layout, keyCode, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars
            )
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: chars, count: length)
        }
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private static func arrayProperty(_ source: TISInputSource, _ key: CFString) -> [String] {
        guard let raw = TISGetInputSourceProperty(source, key) else { return [] }
        return (Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String]) ?? []
    }
}
