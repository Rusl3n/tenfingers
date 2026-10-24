import Foundation

/// Версия приложения из `Info.plist` собранного `.app`.
/// `scripts/build-app.sh` кладёт туда `VERSION`, номер сборки (число коммитов) и короткий хэш коммита (`TFGitCommit`).
/// При `swift run` и в тестах этих ключей нет, тогда версия — «dev».
enum AppVersion {
    static let versionKey = "CFBundleShortVersionString"
    static let buildKey = "CFBundleVersion"
    static let commitKey = "TFGitCommit"

    static var current: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    /// «0.3.0 (сборка 128)», без сборки — «0.3.0», без версии — «dev».
    static func display(info: [String: Any]) -> String {
        compose(info: info, includeCommit: false)
    }

    /// Короткая форма для боковой панели: «0.3.0-dev (89)», без версии — «dev».
    static func short(info: [String: Any]) -> String {
        guard let version = value(info, versionKey) else { return "dev" }
        guard let build = value(info, buildKey) else { return version }
        return "\(version) (\(build))"
    }

    /// Мелкая строка внизу настроек: «Версия 0.3.0 (сборка 128, abc1234)».
    static func settingsLine(info: [String: Any]) -> String {
        let text = compose(info: info, includeCommit: true)
        return String(localized: "Версия \(text)")
    }

    /// Короткий хэш коммита; `nil`, если сборка не из `build-app.sh`.
    static func commit(info: [String: Any]) -> String? {
        value(info, commitKey)
    }

    private static func compose(info: [String: Any], includeCommit: Bool) -> String {
        guard let version = value(info, versionKey) else { return "dev" }
        var details: [String] = []
        if let build = value(info, buildKey) { details.append(String(localized: "сборка \(build)")) }
        if includeCommit, let commit = commit(info: info) { details.append(commit) }
        return details.isEmpty ? version : "\(version) (\(details.joined(separator: ", ")))"
    }

    private static func value(_ info: [String: Any], _ key: String) -> String? {
        guard let text = info[key] as? String, !text.isEmpty else { return nil }
        return text
    }
}
