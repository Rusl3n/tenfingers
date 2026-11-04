import Foundation

/// Почему обновление не предлагается, хотя описание выпуска получено.
public enum UpdateUnsupported: Equatable, Sendable {
    /// Неизвестный `format` или нечитаемая версия в описании.
    case format
    /// Система старее `minimumSystemVersion`.
    case system
    /// Пользователь пропустил именно эту версию.
    case skipped
}

public enum UpdateDecision: Equatable, Sendable {
    case upToDate
    case available(ReleaseManifest)
    case unsupported(reason: UpdateUnsupported)
    /// Установлена сборка `-dev`: своя сборка не «обновляется» на релиз.
    case developmentBuild
}

/// Что предлагать и когда проверять (7b, §5.1). Чистые функции, без сети и `UserDefaults`.
public enum UpdatePolicy {
    /// Период таймера автоматической проверки, пока приложение открыто.
    public static let autoCheckInterval: TimeInterval = 24 * 3600
    /// Автоматическая проверка не чаще этого промежутка: частые перезапуски сеть не дёргают.
    public static let autoCheckMinimumGap: TimeInterval = 20 * 3600

    /// Порядок: формат → сборка `-dev` → система → пропущенная версия → сравнение версий (при равных — по `build`).
    /// `allowDevelopment` — сборка `-dev` с заданным `updateFeedURL`: версии сравниваются и для неё.
    public static func decide(
        manifest: ReleaseManifest,
        installedVersion: String,
        installedBuild: Int,
        systemVersion: OperatingSystemVersion,
        skippedVersion: String?,
        allowDevelopment: Bool = false
    ) -> UpdateDecision {
        guard manifest.format == ReleaseManifest.supportedFormat,
              let offered = SemanticVersion(manifest.version) else {
            return .unsupported(reason: .format)
        }
        let installed = SemanticVersion(installedVersion)
        if let installed, isDevelopment(installed), !allowDevelopment {
            return .developmentBuild
        }
        guard let required = parseSystem(manifest.minimumSystemVersion) else {
            return .unsupported(reason: .format)
        }
        if isOlder(systemVersion, than: required) {
            return .unsupported(reason: .system)
        }
        if let skippedVersion, skippedVersion == manifest.version {
            return .unsupported(reason: .skipped)
        }
        // Нечитаемая установленная версия: ничего не предлагаем, чтобы не затереть неизвестную сборку.
        guard let installed else { return .upToDate }
        if offered > installed || (offered == installed && manifest.build > installedBuild) {
            return .available(manifest)
        }
        return .upToDate
    }

    /// Автоматическая проверка нужна, если успешной не было вовсе или прошло не меньше 20 часов.
    /// Время последней проверки «в будущем» (сбитые часы) не блокирует проверки.
    public static func shouldAutoCheck(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= autoCheckMinimumGap
    }

    /// Сборка «для разработки»: нет версии вовсе (`swift run`) или суффикс `-dev`/`-dev.N`.
    /// Нечитаемая версия сборкой для разработки не считается.
    public static func isDevelopmentBuild(version: String?) -> Bool {
        guard let version else { return true }
        guard let parsed = SemanticVersion(version) else { return false }
        return isDevelopment(parsed)
    }

    private static func isDevelopment(_ version: SemanticVersion) -> Bool {
        guard let suffix = version.prerelease else { return false }
        return suffix == "dev" || suffix.hasPrefix("dev.")
    }

    /// «15», «15.0», «15.1.2»; всё остальное — `nil`.
    private static func parseSystem(_ text: String) -> OperatingSystemVersion? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        while numbers.count < 3 { numbers.append(0) }
        return OperatingSystemVersion(majorVersion: numbers[0], minorVersion: numbers[1], patchVersion: numbers[2])
    }

    private static func isOlder(_ lhs: OperatingSystemVersion, than rhs: OperatingSystemVersion) -> Bool {
        (lhs.majorVersion, lhs.minorVersion, lhs.patchVersion) < (rhs.majorVersion, rhs.minorVersion, rhs.patchVersion)
    }
}
