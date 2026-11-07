import Foundation

/// «Сдвиг звука» игры «Ритм» (§5): на сколько миллисекунд бит сдвинут относительно нот. Отрицательный сдвиг — бит
/// раньше (для наушников с задержкой), положительный — позже; в петле: кадр
/// `(t − leadIn − сдвиг) mod длина`. На оценку нажатий не влияет. Хранится одним ключом `rhythmSoundOffsetMs`
/// (`Int`, мс); поле не архивируется: задержка зависит от наушников этого Mac.
enum RhythmSoundOffset {
    static let range = -200...200
    static let step = 10
    static let defaultMs = 0

    /// Значение в границах диапазона и кратное шагу (ближайшее); мусор из `UserDefaults` не ломает игру.
    static func clamped(_ ms: Int) -> Int {
        let stepped = Int((Double(ms) / Double(step)).rounded()) * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }

    /// Сохранённый сдвиг, мс; нет значения или значение не того вида — 0.
    static func milliseconds(in defaults: UserDefaults = ProfileDefaults.device) -> Int {
        guard let stored = defaults.object(forKey: SettingsKey.rhythmSoundOffsetMs) as? Int else { return defaultMs }
        return clamped(stored)
    }

    /// Сдвиг для часов игры, секунды.
    static func seconds(in defaults: UserDefaults = ProfileDefaults.device) -> TimeInterval {
        Double(milliseconds(in: defaults)) / 1000
    }

    /// «+30 мс», «−30 мс», «0 мс».
    static func label(_ ms: Int) -> String {
        let value = clamped(ms)
        let text = value > 0 ? "+\(value)" : value < 0 ? "−\(-value)" : "0"
        return String(localized: "\(text) мс")
    }
}
