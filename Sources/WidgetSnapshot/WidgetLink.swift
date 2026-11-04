import Foundation

/// Ссылки `tenfingers://…`: виджет открывает ими разделы приложения, приложение их разбирает (`AppLink`).
/// Общие константы, чтобы схема и имена разделов не расходились.
public enum WidgetLink {
    public static let scheme = "tenfingers"
    public static let homeHost = "home"
    public static let courseHost = "course"
    public static let achievementsHost = "achievements"

    public static func url(host: String) -> URL {
        URL(string: "\(scheme)://\(host)")!
    }

    public static var home: URL { url(host: homeHost) }
    public static var course: URL { url(host: courseHost) }
    public static var achievements: URL { url(host: achievementsHost) }
}
