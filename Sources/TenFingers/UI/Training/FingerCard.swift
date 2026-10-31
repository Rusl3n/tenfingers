import SwiftUI
import TypingCore

/// Данные карточки «Пальцы»: восемь пальцев (слева направо, как на клавиатуре) с классом и кнопкой занятия.
struct FingerCardModel: Equatable {
    struct Cell: Identifiable, Equatable {
        let report: FingerReport
        /// Кнопку занятия можно показать: известны буквы пальца (из истории клавиш или раскладки).
        var hasLetters = true

        var finger: Finger { report.finger }
        var id: Finger { report.finger }
        /// «Слабый / норма / сильный / мало данных» — он же цвет клетки.
        var tone: FingerClass { report.kind }
        /// Кнопка занятия: «Точность» у слабого пальца, «Скорость» у сильного, у остальных кнопки нет.
        var drill: FingerDrill? {
            guard hasLetters else { return nil }
            return switch report.kind {
            case .weak: .accuracy
            case .strong: .speed
            case .normal, .noData: nil
            }
        }
        /// Точность: у «мало данных» — «—», а не процент по нескольким нажатиям.
        var accuracyText: String {
            guard report.kind != .noData, let accuracy = report.accuracy else { return "—" }
            return Formatting.percent(accuracy)
        }
    }

    let cells: [Cell]

    /// Нет ни одного пальца с данными (меньше 50 нажатий у каждого): кнопок нет.
    var hasData: Bool { cells.contains { $0.tone != .noData } }

    var leftHand: [Cell] { cells.filter { $0.finger.hand == .left } }
    var rightHand: [Cell] { cells.filter { $0.finger.hand == .right } }

    /// Порядок — как у таблицы пальцев в аналитике (`FingerRow.order`): левая рука от мизинца, правая от указательного.
    /// `fingerOf` — буква → палец: у пальца без букв кнопки занятия нет (занятие было бы случайными словами).
    static func make(reports: [FingerReport], fingerOf: [Character: Finger]) -> FingerCardModel {
        let order = FingerRow.order.filter { $0 != .thumb }
        let byFinger = Dictionary(reports.map { ($0.finger, $0) }, uniquingKeysWith: { first, _ in first })
        let withLetters = Set(fingerOf.values)
        return FingerCardModel(cells: order.compactMap { finger in
            byFinger[finger].map { Cell(report: $0, hasLetters: withLetters.contains(finger)) }
        })
    }
}

/// Карточка «Пальцы» экрана «Тренировка»: схема рук с раскраской по классу пальца и кнопками занятий.
struct FingerCard: View {
    let model: FingerCardModel
    let unit: SpeedUnit
    /// Раскладка не того языка, что курс: буквы пальцев не определить — подсказка вместо тихих пустых данных.
    var layoutPrompt: String?
    let start: (Finger, FingerDrill) -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Text("Пальцы").font(.title3.bold())
                Spacer()
                legend(.weak, "слабый", help: HelpText.fingerWeak)
                legend(.strong, "сильный", help: HelpText.fingerStrong)
            }
            HStack(alignment: .top, spacing: 24) {
                hand(model.leftHand)
                hand(model.rightHand)
            }
            if !model.hasData {
                Text("Мало данных: занимайтесь, и здесь появятся пальцы").foregroundStyle(.secondary)
            }
            if let layoutPrompt {
                Label(layoutPrompt, systemImage: "keyboard").font(.callout).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func hand(_ cells: [FingerCardModel.Cell]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(cells) { cell($0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(_ tone: FingerClass, _ title: LocalizedStringKey, help: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(Self.color(tone)).frame(width: 10, height: 10)
            Text(title).font(.caption).foregroundStyle(.secondary)
            InfoButton(text: help, size: 11)
        }
    }

    private func cell(_ cell: FingerCardModel.Cell) -> some View {
        let report = cell.report
        let accuracy = cell.accuracyText
        let speed = report.speedCpm.map { unit.format($0) } ?? "—"
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(FingerPalette.color(cell.finger).opacity(max(palette.keyOpacity, 0.6)))
                .frame(width: 24, height: 6)
            Text(cell.finger.displayName.localizedCapitalizedFirst)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.title(cell.tone)).font(.caption2).foregroundStyle(Self.color(cell.tone))
            Text(accuracy).font(.callout).monospacedDigit()
            Text(speed).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            if let drill = cell.drill {
                Button(Self.buttonTitle(drill)) { start(cell.finger, drill) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Self.color(cell.tone).opacity(cell.tone == .noData ? 0.08 : 0.16),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Self.color(cell.tone).opacity(cell.tone == .noData ? 0.2 : 0.5), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    static func color(_ tone: FingerClass) -> Color {
        switch tone {
        case .weak: .orange
        case .strong: .green
        case .normal: .secondary
        case .noData: .gray
        }
    }

    static func title(_ tone: FingerClass) -> LocalizedStringKey {
        switch tone {
        case .weak: "слабый"
        case .normal: "норма"
        case .strong: "сильный"
        case .noData: "мало данных"
        }
    }

    static func buttonTitle(_ drill: FingerDrill) -> LocalizedStringKey {
        switch drill {
        case .accuracy: "Точность"
        case .speed: "Скорость"
        }
    }
}
