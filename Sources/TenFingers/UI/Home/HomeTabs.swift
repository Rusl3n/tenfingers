import SwiftUI

/// Вкладка «страницы в странице»: значок и подпись сегмента переключателя.
protocol PageTab: Hashable, Identifiable {
    var icon: String { get }
    var title: String { get }
}

/// Вкладки нижней части «Главной» в порядке слева направо.
enum HomeTab: String, CaseIterable, Identifiable, PageTab {
    case plan, challenges, course, quick

    var id: String { rawValue }

    /// Значок кнопки вкладки (те же символы были у прежних блоков «Главной»).
    var icon: String {
        switch self {
        case .plan: "checklist"
        case .challenges: "flag.checkered"
        case .course: "graduationcap"
        case .quick: "target"
        }
    }

    var title: String {
        switch self {
        case .plan: String(localized: "План на сегодня")
        case .challenges: String(localized: "Испытания")
        case .course: String(localized: "Продолжить курс")
        case .quick: String(localized: "Тренировка и практика")
        }
    }
}

/// Какие вкладки есть и какая выбрана. Выбор хранится одним ключом `SettingsKey.homeTab` (состояние окна,
/// в архив прогресса не входит).
enum HomeTabs {
    /// Вкладка есть, только когда есть её содержимое; «Тренировка и практика» — всегда.
    static func available(hasPlan: Bool, hasChallenges: Bool, hasCourse: Bool) -> [HomeTab] {
        HomeTab.allCases.filter {
            switch $0 {
            case .plan: hasPlan
            case .challenges: hasChallenges
            case .course: hasCourse
            case .quick: true
            }
        }
    }

    /// Сохранённая вкладка, если она доступна; иначе первая доступная (то есть «План на сегодня», пока он есть).
    static func resolved(stored: String?, available: [HomeTab]) -> HomeTab {
        if let stored, let tab = HomeTab(rawValue: stored), available.contains(tab) { return tab }
        return available.first ?? .quick
    }

    static func selected(available: [HomeTab], _ defaults: UserDefaults = ProfileDefaults.current) -> HomeTab {
        resolved(stored: defaults.string(forKey: SettingsKey.homeTab), available: available)
    }

    static func store(_ tab: HomeTab, _ defaults: UserDefaults = ProfileDefaults.current) {
        defaults.set(tab.rawValue, forKey: SettingsKey.homeTab)
    }
}

/// Раскладка в ряд: все сегменты одной ширины (ширина колонки за вычетом промежутков, поровну).
/// Без неё сегменты со значками получают разную ширину по длине подписи.
private struct EqualWidthRow: Layout {
    var spacing: CGFloat

    private func cellWidth(_ total: CGFloat, count: Int) -> CGFloat {
        (total - spacing * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let cell = cellWidth(width, count: subviews.count)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = cellWidth(bounds.width, count: subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index) * (cell + spacing)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: cell, height: bounds.height))
        }
    }
}

/// Переключатель вкладок на всю ширину колонки: сегменты одной ширины, выбранный залит акцентным цветом.
/// Сделан на чистом SwiftUI: системный сегментный `Picker` не растягивается и не рисуется в `ImageRenderer`.
struct HomeTabBar<Tab: PageTab>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    /// Вкладки с красным кружком «есть новое» (`HomeTabNews.dots`).
    var dots: Set<Tab> = []
    @Environment(\.palette) private var palette

    var body: some View {
        EqualWidthRow(spacing: 2) {
            ForEach(tabs) { tab in
                let isSelected = tab == selection
                let hasDot = dots.contains(tab)
                Button { selection = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                            .accessibilityHidden(true)
                        Text(verbatim: tab.title)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            // Кружок у подписи, а не в углу широкой ячейки: иначе он читается как метка соседней вкладки.
                            .overlay(alignment: .topTrailing) {
                                if hasDot { NewDot().offset(x: 9, y: -3) }
                            }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityValue(hasDot ? Text("есть новое") : Text(verbatim: ""))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
    }
}

/// Страница внутри страницы: переключатель вкладок и под ним содержимое выбранной в карточке на всю ширину.
struct HomeTabsSection<Tab: PageTab, Content: View>: View {
    let tabs: [Tab]
    @Binding var selection: Tab
    var dots: Set<Tab> = []
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HomeTabBar(tabs: tabs, selection: $selection, dots: dots)
            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}
