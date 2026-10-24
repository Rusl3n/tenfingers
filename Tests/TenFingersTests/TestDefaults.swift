import Foundation

/// Папка доменов настроек тестов во временном каталоге пользователя.
private let testDefaultsDirectory: URL = {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TenFingersTests-defaults",
                                                                                   isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}()

/// Отдельный домен `UserDefaults` на тест. Удалять — `removeTestDefaults(name)` в `defer`.
///
/// Имя домена — абсолютный путь во временном каталоге: домен с обычным именем cfprefsd через несколько секунд
/// после выхода процесса записывает в `~/Library/Preferences/<имя>.plist` даже после
/// `removePersistentDomain` (пустой файл), и они там копились сотнями. С путём файл появляется только здесь.
func makeTestDefaults(_ prefix: String) -> (defaults: UserDefaults, name: String) {
    let name = testDefaultsDirectory.appendingPathComponent(prefix + UUID().uuidString).path
    return (UserDefaults(suiteName: name)!, name)
}

/// Удаляет домен настроек теста: очищает его и убирает файл, если он уже записан.
func removeTestDefaults(_ name: String) {
    precondition(name.hasPrefix(testDefaultsDirectory.path + "/"), "не домен теста: \(name)")
    UserDefaults().removePersistentDomain(forName: name)
    try? FileManager.default.removeItem(atPath: name + ".plist")
}
