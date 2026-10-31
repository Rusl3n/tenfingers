import os
import SwiftData
import SwiftUI
import TypingCore

private let seenLog = Logger(subsystem: "local.tenfingers", category: "achievements")

/// Экран «Ачивки»: прогресс «Получено N из M», фильтры (по состоянию и по категориям) и сетка значков. При появлении все
/// ачивки с непросмотренной записью или выдачей запоминаются (снимок): на время визита по ним работают «Новые» и красные
/// кружки; просмотренными в базе они становятся при уходе с экрана (одной транзакцией).
struct AchievementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AchievementRecord.unlockedAt, order: .reverse) private var records: [AchievementRecord]
    @Query private var grantRecords: [AchievementGrant]
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @AppStorage(SettingsKey.achievementsFilter) private var filterRaw = AchievementsFilter.all.rawValue
    @State private var category: AchievementCategory?
    @State private var selected: AchievementEntry?
    /// Снимок новых: ачивки с непросмотренной записью или выдачей на момент открытия экрана и пришедшие, пока он
    /// открыт. Просмотренными в базе они становятся при уходе.
    @State private var fresh: Set<String> = []

    private var filter: Binding<AchievementsFilter> {
        Binding(get: { AchievementsFilter(rawValue: filterRaw) ?? .all }, set: { filterRaw = $0.rawValue })
    }

    private var stored: [StoredAchievement] { records.map(StoredAchievement.init) }

    private var entries: [AchievementEntry] {
        AchievementsListing.entries(catalog: AchievementCatalog.all, earned: stored,
                                    grants: grantRecords.map(StoredGrant.init), adultHumor: adultHumor)
    }

    private var unseen: Set<String> {
        AchievementsListing.unseenIds(
            catalog: AchievementCatalog.all, earned: stored,
            unseenGrantIds: Set(grantRecords.filter { !$0.seen }.map(\.achievementId)), adultHumor: adultHumor)
    }

    var body: some View {
        ScrollView {
            AchievementsContent(entries: entries, category: $category, filter: filter, freshIds: fresh,
                                select: { selected = $0 })
        }
        .scrollContentBackground(.hidden)
        .onAppear {
            fresh = unseen
            // Пустой снимок (новый визит): выбранные «Новые» сбрасываются на «Все» и в хранимом выборе.
            let resolved = AchievementsListing.resolvedFilter(filter.wrappedValue, hasNew: !fresh.isEmpty)
            if resolved != filter.wrappedValue { filter.wrappedValue = resolved }
        }
        // Новая ачивка или выдача при открытом экране (например, проверка после упражнения) попадает в снимок.
        .onChange(of: unseen) { fresh.formUnion(unseen) }
        .onDisappear(perform: markSeen)
        // Выбранная категория пропала (выключили «Взрослый юмор»): назад к «Все».
        .onChange(of: AchievementsListing.categories(of: entries)) {
            category = AchievementsListing.resolvedCategory(category, in: entries)
        }
        .sheet(item: $selected) { entry in
            AchievementDetailView(entry: entry, close: { selected = nil })
        }
    }

    /// Снимок и всё, что пришло после, — в просмотренные одной транзакцией (при уходе с экрана).
    private func markSeen() {
        let ids = fresh.union(unseen)
        guard !ids.isEmpty else { return }
        do {
            try AchievementsListing.markSeen(ids, in: .live(context: modelContext))
        } catch {
            seenLog.error("Marking achievements seen failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Раскладка экрана без прокрутки и без базы (её же рисует проверка через `ImageRenderer`).
struct AchievementsContent: View {
    let entries: [AchievementEntry]
    @Binding var category: AchievementCategory?
    @Binding var filter: AchievementsFilter
    let freshIds: Set<String>
    let select: (AchievementEntry) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let progress = AchievementsListing.progress(entries)
        let fresh = freshIds.intersection(entries.map(\.id))
        let hasNew = !fresh.isEmpty
        let currentFilter = AchievementsListing.resolvedFilter(filter, hasNew: hasNew)
        let shown = AchievementsListing.filtered(entries, category: category, filter: currentFilter, fresh: fresh)
        let picked = Binding(get: { currentFilter }, set: { filter = $0 })
        VStack(alignment: .leading, spacing: 16) {
            Text("Ачивки").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 8) {
                Text("Получено \(progress.earned) из \(progress.total)").font(.headline)
                ProgressBar(fraction: progress.total == 0 ? 0 : Double(progress.earned) / Double(progress.total))
                if progress.earned == 0 {
                    Text("Пока ни одной: они появятся после занятий").foregroundStyle(.secondary)
                }
            }
            Picker("Показывать", selection: picked) {
                ForEach(AchievementsListing.availableFilters(hasNew: hasNew)) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .overlay(alignment: .topTrailing) {
                if hasNew { NewDot().offset(x: 4, y: -4) }
            }
            CategoryFilter(categories: AchievementsListing.categories(of: entries),
                           newCategories: AchievementsListing.categoriesWithNew(of: entries, fresh: fresh),
                           selection: $category)
            if shown.isEmpty {
                EmptyAchievements { filter = .all; category = nil }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top)], spacing: 12) {
                    ForEach(shown) { entry in
                        Button { select(entry) } label: {
                            AchievementBadge(entry: entry, showsDot: freshIds.contains(entry.id) || !entry.seen)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

/// Красный кружок «есть новое» на кнопках фильтров.
private struct NewDot: View {
    var body: some View {
        Circle().fill(.red).frame(width: 9, height: 9).accessibilityHidden(true)
    }
}

/// Пустое сочетание фильтров: подсказка и кнопка сброса.
private struct EmptyAchievements: View {
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 32)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Здесь пока пусто").font(.headline)
            Button("Показать все", action: reset)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Полоса прогресса (нарисована сама: `ProgressView` — элемент AppKit, `ImageRenderer` его не рисует).
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule().fill(.quaternary)
            .frame(height: 8)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Color.accentColor).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .accessibilityHidden(true)
    }
}

/// Фильтр: «Все» и категории, в несколько строк по ширине экрана.
private struct CategoryFilter: View {
    let categories: [AchievementCategory]
    let newCategories: Set<AchievementCategory>
    @Binding var selection: AchievementCategory?

    var body: some View {
        ChipFlow(spacing: 8) {
            chip(String(localized: "Все"), tint: .accentColor, isOn: selection == nil) { selection = nil }
            ForEach(categories, id: \.self) { category in
                chip(AchievementStyle.title(category), tint: AchievementStyle.tint(category),
                     isOn: selection == category, hasNew: newCategories.contains(category)) { selection = category }
            }
        }
    }

    private func chip(_ title: String, tint: Color, isOn: Bool, hasNew: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(isOn ? tint : tint.opacity(0.14), in: Capsule())
                .overlay(alignment: .topTrailing) {
                    if hasNew { NewDot().offset(x: 2, y: -2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Элементы слева направо с переносом на следующую строку.
private struct ChipFlow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (subview, frame) in zip(subviews, frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, usedWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (frames, CGSize(width: usedWidth, height: y + rowHeight))
    }
}
