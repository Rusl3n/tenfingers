import SwiftUI
import TypingCore

/// Плашка «Серия на волоске» (§10.4, решение 17): сколько минут набрать сегодня, чтобы спасти пропущенный день.
struct RepairBannerModel: Equatable {
    let text: String
    /// «Сегодня 8 из 20 мин» — подпись к полоске двойной цели.
    let caption: String
    /// Доля двойной цели, набранная сегодня, 0…1.
    let fraction: Double

    /// `nil`, если серия не «на волоске».
    static func make(streak: StreakSummary, todaySeconds: Double, bundle: Bundle = .main,
                     locale: Locale = Formatting.interfaceLocale()) -> RepairBannerModel? {
        guard streak.repairPending else { return nil }
        let minutes = max(1, Int((streak.repairNeedSeconds / 60).rounded(.up)))
        let days = Formatting.days(streak.repairStreak, bundle: bundle, locale: locale)
        let done = Int(max(todaySeconds, 0) / 60)
        let target = Int((streak.repairTargetSeconds / 60).rounded())
        let fraction = streak.repairTargetSeconds > 0 ? min(max(todaySeconds / streak.repairTargetSeconds, 0), 1) : 0
        return RepairBannerModel(
            text: String(localized: "Серия на волоске: наберите сегодня \(minutes) мин (двойная цель), чтобы спасти \(days)",
                         bundle: bundle, locale: locale),
            caption: String(localized: "Сегодня \(done) из \(target) мин", bundle: bundle, locale: locale),
            fraction: fraction)
    }
}

struct RepairBanner: View {
    let model: RepairBannerModel

    var body: some View {
        let green = DayStatusStyle.color(.repaired)
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: DayStatusStyle.icon(.repaired))
                .font(.system(size: 28))
                .foregroundStyle(green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(verbatim: model.text).font(.headline).fixedSize(horizontal: false, vertical: true)
                    InfoButton(text: HelpText.repair)
                }
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 8)
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(green).frame(width: proxy.size.width * model.fraction)
                        }
                    }
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: model.caption))
                    .accessibilityValue(Text(Formatting.percent(model.fraction)))
                Text(verbatim: model.caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(green.opacity(0.4)))
    }
}
