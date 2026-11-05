import SwiftUI
import TypingCore

/// Строка «Сертификат» над курсом, пока он не получен (фаза 8, §4): условие и текущее состояние. Нажатие открывает образец.
enum CertificatePreviewText {
    /// «Этапов сдано 3 из 7 · средняя проверок 98 зн/мин, нужно 120 зн/мин»; проверок ещё нет — «средняя появится после
    /// первой проверки этапа».
    static func status(_ progress: CertificateProgress, unit: SpeedUnit, bundle: Bundle = .main,
                       locale: Locale = Formatting.interfaceLocale()) -> String {
        guard let average = progress.averageCheckCpm else {
            return String(format: String(localized: "certificate.preview.noChecks", bundle: bundle, locale: locale),
                          locale: locale, progress.stagesPassed, progress.stagesTotal)
        }
        return String(format: String(localized: "certificate.preview.progress", bundle: bundle, locale: locale),
                      locale: locale, progress.stagesPassed, progress.stagesTotal, unit.format(average),
                      unit.format(progress.required))
    }
}

struct CertificatePreviewRow: View {
    let progress: CertificateProgress
    let language: Language
    let unit: SpeedUnit
    @State private var showsSample = false

    var body: some View {
        Button { showsSample = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "rosette").foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Сертификат").font(.callout.weight(.semibold))
                    Text(verbatim: CertificatePreviewText.status(progress, unit: unit))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Показать образец сертификата"))
        .sheet(isPresented: $showsSample) {
            CertificateSampleSheet(language: language, averageCpm: progress.averageCheckCpm ?? progress.required)
        }
    }
}

/// Образец сертификата: обычная карточка с именем из профиля и крупной пометкой «Образец» по диагонали.
struct CertificateSampleSheet: View {
    let language: Language
    let averageCpm: Double
    @Environment(\.dismiss) private var dismiss
    @State private var profile = ShareProfile.stored()

    private static let width: CGFloat = 560

    var body: some View {
        var options = ShareOptions.load(profile: profile)
        options.format = .wide
        options.signature = profile.defaultSignature
        let size = options.format.size
        let scale = Self.width / size.width
        let card = ShareCardView.make(card: ShareCard(.certificate(language: language, averageCpm: averageCpm)),
                                      options: options, profile: profile)
        return VStack(spacing: 16) {
            Text("Образец сертификата").font(.title2.bold())
            card
                .overlay {
                    Text("Образец")
                        .font(.system(size: 220, weight: .black, design: .rounded))
                        .foregroundStyle(Color.red.opacity(0.22))
                        .rotationEffect(.degrees(-24))
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                }
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: size.width * scale, height: size.height * scale, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Образец сертификата"))
            Text("Так будет выглядеть сертификат, когда курс пройден и средняя проверок достигнет нужной.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Закрыть") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .onExitCommand { dismiss() }
        .padding(24)
        .frame(width: Self.width + 48)
    }
}
