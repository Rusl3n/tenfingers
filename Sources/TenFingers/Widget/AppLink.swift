import Foundation
import WidgetSnapshot

/// Ссылки `tenfingers://home`, `tenfingers://course`, `tenfingers://achievements`: так виджет открывает нужный раздел.
enum AppLink {
    static let scheme = WidgetLink.scheme

    /// Раздел по ссылке; неизвестный путь и чужая схема ведут на «Главную».
    static func item(for url: URL) -> SidebarItem {
        guard url.scheme?.lowercased() == scheme else { return .home }
        switch url.host(percentEncoded: false)?.lowercased() {
        case WidgetLink.courseHost: return .course
        case WidgetLink.achievementsHost: return .achievements
        default: return .home
        }
    }

    /// Ссылка на раздел; разделы без ссылки ведут на `home`.
    static func url(_ item: SidebarItem) -> URL {
        switch item {
        case .course: WidgetLink.course
        case .achievements: WidgetLink.achievements
        default: WidgetLink.home
        }
    }
}

extension AppLink {
    /// Раздел, на который надо перейти: пока идёт упражнение (виден он или скрыт), `nil` — ссылка только
    /// выводит окно вперёд и запуск не прерывает.
    static func target(for url: URL, hasRun: Bool) -> SidebarItem? {
        hasRun ? nil : item(for: url)
    }
}
