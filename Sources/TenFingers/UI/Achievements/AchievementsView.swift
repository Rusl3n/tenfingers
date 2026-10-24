import os
import SwiftData
import SwiftUI
import TypingCore

private let seenLog = Logger(subsystem: "local.tenfingers", category: "achievements")

/// Экран «Ачивки»: прогресс «Получено N из M», фильтр по категориям и сетка значков. При появлении все
/// видимые ачивки помечаются просмотренными (одной транзакцией), но точки «новое» остаются, пока экран открыт.
struct AchievementsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AchievementRecord.unlockedAt, order: .reverse) private var records: [AchievementRecord]
    @AppStorage(SettingsKey.adultHumor) private var adultHumor = SettingsDefault.adultHumor
    @State private var category: AchievementCategory?
    @State private var selected: AchievementEntry?
    /// Ачивки, которые были новыми к моменту открытия экрана: на них точка, хотя в базе они уже просмотрены.
    @State private var fresh: Set<String> = []

    private var stored: [StoredAchievement] { records.map(StoredAchievement.init) }

    private var entries: [AchievementEntry] {
        AchievementsListing.entries(catalog: AchievementCatalog.all, earned: stored, adultHumor: adultHumor)
    }

    private var unseen: Set<String> {
        AchievementsListing.unseenIds(catalog: AchievementCatalog.all, earned: stored, adultHumor: adultHumor)
    }

    var body: some View {
        ScrollView {
            AchievementsContent(entries: entries, category: $category, freshIds: fresh,
                                select: { selected = $0 })
        }
        .scrollContentBackground(.hidden)
        .onAppear(perform: markSeen)
        // Новая ачивка, выданная при открытом экране (например, проверка при запуске).
        .onChange(of: unseen) { markSeen() }
        // Выбранная категория пропала (выключили «Взрослый юмор»): назад к «Все».
        .onChange(of: AchievementsListing.categories(of: entries)) {
            category = AchievementsListing.resolvedCategory(category, in: entries)
        }
        .sheet(item: $selected) { entry in
            AchievementDetailView(entry: entry, close: { selected = nil })
        }
    }

    /// Все видимые непросмотренные — в просмотренные одной транзакцией; точки на них остаются до ухода с экрана.
    private func markSeen() {
        let ids = unseen
        guard !ids.isEmpty else { return }
        fresh.formUnion(ids)
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
    let freshIds: Set<String>
    let select: (AchievementEntry) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        let progress = AchievementsListing.progress(entries)
        VStack(alignment: .leading, spacing: 16) {
            Text("Ачивки").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 8) {
                Text("Получено \(progress.earned) из \(progress.total)").font(.headline)
                ProgressBar(fraction: progress.total == 0 ? 0 : Double(progress.earned) / Double(progress.total))
                if progress.earned == 0 {
                    Text("Пока ни одной: они появятся после занятий").foregroundStyle(.secondary)
                }
            }
            CategoryFilter(categories: AchievementsListing.categories(of: entries), selection: $category)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(AchievementsListing.filtered(entries, category: category)) { entry in
                    Button { select(entry) } label: {
                        AchievementBadge(entry: entry, showsDot: freshIds.contains(entry.id) || !entry.seen)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 900, alignment: .leading)
        .frame(maxWidth: .infinity)
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
    @Binding var selection: AchievementCategory?

    var body: some View {
        ChipFlow(spacing: 8) {
            chip(String(localized: "Все"), tint: .accentColor, isOn: selection == nil) { selection = nil }
            ForEach(categories, id: \.self) { category in
                chip(AchievementStyle.title(category), tint: AchievementStyle.tint(category),
                     isOn: selection == category) { selection = category }
            }
        }
    }

    private func chip(_ title: String, tint: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(isOn ? tint : tint.opacity(0.14), in: Capsule())
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
