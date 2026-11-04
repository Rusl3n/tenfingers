import AppIntents
import AppKit
import WidgetKit
import WidgetSnapshot

/// Настройки виджета. Только простые типы (`Bool`, `Int`): выбор из списка (`AppEnum`) разбирает системная служба,
/// а она отказывает процессу с ad-hoc подписью, и действовало бы значение по умолчанию.
struct TenFingersConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Десять пальцев"
    static let description = IntentDescription("Серия, цель дня и ачивки на рабочем столе.")

    @Parameter(title: "Серия", default: true)
    var showStreak: Bool

    @Parameter(title: "Цель дня", default: true)
    var showGoal: Bool

    @Parameter(title: "Ачивки", default: true)
    var showAchievements: Bool

    @Parameter(title: "Менять каждые, мин", default: 15, inclusiveRange: (5, 60))
    var intervalMinutes: Int

    @Parameter(title: "Менять по нажатию", default: false)
    var tapToSwitch: Bool

    @Parameter(title: "Приглашение на урок", default: true)
    var showInvite: Bool

    @Parameter(title: "Скрывать шуточные 18+", default: false)
    var hideAdult: Bool

    init() {}

    var selection: WidgetPageSelection {
        WidgetPageSelection(streak: showStreak, goal: showGoal, achievements: showAchievements)
    }
}

/// Счётчик нажатий «Менять по нажатию». Лежит в `UserDefaults` процесса виджета (его песочница, не папка приложения)
/// и общий для всех экземпляров виджета.
enum PageCounter {
    private static let key = "widget.pageOffset"

    static var value: Int {
        UserDefaults.standard.integer(forKey: key)
    }

    static func set(_ offset: Int) {
        UserDefaults.standard.set(offset, forKey: key)
    }
}

/// Кнопка на самом виджете: следующая страница и раздел приложения. Параметры — строка и число (их разбирает сам виджет).
struct NextPageIntent: AppIntent {
    static let title: LocalizedStringResource = "Следующая страница"
    static let description = IntentDescription("Переключает виджет на следующую страницу.")
    static let isDiscoverable = false
    static let openAppWhenRun = false

    /// Раздел приложения для показанной страницы (`tenfingers://…`). Строка, а не перечисление:
    /// перечисления в параметрах с ad-hoc подписью не разбираются.
    @Parameter(title: "Ссылка")
    var link: String

    /// Смещение ленты после нажатия: страница, следующая за показанной (`WidgetTimeline.nextOffset`).
    @Parameter(title: "Страница")
    var nextOffset: Int

    init() {
        link = WidgetLink.home.absoluteString
        nextOffset = 0
    }

    init(link: URL, nextOffset: Int) {
        self.link = link.absoluteString
        self.nextOffset = nextOffset
    }

    /// Листает виджет и открывает приложение в разделе страницы, которую нажали. Ссылку открывает сам виджет:
    /// `OpensIntent` выполняет системная служба, а она с ad-hoc подписью отказывает (проверено на установке).
    func perform() async throws -> some IntentResult {
        PageCounter.set(nextOffset)
        WidgetCenter.shared.reloadTimelines(ofKind: TenFingersWidgetKind.home)
        // Только свои ссылки: параметр приходит извне процесса
        let url = URL(string: link).flatMap { $0.scheme == WidgetLink.scheme ? $0 : nil } ?? WidgetLink.home
        _ = try? await NSWorkspace.shared.open(url, configuration: .init())
        return .result()
    }
}
