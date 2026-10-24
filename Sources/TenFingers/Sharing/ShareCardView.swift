import AppKit
import SwiftUI
import TypingCore

/// Цвета карточки: фон, текст и иконка события по теме, фону и событию.
struct ShareCardStyle {
    enum Fill {
        /// Градиент «огня» (серия).
        case fire
        /// Палитра приложения с отсветом цвета события.
        case palette(Palette)
        /// Прозрачный PNG.
        case none
    }

    let fill: Fill
    let isDark: Bool
    let primary: Color
    let secondary: Color
    /// Цвет заголовка и иконки события.
    let accent: Color
    let iconBackdrop: Color
    /// Тень текста на прозрачном фоне (для читаемости на любой подложке).
    let shadow: Color?

    /// Прозрачный PNG: фон неизвестен, поэтому бледные элементы приходится усиливать.
    var isTransparent: Bool {
        if case .none = fill { true } else { false }
    }

    static func make(event: ShareEvent, options: ShareOptions, light: Palette, dark: Palette) -> ShareCardStyle {
        let isDark = options.theme == .dark
        let tint = tint(event)
        let textPrimary = isDark ? Color.white : Color(white: 0.11)
        let textSecondary = isDark ? Color.white.opacity(0.7) : Color(white: 0.38)
        if options.background == .transparent {
            return ShareCardStyle(fill: .none, isDark: isDark, primary: textPrimary, secondary: textSecondary,
                                  accent: tint, iconBackdrop: tint.opacity(0.2),
                                  shadow: isDark ? Color.black.opacity(0.75) : Color.white.opacity(0.9))
        }
        // «Мой прогресс» — палитра темы с оранжевым акцентом: на градиенте огня не читались бы цвета статусов дней.
        if case .streak = event {
            // Светлый огонь — оранжево-красный градиент с белым текстом, тёмный — угли с оранжевым отсветом.
            return ShareCardStyle(fill: .fire, isDark: isDark, primary: .white,
                                  secondary: Color.white.opacity(isDark ? 0.72 : 0.88),
                                  accent: isDark ? Color(red: 1, green: 0.62, blue: 0.25) : .white,
                                  iconBackdrop: isDark ? Color.orange.opacity(0.2) : Color.white.opacity(0.2), shadow: nil)
        }
        return ShareCardStyle(fill: .palette(isDark ? dark : light), isDark: isDark, primary: textPrimary,
                              secondary: textSecondary, accent: tint, iconBackdrop: tint.opacity(isDark ? 0.22 : 0.15),
                              shadow: nil)
    }

    static func tint(_ event: ShareEvent) -> Color {
        switch event {
        case .achievement(let achievement, _): AchievementStyle.tint(achievement.category)
        case .streak, .progress: .orange
        case .speedRecord: .blue
        case .stage: .purple
        case .course: .green
        }
    }
}

/// Ограничивает ширину одного дочернего вида сверху, не растягивая его: предлагает `min(предложенная, cap)`, а размер
/// берёт у потомка. Обычный `frame(maxWidth:)` занял бы всю предложенную ширину, и короткий текст в строке «иконка +
/// заголовок» сместился бы к краю, а без ограничения `Text` с `minimumScaleFactor` вылезает за карточку.
private struct WidthCap: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        return child.sizeThatFits(ProposedViewSize(width: min(proposal.width ?? cap, cap), height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private extension View {
    /// Без `width` — как есть.
    @ViewBuilder func cappedWidth(_ width: CGFloat?) -> some View {
        if let width { WidthCap(cap: width) { self } } else { self }
    }
}

/// Картинка-карточка фиксированного размера формата: иконка события, заголовок, главная строка, подзаголовок,
/// подпись, дата и водяной знак с иконкой приложения (и по желанию QR-код). Её же рисует `ShareCardRenderer` и предпросмотр листа.
struct ShareCardView: View {
    let text: ShareCardText
    let icon: String
    let options: ShareOptions
    let style: ShareCardStyle
    /// Иконка приложения; `nil` — нарисованная замена (запуск без бандла приложения).
    var appIcon: NSImage?
    /// Данные календаря у карточки «Мой прогресс» (`nil` у прочих событий); раскладку выбирает `progressParts`: рисует «Мой прогресс» только при наличии и данных, и текста.
    var progress: ProgressCardData?

    /// Карточка по настройкам приложения: единица скорости и палитры тем — из `defaults`.
    @MainActor
    static func make(card: ShareCard, options: ShareOptions, profile: ShareProfile,
                     defaults: UserDefaults = .standard, bundle: Bundle = .main, locale: Locale? = nil,
                     appIcon: NSImage? = ShareCardView.bundledAppIcon) -> ShareCardView {
        let unit = defaults.string(forKey: SettingsKey.speedUnit).flatMap(SpeedUnit.init(rawValue:)) ?? .cpm
        let light = (defaults.string(forKey: SettingsKey.lightPalette).flatMap(LightPalette.init(rawValue:)) ?? .white).palette
        let dark = (defaults.string(forKey: SettingsKey.darkPalette).flatMap(DarkPalette.init(rawValue:)) ?? .graphite).palette
        let text = ShareCardText(card: card, options: options, profile: profile, unit: unit, bundle: bundle, locale: locale)
        return ShareCardView(
            text: text, icon: card.event.icon, options: options,
            style: ShareCardStyle.make(event: card.event, options: options, light: light, dark: dark),
            appIcon: appIcon, progress: card.event.progressData)
    }

    /// `AppIcon.icns` из ресурсов приложения (кладёт scripts/build-app.sh), читается один раз.
    @MainActor static let bundledAppIcon: NSImage? = Bundle.main.image(forResource: "AppIcon")

    var body: some View {
        let size = options.format.size
        ZStack {
            background
            Group {
                switch (options.format, progressParts) {
                case (.wide, let parts?): progressWide(parts)
                case (.wide, nil): wide
                case (.square, let parts?): progressVertical(parts, .square)
                case (.square, nil): vertical(.square)
                case (.story, let parts?): progressVertical(parts, .story)
                case (.story, nil): vertical(.story)
                }
            }
            .shadow(color: style.shadow ?? .clear, radius: style.shadow == nil ? 0 : 6)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    // MARK: Раскладки

    /// Поля, иконка и промежуток широкой раскладки; ширина текстовой колонки — остаток.
    private static let widePadding: CGFloat = 72, wideIcon: CGFloat = 232, wideGap: CGFloat = 56

    private var wide: some View {
        let textWidth = ShareFormat.wide.size.width - 2 * Self.widePadding - Self.wideIcon - Self.wideGap
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Self.wideGap) {
                eventIcon(size: Self.wideIcon)
                VStack(alignment: .leading, spacing: 14) {
                    header(size: 28)
                    headline(size: isNumeric ? 150 : 74, alignment: .leading, width: textWidth)
                    subtitle(size: 30, alignment: .leading, width: textWidth)
                    footnote(size: 22, alignment: .leading, width: textWidth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            wideFooter
        }
        .padding(.horizontal, Self.widePadding)
        .padding(.vertical, 56)
    }

    /// Низ широкой карточки: QR и водяной знак слева, подпись и дата справа.
    var wideFooter: some View {
        HStack(alignment: .bottom, spacing: 24) {
            HStack(spacing: 24) {
                if options.showsQR { qrCode(side: 120) }
                watermark(iconSize: 52, fontSize: 23)
            }
            Spacer(minLength: 24)
            VStack(alignment: .trailing, spacing: 6) { signatureAndDate(signature: 30, date: 23) }
        }
    }

    /// Размеры вертикальных раскладок: квадрат и «сторис» (та же раскладка, крупнее и выше).
    struct Metrics {
        let icon, header, headline, numericHeadline, subtitle, footnote: CGFloat
        let signature, date, watermarkIcon, watermarkFont, padding, qr: CGFloat

        static let square = Metrics(icon: 300, header: 32, headline: 88, numericHeadline: 200, subtitle: 34, footnote: 26,
                                    signature: 38, date: 28, watermarkIcon: 56, watermarkFont: 26, padding: 80, qr: 150)
        static let story = Metrics(icon: 360, header: 40, headline: 110, numericHeadline: 260, subtitle: 42, footnote: 30,
                                   signature: 46, date: 32, watermarkIcon: 64, watermarkFont: 30, padding: 96, qr: 200)
    }

    private func vertical(_ metrics: Metrics) -> some View {
        let textWidth = options.format.size.width - 2 * metrics.padding
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            eventIcon(size: metrics.icon)
            Spacer().frame(height: 48)
            VStack(spacing: 18) {
                header(size: metrics.header)
                headline(size: isNumeric ? metrics.numericHeadline : metrics.headline, alignment: .center, width: textWidth)
                subtitle(size: metrics.subtitle, alignment: .center, width: textWidth)
                footnote(size: metrics.footnote, alignment: .center, width: textWidth)
            }
            Spacer(minLength: 32)
            VStack(spacing: 8) { signatureAndDate(signature: metrics.signature, date: metrics.date) }
            Spacer().frame(height: 52)
            HStack(spacing: 28) {
                if options.showsQR { qrCode(side: metrics.qr) }
                watermark(iconSize: metrics.watermarkIcon, fontSize: metrics.watermarkFont)
            }
        }
        .padding(metrics.padding)
    }

    // MARK: Части

    /// Главная строка — число (рекорд скорости): рисуем крупнее.
    private var isNumeric: Bool { Int(text.headline) != nil }

    func eventIcon(size: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(style.accent)
            .frame(width: size, height: size)
            .background(style.iconBackdrop, in: Circle())
    }

    func header(size: CGFloat) -> some View {
        Text(verbatim: text.header)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .tracking(size * 0.08)
            .foregroundStyle(style.accent)
    }

    func headline(size: CGFloat, alignment: TextAlignment, width: CGFloat? = nil) -> some View {
        Text(verbatim: text.headline)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(style.primary)
            .multilineTextAlignment(alignment)
            .lineLimit(isNumeric ? 1 : 3)
            .minimumScaleFactor(0.45)
            .fixedSize(horizontal: false, vertical: true)
            .cappedWidth(width)
    }

    /// `width` (у `headline`, `subtitle`, `footnote`) — ширина, отведённая тексту: без неё `Text` с `minimumScaleFactor`
    /// не переносится и не сжимается, а берёт ширину одной строки и вылезает за поля карточки (длинная сноска «За что: …»).
    @ViewBuilder func subtitle(size: CGFloat, alignment: TextAlignment, width: CGFloat? = nil) -> some View {
        if let subtitle = text.subtitle {
            Text(verbatim: subtitle)
                .font(.system(size: size, weight: .medium, design: .rounded))
                .foregroundStyle(style.secondary)
                .multilineTextAlignment(alignment)
                // У «Мой прогресс» до трёх строк, и каждая может перенестись: запас, чтобы ничего не обрезалось.
                .lineLimit(text.progress == nil ? 3 : 6)
                .minimumScaleFactor(0.7)
                .cappedWidth(width)
        }
    }

    /// «За что: …» у ачивки: мелкая строка под подзаголовком.
    @ViewBuilder func footnote(size: CGFloat, alignment: TextAlignment, width: CGFloat? = nil) -> some View {
        if let footnote = text.footnote {
            Text(verbatim: footnote)
                .font(.system(size: size, weight: .medium, design: .rounded))
                .foregroundStyle(style.secondary)
                .multilineTextAlignment(alignment)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .cappedWidth(width)
                .padding(.top, size * 0.3)
        }
    }

    @ViewBuilder func signatureAndDate(signature: CGFloat, date: CGFloat) -> some View {
        if let name = text.signature {
            Text(verbatim: name)
                .font(.system(size: signature, weight: .bold, design: .rounded))
                .foregroundStyle(style.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        Text(verbatim: text.date)
            .font(.system(size: date, weight: .medium, design: .rounded))
            .foregroundStyle(style.secondary)
    }

    /// Иконка приложения слева, справа от неё две строки: название (полужирное) и ссылка (мельче, secondary).
    func watermark(iconSize: CGFloat, fontSize: CGFloat) -> some View {
        HStack(spacing: 14) {
            appIconImage.frame(width: iconSize, height: iconSize)
            VStack(alignment: .leading, spacing: fontSize * 0.12) {
                Text(verbatim: text.appName)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(style.primary)
                Text(verbatim: text.link)
                    .font(.system(size: fontSize * 0.8, weight: .medium, design: .rounded))
                    .foregroundStyle(style.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    /// QR-код со ссылкой: всегда тёмные модули на белой подложке с тихой зоной, в любой теме и на любом фоне
    /// (светлые модули на тёмном читаются не всеми сканерами).
    @ViewBuilder func qrCode(side: CGFloat) -> some View {
        if let mask = Self.qrMask {
            Image(decorative: mask, scale: 1)
                .interpolation(.none)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(Color(white: 0.11))
                // Тихая зона — 4 модуля, как требует стандарт QR: плашка того же размера, модули чуть мельче.
                .padding(side / CGFloat(mask.width + 8) * 4)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                .accessibilityHidden(true)
        }
    }

    /// Модули QR со ссылкой на приложение, строятся один раз.
    private static let qrMask = ShareQRCode.moduleMask()

    @ViewBuilder private var appIconImage: some View {
        if let appIcon {
            Image(nsImage: appIcon).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else {
            // Замена иконки по мотивам AppIconView из scripts/make-icon.swift: оранжевая плашка с огоньком.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.64, blue: 0.47),
                                              Color(red: 0.86, green: 0.38, blue: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(Image(systemName: "flame.fill").font(.system(size: 26, weight: .bold)).foregroundStyle(.white))
                .padding(4)
        }
    }

    // MARK: Фон

    @ViewBuilder private var background: some View {
        switch style.fill {
        case .none:
            Color.clear
        case .fire:
            ZStack {
                LinearGradient(colors: style.isDark
                               ? [Color(red: 0.30, green: 0.09, blue: 0.05), Color(red: 0.11, green: 0.04, blue: 0.04)]
                               : [Color(red: 1.0, green: 0.66, blue: 0.24), Color(red: 0.93, green: 0.34, blue: 0.15),
                                  Color(red: 0.78, green: 0.15, blue: 0.17)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Color.orange.opacity(style.isDark ? 0.35 : 0.25), .clear],
                               center: .topLeading, startRadius: 0, endRadius: options.format.size.width * 0.75)
                watermarkSymbol(Color.white.opacity(style.isDark ? 0.05 : 0.1))
            }
        case .palette(let palette):
            ZStack {
                LinearGradient(colors: [palette.background, palette.card], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [style.accent.opacity(style.isDark ? 0.3 : 0.2), .clear],
                               center: .topLeading, startRadius: 0, endRadius: options.format.size.width * 0.8)
                watermarkSymbol(style.accent.opacity(style.isDark ? 0.08 : 0.07))
            }
        }
    }

    /// Крупный бледный символ события в углу фона.
    private func watermarkSymbol(_ color: Color) -> some View {
        let size = options.format.size
        return Image(systemName: icon)
            .font(.system(size: min(size.width, size.height) * 0.75, weight: .bold))
            .foregroundStyle(color)
            .offset(x: size.width * 0.32, y: size.height * 0.22)
    }
}
