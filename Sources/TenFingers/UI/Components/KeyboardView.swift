import SwiftUI
import TypingCore

enum KeyMark {
    case next, error, intro
}

struct KeyboardView: View {
    let snapshot: LayoutSnapshot
    let marks: [UInt16: KeyMark]
    var shiftDown = false
    var unit: CGFloat = 40
    /// Подсветка пробела только на этой половине (каким большим пальцем жать); `nil` — весь пробел.
    var spaceHalf: Hand? = nil
    @Environment(\.palette) private var palette
    private let spacing = CGFloat(KeyboardSizing.keySpacing)

    static func marks(for highlight: KeyHighlight?) -> [UInt16: KeyMark] {
        guard let highlight else { return [:] }
        let mark: KeyMark = highlight.isError ? .error : .next
        var marks = [highlight.keyCode: mark]
        if let shift = highlight.shiftKeyCode { marks[shift] = mark }
        return marks
    }

    /// Половина пробела для подсказки большого пальца.
    static func spaceHalf(for highlight: KeyHighlight?) -> Hand? {
        guard let highlight, highlight.keyCode == KeyboardGeometry.space else { return nil }
        return highlight.spaceThumb
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(KeyboardGeometry.rows(for: snapshot.shape).enumerated()), id: \.offset) { index, row in
                HStack(spacing: spacing) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, slot in key(slot) }
                }
                .padding(.leading, index == 4 ? (unit + spacing) * 4 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func key(_ slot: KeySlot) -> some View {
        if slot.keyCode == KeyboardGeometry.space {
            spaceKey(slot)
        } else {
            plainKey(slot)
        }
    }

    private func width(_ slot: KeySlot) -> CGFloat { slot.width * unit + (slot.width - 1) * spacing }

    private func plainKey(_ slot: KeySlot) -> some View {
        let finger = FingerMap.finger(for: slot.keyCode)
        let mark = marks[slot.keyCode]
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill((finger.map(FingerPalette.color) ?? .gray).opacity(palette.keyOpacity * (finger == nil ? 0.45 : 1)))
            RoundedRectangle(cornerRadius: 6)
                .stroke(strokeColor(mark), lineWidth: mark == nil ? 0.5 : 3)
            label(slot)
            if KeyboardGeometry.homeBumps.contains(slot.keyCode) {
                Capsule().fill(.primary.opacity(0.5)).frame(width: 10, height: 2).offset(y: unit / 2 - 7)
            }
        }
        .frame(width: width(slot), height: unit * 0.92)
        .scaleEffect(mark == .intro ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: mark)
    }

    /// Пробел из двух половин (левый и правый большой палец) с тонким разделителем.
    /// При известной руке подсвечивается только нужная половина.
    private func spaceKey(_ slot: KeySlot) -> some View {
        let mark = marks[slot.keyCode]
        let half = mark == nil ? nil : spaceHalf
        let color = FingerPalette.color(.thumb)
        let halfWidth = width(slot) / 2
        return ZStack {
            HStack(spacing: 0) {
                Rectangle().fill(color.opacity(palette.keyOpacity))
                Rectangle().fill(color.opacity(palette.keyOpacity * 0.7))
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            Rectangle()
                .fill(.primary.opacity(0.25))
                .frame(width: 1)
                .padding(.vertical, unit * 0.18)
            RoundedRectangle(cornerRadius: 6)
                .stroke(strokeColor(half == nil ? mark : nil), lineWidth: half == nil && mark != nil ? 3 : 0.5)
            if let half, let mark {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(strokeColor(mark), lineWidth: 3)
                    .frame(width: halfWidth)
                    .frame(maxWidth: .infinity, alignment: half == .left ? .leading : .trailing)
            }
        }
        .frame(width: width(slot), height: unit * 0.92)
        .scaleEffect(mark == .intro && half == nil ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: mark)
        .animation(.easeOut(duration: 0.15), value: half)
    }

    @ViewBuilder private func label(_ slot: KeySlot) -> some View {
        if let special = KeyboardGeometry.specialLabels[slot.keyCode] {
            Text(special).font(.system(size: 10)).foregroundStyle(.secondary)
        } else {
            let plain = snapshot.plain[slot.keyCode] ?? ""
            let shifted = snapshot.shifted[slot.keyCode] ?? ""
            if plain.first?.isLetter == true {
                Text(shiftDown ? shifted : plain.uppercased()).font(.system(size: 15, weight: .medium))
            } else {
                VStack(spacing: 0) {
                    Text(shifted).font(.system(size: 10)).foregroundStyle(shiftDown ? .primary : .secondary)
                    Text(plain).font(.system(size: 13)).foregroundStyle(shiftDown ? .secondary : .primary)
                }
            }
        }
    }

    private func strokeColor(_ mark: KeyMark?) -> Color {
        switch mark {
        case .next, .intro: .accentColor
        case .error: .red
        case nil: .primary.opacity(0.15)
        }
    }
}

#Preview {
    KeyboardView(
        snapshot: LayoutSnapshot(id: "p", language: .en, shape: .ansi,
                                 plain: [3: "f", 38: "j", 22: "6"], shifted: [3: "F", 38: "J", 22: "^"]),
        marks: [22: .next, 56: .next]
    )
    .padding()
}
