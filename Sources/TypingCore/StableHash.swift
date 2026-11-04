import Foundation

/// Стабильный хэш строки: результат не зависит от запуска и версии системы (в отличие от `Hashable`), поэтому годится
/// для детерминированного выбора — фраз напоминаний и испытаний недели и месяца.
enum StableHash {
    /// FNV-1a, 64 бита, по байтам UTF-8.
    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
