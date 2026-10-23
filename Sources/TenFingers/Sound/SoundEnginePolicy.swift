import Foundation

/// Когда запускать и останавливать `AVAudioEngine`. Чистая логика без аудио, чтобы её можно было проверить тестами.
/// Работающий движок не даёт Mac уйти в сон по бездействию, поэтому его останавливают после паузы в звуках.
struct SoundEnginePolicy {
    /// Пауза после неудачного запуска, в течение которой новых попыток нет.
    static let retryDelay: TimeInterval = 5
    /// Сколько движок работает без звуков.
    static let idleTimeout: TimeInterval = 15

    private var lastFailure: Date?
    private var lastActivity: Date?

    func canStart(at now: Date) -> Bool {
        guard let lastFailure else { return true }
        return now.timeIntervalSince(lastFailure) >= Self.retryDelay
    }

    mutating func startFailed(at now: Date) { lastFailure = now }
    mutating func startSucceeded() { lastFailure = nil }

    /// Звук проигран или движок только что запущен.
    mutating func noteActivity(at now: Date) { lastActivity = now }
    mutating func engineStopped() { lastActivity = nil }

    /// Через сколько секунд движок пора остановить; `nil`, если останавливать нечего. `0` — пора сейчас.
    func idleDelay(at now: Date) -> TimeInterval? {
        guard let lastActivity else { return nil }
        return max(0, Self.idleTimeout - now.timeIntervalSince(lastActivity))
    }
}
