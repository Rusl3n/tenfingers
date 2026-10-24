import SwiftUI
import TypingCore

/// Карточка тепловой карты: переключатель «Ошибки / Медленные», клавиатура и шкала.
struct KeyboardHeatmapView: View {
    let snapshot: LayoutSnapshot
    let language: Language
    let keys: [KeyInfo]
    @State private var mode: HeatMode = .errors

    var body: some View {
        AnalyticsCard("Клавиатура") {
            Picker("Показать", selection: $mode) {
                Text("Ошибки").tag(HeatMode.errors)
                Text("Медленные").tag(HeatMode.slowness)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        } content: {
            if keys.isEmpty {
                Text("Пока мало данных")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HeatmapKeyboardView(snapshot: snapshot, language: language, keys: keys,
                                        heat: HeatmapModel.heat(keys, mode: mode))
                    HeatLegend(mode: mode)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Раскладка как у `KeyboardView`, но заливка клавиши идёт от цвета пальца к красному по `heat` (0…1).
/// Клавиши без данных бледнее; подсказка при наведении — нажатия, ошибки и время.
struct HeatmapKeyboardView: View {
    let snapshot: LayoutSnapshot
    let language: Language
    let keys: [KeyInfo]
    let heat: [UInt16: Double]
    var unit: CGFloat = 36
    @Environment(\.palette) private var palette
    private let spacing = CGFloat(KeyboardSizing.keySpacing)

    private var info: [UInt16: KeyInfo] { Dictionary(uniqueKeysWithValues: keys.map { ($0.keyCode, $0) }) }

    var body: some View {
        let info = info
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(KeyboardGeometry.rows(for: snapshot.shape).enumerated()), id: \.offset) { index, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, slot in key(slot, info: info[slot.keyCode]) }
                }
                .padding(.leading, index == 4 ? (unit + spacing) * 4 : 0)
            }
        }
    }

    private func width(_ slot: KeySlot) -> CGFloat { slot.width * unit + (slot.width - 1) * spacing }

    private func key(_ slot: KeySlot, info: KeyInfo?) -> some View {
        let finger = FingerMap.finger(for: slot.keyCode)
        let value = heat[slot.keyCode]
        let base = (finger.map(FingerPalette.color) ?? .gray)
            .opacity(palette.keyOpacity * (finger == nil ? 0.45 : 1) * (value == nil ? 0.5 : 1))
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(base)
            if let value {
                RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.1 + 0.8 * value))
            }
            RoundedRectangle(cornerRadius: 6).stroke(.primary.opacity(0.15), lineWidth: 0.5)
            Text(label(slot, info: info))
                .font(.system(size: KeyboardGeometry.specialLabels[slot.keyCode] == nil ? 14 : 9,
                              weight: .medium))
                .foregroundStyle(KeyboardGeometry.specialLabels[slot.keyCode] == nil ? .primary : .secondary)
        }
        .frame(width: width(slot), height: unit * 0.92)
        .help(info?.helpText() ?? "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(info?.helpText() ?? label(slot, info: nil)))
    }

    /// Подпись: символ текущей раскладки, если она того же языка, что статистика; иначе символ из статистики.
    private func label(_ slot: KeySlot, info: KeyInfo?) -> String {
        if let special = KeyboardGeometry.specialLabels[slot.keyCode] { return special }
        let plain = snapshot.language == language ? snapshot.plain[slot.keyCode] : nil
        let text = plain ?? info?.label ?? ""
        return text.first?.isLetter == true ? text.uppercased() : text
    }
}

/// Шкала под клавиатурой: от цвета пальца к красному.
struct HeatLegend: View {
    let mode: HeatMode

    var body: some View {
        HStack(spacing: 8) {
            Text(mode == .errors ? "Меньше ошибок" : "Быстрее")
            LinearGradient(colors: [Color.red.opacity(0.1), Color.red.opacity(0.9)], startPoint: .leading,
                           endPoint: .trailing)
                .frame(width: 140, height: 8)
                .clipShape(Capsule())
            Text(mode == .errors ? "Больше ошибок" : "Медленнее")
            Spacer()
            Text("Наведите на клавишу, чтобы увидеть подробности")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
