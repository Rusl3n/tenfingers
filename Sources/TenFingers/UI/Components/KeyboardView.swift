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
    @Environment(\.palette) private var palette
    private let spacing = CGFloat(KeyboardSizing.keySpacing)

    static func marks(for highlight: KeyHighlight?) -> [UInt16: KeyMark] {
        guard let highlight else { return [:] }
        let mark: KeyMark = highlight.isError ? .error : .next
        var marks = [highlight.keyCode: mark]
        if let shift = highlight.shiftKeyCode { marks[shift] = mark }
        return marks
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

    private func key(_ slot: KeySlot) -> some View {
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
        .frame(width: slot.width * unit + (slot.width - 1) * spacing, height: unit * 0.92)
        .scaleEffect(mark == .intro ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: mark)
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
