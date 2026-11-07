import Foundation
import Testing
@testable import TenFingers

/// Файлы, где `.standard` разрешён: единственная точка доступа и системная тема (`AppleInterfaceStyle`).
private let standardAllowedFiles: Set<String> = ["ProfileDefaults.swift", "Theme.swift"]

private func sourceFiles() -> [URL] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Sources/TenFingers", directoryHint: .isDirectory)
    let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    return (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
}

/// Код без строк-комментариев.
private func codeLines(_ url: URL) -> [(number: Int, text: String)] {
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    return text.components(separatedBy: "\n").enumerated().compactMap { index, line in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("//") ? nil : (index + 1, line)
    }
}

@Test func noStandardDefaultsOutsideAllowedFiles() throws {
    var offenders: [String] = []
    for url in sourceFiles() where !standardAllowedFiles.contains(url.lastPathComponent) {
        for (number, line) in codeLines(url) {
            // `store: .standard` у `@AppStorage` ключей Mac проверяется отдельным тестом; `.standard` у ReminderTiming — не настройки.
            let cleaned = line.replacingOccurrences(of: "store: .standard", with: "")
                .replacingOccurrences(of: "ReminderTiming = .standard", with: "")
            if cleaned.range(of: #"\.standard\b"#, options: .regularExpression) != nil
                && !cleaned.contains("standardizedFileURL") {
                offenders.append("\(url.lastPathComponent):\(number)")
            }
        }
    }
    #expect(offenders.isEmpty, "Настройки только через ProfileDefaults: \(offenders)")
}

@Test func deviceLevelAppStorageKeysUseStandardStore() throws {
    var offenders: [String] = []
    let keys = ProfileDefaults.deviceKeys
    for url in sourceFiles() {
        for (number, line) in codeLines(url) where line.contains("@AppStorage(SettingsKey.") {
            let isDevice = keys.contains { key in
                SettingsKeyNames.names[key].map { line.contains("@AppStorage(SettingsKey.\($0)") } ?? false
            }
            if isDevice && !line.contains("store: .standard") { offenders.append("\(url.lastPathComponent):\(number)") }
        }
    }
    #expect(offenders.isEmpty, "Ключ уровня Mac без store: .standard: \(offenders)")
}

/// Имя свойства `SettingsKey` для значения ключа (у всех ключей Mac они совпадают).
private enum SettingsKeyNames {
    static let names: [String: String] = Dictionary(uniqueKeysWithValues: ProfileDefaults.deviceKeys.map { ($0, $0) })
}

@Test func deviceKeysAreRoutedToDeviceDomain() {
    for key in ProfileDefaults.deviceKeys {
        #expect(ProfileDefaults.store(forKey: key) === ProfileDefaults.device, "\(key)")
    }
    for key in [SettingsKey.themeMode, SettingsKey.dailyGoalMinutes, SettingsKey.profileNickname, SettingsKey.adultHumor,
                SettingsKey.reminderHour, SettingsKey.activeLanguage] {
        #expect(ProfileDefaults.store(forKey: key) === ProfileDefaults.current, "\(key)")
    }
    #expect(!ProfileDefaults.deviceKeys.contains(SettingsKey.onboardingCompleted))
}

@Test func profileKeyGoesToProfileDomainAndDeviceKeyDoesNot() {
    let (profile, name) = makeTestDefaults("test.profiledefaults.")
    let (mac, macName) = makeTestDefaults("test.profiledefaults.mac.")
    defer { removeTestDefaults(name); removeTestDefaults(macName) }
    #expect(ProfileDefaults.store(forKey: SettingsKey.dailyGoalMinutes, profile: profile, device: mac) === profile)
    #expect(ProfileDefaults.store(forKey: SettingsKey.uiScale, profile: profile, device: mac) === mac)
    // Без записи в глобальный `current`: домен профиля приложения парится с доменом Mac.
    #expect(ProfileDefaults.deviceStore(pairedWith: ProfileDefaults.current) === ProfileDefaults.device)
}

@Test func pairedDeviceStoreIsSameDomainForForeignDefaults() {
    let (other, name) = makeTestDefaults("test.profiledefaults.other.")
    defer { removeTestDefaults(name) }
    #expect(ProfileDefaults.deviceStore(pairedWith: other) === other)
}
