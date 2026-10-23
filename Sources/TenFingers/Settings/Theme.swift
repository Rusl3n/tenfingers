import SwiftUI

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark, schedule
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: String(localized: "Как в системе")
        case .light: String(localized: "Светлая")
        case .dark: String(localized: "Тёмная")
        case .schedule: String(localized: "По расписанию")
        }
    }
}

struct Palette: Equatable {
    let background: Color
    let card: Color
    /// Насыщенность цветов пальцев на клавишах.
    let keyOpacity: Double
}

enum LightPalette: String, CaseIterable, Identifiable {
    case white, beige, gray
    var id: String { rawValue }
    var title: String {
        switch self {
        case .white: String(localized: "Белая")
        case .beige: String(localized: "Бежевая")
        case .gray: String(localized: "Серая")
        }
    }
    var palette: Palette {
        switch self {
        case .white: Palette(background: Color(red: 1, green: 1, blue: 1), card: Color(red: 0.96, green: 0.96, blue: 0.97), keyOpacity: 0.28)
        case .beige: Palette(background: Color(red: 0.965, green: 0.941, blue: 0.902), card: Color(red: 0.929, green: 0.894, blue: 0.839), keyOpacity: 0.42)
        case .gray: Palette(background: Color(red: 0.925, green: 0.925, blue: 0.933), card: Color(red: 0.882, green: 0.882, blue: 0.894), keyOpacity: 0.40)
        }
    }
}

enum DarkPalette: String, CaseIterable, Identifiable {
    case graphite, night, cocoa
    var id: String { rawValue }
    var title: String {
        switch self {
        case .graphite: String(localized: "Графит")
        case .night: String(localized: "Ночь")
        case .cocoa: String(localized: "Кофе")
        }
    }
    var palette: Palette {
        switch self {
        case .graphite: Palette(background: Color(red: 0.118, green: 0.118, blue: 0.125), card: Color(red: 0.165, green: 0.165, blue: 0.176), keyOpacity: 0.30)
        case .night: Palette(background: Color(red: 0.059, green: 0.106, blue: 0.176), card: Color(red: 0.090, green: 0.157, blue: 0.251), keyOpacity: 0.38)
        case .cocoa: Palette(background: Color(red: 0.137, green: 0.102, blue: 0.082), card: Color(red: 0.184, green: 0.141, blue: 0.114), keyOpacity: 0.36)
        }
    }
}

enum ThemeResolver {
    static func isDark(mode: ThemeMode, systemIsDark: Bool, hour: Int, darkFrom: Int, darkTo: Int) -> Bool {
        switch mode {
        case .system: return systemIsDark
        case .light: return false
        case .dark: return true
        case .schedule:
            if darkFrom == darkTo { return false }
            return darkFrom < darkTo ? (hour >= darkFrom && hour < darkTo) : (hour >= darkFrom || hour < darkTo)
        }
    }
}

extension ThemeResolver {
    /// Имя внешнего вида для окна: nil для «Как в системе» (системное значение).
    static func appearanceName(mode: ThemeMode, isDark: Bool) -> NSAppearance.Name? {
        mode == .system ? nil : (isDark ? .darkAqua : .aqua)
    }

    /// Внешний вид по сохранённым настройкам и часу: нужен до появления окна, чтобы первый кадр был верным.
    static func storedAppearanceName(defaults: UserDefaults, hour: Int) -> NSAppearance.Name? {
        let mode = defaults.string(forKey: SettingsKey.themeMode).flatMap(ThemeMode.init(rawValue:)) ?? .system
        let from = defaults.object(forKey: SettingsKey.darkFromHour) as? Int ?? SettingsDefault.darkFromHour
        let to = defaults.object(forKey: SettingsKey.darkToHour) as? Int ?? SettingsDefault.darkToHour
        // Для режима «Как в системе» имя не задаётся, поэтому системная схема здесь не нужна.
        let isDark = isDark(mode: mode, systemIsDark: false, hour: hour, darkFrom: from, darkTo: to)
        return appearanceName(mode: mode, isDark: isDark)
    }

    /// Применяет сохранённый внешний вид к приложению. Возвращает `false`, если `NSApp` ещё не создан.
    @MainActor @discardableResult
    static func applyStoredAppearance(defaults: UserDefaults = .standard, now: Date = .now) -> Bool {
        guard let app = NSApp else { return false }
        let hour = Calendar.current.component(.hour, from: now)
        app.appearance = storedAppearanceName(defaults: defaults, hour: hour).flatMap { NSAppearance(named: $0) }
        return true
    }
}

/// Реальная системная схема, не зависящая от внешнего вида окна приложения.
@MainActor @Observable
final class SystemAppearance {
    private(set) var isDark = SystemAppearance.read()
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    isolated deinit {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    init() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isDark = SystemAppearance.read() }
        }
    }

    private static func read() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = LightPalette.white.palette
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
