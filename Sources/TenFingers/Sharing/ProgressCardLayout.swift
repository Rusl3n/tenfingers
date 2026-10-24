import SwiftUI
import TypingCore

/// Данные и тексты карточки «Мой прогресс», взятые вместе: раскладка выбирается по ним, а не по двум независимым полям.
struct ProgressCardParts {
    let data: ProgressCardData
    let text: ProgressCardText
}

/// Размеры «Мой прогресс» в вертикальных форматах; подпись, дата, водяной знак и QR — из `ShareCardView.Metrics`.
private struct ProgressMetrics {
    let icon, header, headline, subtitle, period, metricValue, metricTitle, weekday: CGFloat
    let spacing: CGFloat

    static let square = ProgressMetrics(icon: 120, header: 28, headline: 64, subtitle: 30, period: 38, metricValue: 36,
                                        metricTitle: 22, weekday: 22, spacing: 22)
    static let story = ProgressMetrics(icon: 220, header: 38, headline: 100, subtitle: 40, period: 52, metricValue: 52,
                                       metricTitle: 30, weekday: 30, spacing: 36)
}

/// Широкая раскладка: поля карточки, левая колонка с огнём и показателями и промежуток до календаря.
private enum WideProgress {
    static let padding: CGFloat = 72
    static let column: CGFloat = 440
    static let gap: CGFloat = 48

    /// Ширина календаря: вся ширина карточки без полей, а если слева есть колонка — за вычетом неё и промежутка.
    static func calendarWidth(hasSummary: Bool) -> CGFloat {
        let inner = ShareFormat.wide.size.width - 2 * padding
        return hasSummary ? inner - column - gap : inner
    }
}

extension ShareCardView {
    /// Данные и тексты вместе; `nil`, если у карточки нет хотя бы одного из них (тогда рисуется обычная раскладка).
    var progressParts: ProgressCardParts? {
        guard let data = progress, let text = text.progress else { return nil }
        return ProgressCardParts(data: data, text: text)
    }

    // MARK: Широкая: слева огонь и показатели, справа календарь; без календаря — всё по центру

    func progressWide(_ parts: ProgressCardParts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if parts.text.showsCalendar {
                    wideWithCalendar(parts)
                } else {
                    wideSummaryOnly(parts.text)
                }
            }
            .frame(maxHeight: .infinity)
            wideFooter
        }
        .padding(.horizontal, WideProgress.padding)
        .padding(.vertical, 56)
    }

    /// Левая колонка собирается из включённых блоков; если она пуста, календарь занимает всю ширину.
    private func wideWithCalendar(_ parts: ProgressCardParts) -> some View {
        let text = parts.text
        return HStack(spacing: WideProgress.gap) {
            if text.hasSummary {
                VStack(alignment: .leading, spacing: 14) {
                    if text.showsStreak {
                        HStack(spacing: 20) {
                            eventIcon(size: 84)
                            header(size: 26)
                        }
                        headline(size: 54, alignment: .leading, width: WideProgress.column)
                    } else {
                        header(size: 26)
                    }
                    subtitle(size: 22, alignment: .leading, width: WideProgress.column)
                    if !text.metrics.isEmpty {
                        Spacer().frame(height: 10)
                        metricsList(text.metrics)
                    }
                }
                .frame(width: WideProgress.column, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 14) {
                if !text.hasSummary { header(size: 26) }
                periodLabel(size: 30)
                ProgressCalendarView(data: parts.data, period: text.period, text: text, style: style, labelSize: 18,
                                     width: WideProgress.calendarWidth(hasSummary: text.hasSummary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// «Без календаря»: огонь, полные дни и показатели по центру карточки.
    private func wideSummaryOnly(_ text: ProgressCardText) -> some View {
        let flameOnly = text.isFlameOnly
        let inner = ShareFormat.wide.size.width - 2 * WideProgress.padding
        let iconSize: CGFloat = flameOnly ? 200 : 130
        return VStack(spacing: 22) {
            if text.showsStreak {
                HStack(spacing: 36) {
                    eventIcon(size: iconSize)
                    VStack(alignment: .leading, spacing: 10) {
                        header(size: 28)
                        headline(size: flameOnly ? 92 : 68, alignment: .leading, width: inner - iconSize - 36)
                    }
                }
            } else {
                header(size: 28)
            }
            subtitle(size: 30, alignment: .center, width: inner)
            if !text.metrics.isEmpty {
                VStack(spacing: 14) {
                    captionLabel(size: 24)
                    metricsRow(text.metrics, valueSize: 44, titleSize: 22)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Квадрат и «сторис»: сверху вниз

    func progressVertical(_ parts: ProgressCardParts, _ format: ShareFormat) -> some View {
        let metrics = format == .story ? Metrics.story : Metrics.square
        let progress = format == .story ? ProgressMetrics.story : ProgressMetrics.square
        return VStack(spacing: 0) {
            if parts.text.showsCalendar {
                verticalWithCalendar(parts, metrics: metrics, progress: progress, format: format)
            } else {
                verticalSummaryOnly(parts.text, metrics: metrics, progress: progress)
            }
            Spacer(minLength: progress.spacing)
            VStack(spacing: 8) { signatureAndDate(signature: metrics.signature, date: metrics.date) }
            Spacer().frame(height: metrics.padding * 0.4)
            HStack(spacing: 28) {
                if options.showsQR { qrCode(side: metrics.qr) }
                watermark(iconSize: metrics.watermarkIcon, fontSize: metrics.watermarkFont)
            }
        }
        .padding(metrics.padding)
    }

    /// Сверху огонь и полные дни (если включены), под ними календарь на всё свободное место, ниже показатели.
    @ViewBuilder
    private func verticalWithCalendar(_ parts: ProgressCardParts, metrics: Metrics, progress: ProgressMetrics,
                                      format: ShareFormat) -> some View {
        let text = parts.text
        let contentWidth = options.format.size.width - 2 * metrics.padding
        Group {
            if text.showsStreak {
                HStack(spacing: progress.spacing) {
                    eventIcon(size: progress.icon)
                    VStack(alignment: .leading, spacing: 6) {
                        header(size: progress.header)
                        headline(size: progress.headline, alignment: .leading,
                                 width: contentWidth - progress.icon - progress.spacing)
                    }
                }
            } else {
                header(size: progress.header)
            }
        }
        if text.showsFullDays {
            Spacer().frame(height: progress.spacing * 0.6)
            subtitle(size: progress.subtitle, alignment: .center, width: contentWidth)
        }
        Spacer(minLength: progress.spacing)
        VStack(spacing: progress.spacing * 0.5) {
            periodLabel(size: progress.period)
            ProgressCalendarView(data: parts.data, period: text.period, text: text, style: style,
                                 labelSize: progress.weekday, width: options.format.size.width - 2 * metrics.padding)
        }
        .frame(maxHeight: .infinity)
        if !text.metrics.isEmpty {
            Spacer().frame(height: progress.spacing)
            metricsRow(text.metrics, valueSize: progress.metricValue, titleSize: progress.metricTitle)
        }
    }

    /// «Без календаря»: включённые блоки собираются в центре карточки; один только огонь — крупно.
    @ViewBuilder
    private func verticalSummaryOnly(_ text: ProgressCardText, metrics: Metrics, progress: ProgressMetrics)
        -> some View {
        let flameOnly = text.isFlameOnly
        let contentWidth = options.format.size.width - 2 * metrics.padding
        Spacer(minLength: 0)
        VStack(spacing: progress.spacing) {
            if text.showsStreak {
                eventIcon(size: flameOnly ? metrics.icon : progress.icon * 1.5)
                VStack(spacing: 18) {
                    header(size: metrics.header)
                    headline(size: flameOnly ? metrics.headline * 1.2 : progress.headline, alignment: .center,
                             width: contentWidth)
                    subtitle(size: progress.subtitle, alignment: .center, width: contentWidth)
                }
            } else {
                header(size: metrics.header)
                subtitle(size: progress.subtitle, alignment: .center, width: contentWidth)
            }
            if !text.metrics.isEmpty {
                VStack(spacing: progress.spacing * 0.6) {
                    captionLabel(size: progress.metricTitle)
                    metricsRow(text.metrics, valueSize: progress.metricValue, titleSize: progress.metricTitle)
                }
            }
        }
        Spacer(minLength: 0)
    }

    // MARK: Части

    @ViewBuilder private func periodLabel(size: CGFloat) -> some View {
        if let label = text.progress?.periodLabel {
            Text(verbatim: label)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(style.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// «За всё время» над показателями, когда календаря (и его подписи) нет.
    @ViewBuilder private func captionLabel(size: CGFloat) -> some View {
        if let label = text.progress?.periodLabel {
            Text(verbatim: label)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(style.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    /// Показатели столбцом: название слева, значение справа.
    private func metricsList(_ metrics: [ProgressCardText.Metric]) -> some View {
        VStack(spacing: 12) {
            ForEach(metrics, id: \.title) { metric in
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: metric.title)
                        .font(.system(size: 22, weight: .medium, design: .rounded))
                        .foregroundStyle(style.secondary)
                    Spacer(minLength: 12)
                    Text(verbatim: metric.value)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(style.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }

    /// Показатели в ряд: значение крупно, под ним название.
    private func metricsRow(_ metrics: [ProgressCardText.Metric], valueSize: CGFloat, titleSize: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(metrics, id: \.title) { metric in
                VStack(spacing: 4) {
                    Text(verbatim: metric.value)
                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                        .foregroundStyle(style.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(verbatim: metric.title)
                        .font(.system(size: titleSize, weight: .medium, design: .rounded))
                        .foregroundStyle(style.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Календарь карточки: для месяца — недели с подписями дней недели и числами, для года — 53×7 точек с подписями
/// месяцев; у «Без календаря» ничего не рисует. Размер клетки подбирается под доступное место. Цвета — как в
/// «Аналитике» (`DayStatusStyle`), пропуск — бледно-серый (на прозрачном фоне темнее и с обводкой), будущие дни — пустые.
struct ProgressCalendarView: View {
    let data: ProgressCardData
    let period: ProgressPeriod
    let text: ProgressCardText?
    let style: ShareCardStyle
    /// Размер шрифта подписей (дни недели, месяцы).
    let labelSize: CGFloat
    /// Ширина, отведённая календарю.
    let width: CGFloat

    var body: some View {
        switch period {
        case .month:
            GeometryReader { proxy in
                month(in: proxy.size)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        case .year:
            year(width: width)
                .frame(maxWidth: .infinity)
        case .all:
            EmptyView()
        }
    }

    /// Пропущенный день на прозрачном фоне: фон неизвестен, поэтому заливка плотнее и есть обводка.
    private var missedFill: Color { Color.secondary.opacity(style.isTransparent ? 0.4 : 0.15) }

    private func color(_ status: DayStatus) -> Color {
        status == .none ? missedFill : DayStatusStyle.color(status)
    }

    /// Цвет числа на круге: белый на плотном оранжевом; на светлых кружках (половинный, заморозка) в светлой теме — тёмный.
    private func numberColor(_ day: MonthGrid.Cell) -> Color {
        if day.isFuture { return style.secondary.opacity(0.55) }
        switch day.status {
        case .full: return .white
        case .half: return style.isDark ? .white : Color(white: 0.11)
        case .frozen: return Color(white: 0.11)
        case .none: return style.secondary
        }
    }

    // MARK: Месяц

    private func month(in size: CGSize) -> some View {
        let weeks = data.monthGrid.weeks
        let gap = max(4, size.width / 90)
        let headerHeight = labelSize * 1.5
        let rows = CGFloat(max(weeks.count, 1))
        let byWidth = (size.width - gap * 6) / 7
        let byHeight = (size.height - headerHeight - gap * rows) / rows
        let cell = max(8, min(byWidth, byHeight, 120))
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                ForEach(Array((text?.weekdays ?? []).enumerated()), id: \.offset) { _, name in
                    Text(verbatim: name)
                        .font(.system(size: labelSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(style.secondary)
                        .frame(width: cell)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .frame(height: headerHeight)
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: gap) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        monthCell(day, size: cell)
                    }
                }
            }
        }
    }

    @ViewBuilder private func monthCell(_ day: MonthGrid.Cell?, size: CGFloat) -> some View {
        if let day {
            let missed = !day.isFuture && day.status == .none
            ZStack {
                Circle().fill(day.isFuture ? Color.clear : color(day.status))
                if missed && style.isTransparent {
                    Circle().strokeBorder(style.secondary.opacity(0.7), lineWidth: max(2, size * 0.04))
                }
                Text(verbatim: String(day.day))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(numberColor(day))
            }
            .frame(width: size, height: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }

    // MARK: Год

    private func year(width: CGFloat) -> some View {
        let weeks = data.yearGrid.weeks
        let columns = CGFloat(max(weeks.count, 1))
        let pitch = width / columns
        let gap = pitch * 0.2
        let cell = pitch - gap
        let font = min(labelSize, pitch * 1.15)
        return VStack(alignment: .leading, spacing: gap * 2) {
            yearMonthLabels(pitch: pitch, font: font)
                .frame(height: font * 1.3, alignment: .topLeading)
            HStack(alignment: .top, spacing: gap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: gap) {
                        ForEach(week) { day in
                            Circle()
                                .fill(day.isFuture ? Color.clear : color(day.status))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
        .frame(width: width - gap, alignment: .leading)
    }

    /// Подпись месяца занимает колонки до следующей подписи.
    private func yearMonthLabels(pitch: CGFloat, font: CGFloat) -> some View {
        let labels = data.yearGrid.monthLabels
        let symbols = text?.monthSymbols ?? []
        return HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(labels.first?.column ?? 0) * pitch, height: 1)
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                let end = index + 1 < labels.count ? labels[index + 1].column : data.yearGrid.weeks.count
                Text(verbatim: symbols.indices.contains(label.month - 1) ? symbols[label.month - 1] : "")
                    .font(.system(size: font, weight: .medium, design: .rounded))
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: CGFloat(end - label.column) * pitch, alignment: .leading)
            }
        }
    }
}
