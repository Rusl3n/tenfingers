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
        case .streak: .orange
        case .speedRecord: .blue
        case .stage: .purple
        case .course: .green
        }
    }
}

/// Картинка-карточка фиксированного размера формата: иконка события, заголовок, главная строка, подзаголовок,
/// подпись, дата и водяной знак с иконкой приложения. Её же рисует `ShareCardRenderer` и предпросмотр листа.
struct ShareCardView: View {
    let text: ShareCardText
    let icon: String
    let options: ShareOptions
    let style: ShareCardStyle
    /// Иконка приложения; `nil` — нарисованная замена (запуск без бандла приложения).
    var appIcon: NSImage?

    /// Карточка по настройкам приложения: единица скорости и палитры тем — из `defaults`.
    @MainActor
    static func make(card: ShareCard, options: ShareOptions, profile: ShareProfile,
                     defaults: UserDefaults = .standard, bundle: Bundle = .main, locale: Locale? = nil,
                     appIcon: NSImage? = ShareCardView.bundledAppIcon) -> ShareCardView {
        let unit = defaults.string(forKey: SettingsKey.speedUnit).flatMap(SpeedUnit.init(rawValue:)) ?? .cpm
        let light = (defaults.string(forKey: SettingsKey.lightPalette).flatMap(LightPalette.init(rawValue:)) ?? .white).palette
        let dark = (defaults.string(forKey: SettingsKey.darkPalette).flatMap(DarkPalette.init(rawValue:)) ?? .graphite).palette
        return ShareCardView(
            text: ShareCardText(card: card, options: options, profile: profile, unit: unit, bundle: bundle, locale: locale),
            icon: card.event.icon, options: options,
            style: ShareCardStyle.make(event: card.event, options: options, light: light, dark: dark),
            appIcon: appIcon)
    }

    /// `AppIcon.icns` из ресурсов приложения (кладёт scripts/build-app.sh), читается один раз.
    @MainActor static let bundledAppIcon: NSImage? = Bundle.main.image(forResource: "AppIcon")

    var body: some View {
        let size = options.format.size
        ZStack {
            background
            Group {
                switch options.format {
                case .wide: wide
                case .square: square
                }
            }
            .shadow(color: style.shadow ?? .clear, radius: style.shadow == nil ? 0 : 6)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    // MARK: Раскладки

    private var wide: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 56) {
                eventIcon(size: 232)
                VStack(alignment: .leading, spacing: 14) {
                    header(size: 28)
                    headline(size: isNumeric ? 150 : 74, alignment: .leading)
                    subtitle(size: 30, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            HStack(alignment: .bottom, spacing: 24) {
                watermark(iconSize: 52, fontSize: 23)
                Spacer(minLength: 24)
                VStack(alignment: .trailing, spacing: 6) { signatureAndDate(signature: 30, date: 23) }
            }
        }
        .padding(.horizontal, 72)
        .padding(.vertical, 56)
    }

    private var square: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            eventIcon(size: 300)
            Spacer().frame(height: 48)
            VStack(spacing: 18) {
                header(size: 32)
                headline(size: isNumeric ? 200 : 88, alignment: .center)
                subtitle(size: 34, alignment: .center)
            }
            Spacer(minLength: 32)
            VStack(spacing: 8) { signatureAndDate(signature: 38, date: 28) }
            Spacer().frame(height: 52)
            watermark(iconSize: 56, fontSize: 26)
        }
        .padding(80)
    }

    // MARK: Части

    /// Главная строка — число (рекорд скорости): рисуем крупнее.
    private var isNumeric: Bool { Int(text.headline) != nil }

    private func eventIcon(size: CGFloat) -> some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(style.accent)
            .frame(width: size, height: size)
            .background(style.iconBackdrop, in: Circle())
    }

    private func header(size: CGFloat) -> some View {
        Text(verbatim: text.header)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .tracking(size * 0.08)
            .foregroundStyle(style.accent)
    }

    private func headline(size: CGFloat, alignment: TextAlignment) -> some View {
        Text(verbatim: text.headline)
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .foregroundStyle(style.primary)
            .multilineTextAlignment(alignment)
            .lineLimit(isNumeric ? 1 : 3)
            .minimumScaleFactor(0.45)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func subtitle(size: CGFloat, alignment: TextAlignment) -> some View {
        if let subtitle = text.subtitle {
            Text(verbatim: subtitle)
                .font(.system(size: size, weight: .medium, design: .rounded))
                .foregroundStyle(style.secondary)
                .multilineTextAlignment(alignment)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder private func signatureAndDate(signature: CGFloat, date: CGFloat) -> some View {
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

    private func watermark(iconSize: CGFloat, fontSize: CGFloat) -> some View {
        HStack(spacing: 12) {
            appIconImage.frame(width: iconSize, height: iconSize)
            Text(verbatim: text.watermark)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(style.secondary)
                .lineLimit(1)
        }
    }

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
