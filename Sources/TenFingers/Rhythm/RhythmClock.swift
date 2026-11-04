import Foundation

/// Часы захода: время трека `t`. Во время отсчёта `t < 0`, дальше идёт 1:1 с `uptime`, пауза замораживает.
/// Чистая структура: время (`ProcessInfo.systemUptime`) передаётся снаружи.
struct RhythmClock {
    let countdown: TimeInterval

    /// Опорная точка: в `anchorUptime` время трека было `anchorTrack`; пока не стоит пауза, `t` идёт от неё 1:1.
    private var anchorUptime: TimeInterval?
    private var anchorTrack: TimeInterval = 0
    /// Замороженное значение на паузе.
    private var frozen: TimeInterval?
    /// Дальше всего дошедшее время трека: после повторного отсчёта оно не растёт, пока трек не догонит его.
    private var highWater: TimeInterval = 0

    init(countdown: TimeInterval = 3) {
        self.countdown = countdown
    }

    var isPaused: Bool { frozen != nil }

    /// Начинает отсчёт: в `uptime` время трека равно `−countdown`.
    mutating func start(at uptime: TimeInterval) {
        anchorUptime = uptime
        anchorTrack = -countdown
        frozen = nil
        highWater = 0
    }

    mutating func pause(at uptime: TimeInterval) {
        guard anchorUptime != nil, frozen == nil else { return }
        let current = trackTime(at: uptime)
        highWater = max(highWater, current)
        frozen = current
    }

    /// Продолжает с повторным отсчётом: за `countdown` секунд время трека доходит до замороженного значения.
    /// Если пауза пришла на первый отсчёт (значение < 0), отсчёт начинается заново, а не удлиняется.
    mutating func resume(at uptime: TimeInterval) {
        guard let frozen else { return }
        anchorTrack = frozen >= 0 ? frozen - countdown : -countdown
        anchorUptime = uptime
        self.frozen = nil
    }

    func trackTime(at uptime: TimeInterval) -> TimeInterval {
        if let frozen { return frozen }
        guard let anchorUptime else { return -countdown }
        return anchorTrack + max(0, uptime - anchorUptime)
    }

    /// Секунды самого трека (≥ 0) без отсчётов и пауз.
    func activeSeconds(at uptime: TimeInterval) -> TimeInterval {
        max(0, highWater, trackTime(at: uptime))
    }
}
