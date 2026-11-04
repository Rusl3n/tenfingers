import SwiftUI
import TypingCore

/// Оценка как подпись на поле и строка разбивки на итогах.
extension RhythmJudgement {
    var title: String {
        switch self {
        case .perfect: String(localized: "Точно")
        case .good: String(localized: "Хорошо")
        case .early: String(localized: "Рано")
        case .late: String(localized: "Поздно")
        case .miss: String(localized: "Мимо")
        }
    }

    var color: Color {
        switch self {
        case .perfect: Color(red: 0.20, green: 0.78, blue: 0.85)
        case .good: Color(red: 0.25, green: 0.72, blue: 0.35)
        case .early, .late: Color(red: 0.95, green: 0.62, blue: 0.15)
        case .miss: Color(red: 0.88, green: 0.27, blue: 0.27)
        }
    }
}

/// Положение элементов поля: чистая геометрия без рисования.
enum RhythmFieldLayout {
    static let laneCount = 8
    static let hudHeight: CGFloat = 92
    static let footerHeight: CGFloat = 40
    static let maxWidth: CGFloat = 780
    /// Линия попадания стоит на этой доле высоты поля, ниже неё нота доезжает до края.
    static let hitLineFraction: CGFloat = 0.86
    static let noteHeight: CGFloat = 36
    static let flashSeconds: TimeInterval = 0.1
    static let labelSeconds: TimeInterval = 0.4

    struct Geometry: Equatable {
        /// Поле дорожек (от HUD до подписей пальцев), по ширине — не шире `maxWidth`, по центру.
        let field: CGRect
        /// Расстояние линии попадания от верха поля.
        let hitLineY: CGFloat
        var laneWidth: CGFloat { field.width / CGFloat(RhythmFieldLayout.laneCount) }

        func laneRect(_ index: Int) -> CGRect {
            CGRect(x: field.minX + CGFloat(index) * laneWidth, y: field.minY, width: laneWidth, height: field.height)
        }

        /// Абсолютная координата линии попадания.
        var hitLine: CGFloat { field.minY + hitLineY }
    }

    static func geometry(in size: CGSize) -> Geometry {
        let width = min(size.width - 32, maxWidth)
        let height = max(160, size.height - hudHeight - footerHeight)
        let field = CGRect(x: (size.width - width) / 2, y: hudHeight, width: max(width, 160), height: height)
        return Geometry(field: field, hitLineY: height * hitLineFraction)
    }

    /// Положение ноты от верха поля: `hitLineY − (time − t) / scroll · hitLineY` — нота на линии при `time == t`,
    /// у верхнего края за `scrollSeconds` до этого.
    static func noteOffset(noteTime: TimeInterval, trackTime: TimeInterval, scrollSeconds: Double,
                           hitLineY: CGFloat) -> CGFloat {
        hitLineY - CGFloat((noteTime - trackTime) / scrollSeconds) * hitLineY
    }
}

/// Всё, что рисует поле в один кадр. Собирается из `RhythmPlayModel`, не зависит от времени рисования.
struct RhythmFieldFrame {
    struct Note {
        let index: Int
        let time: TimeInterval
        /// Время полёта этой ноты от верха до линии: у нот бесконечного трека своё, у обычных — уровня.
        let scrollSeconds: Double
        let character: Character
        let lane: RhythmLane
        /// Нота оценена «Мимо» и уезжает за линию тусклой.
        let missed: Bool
    }

    struct Label {
        let judgement: RhythmJudgement
        let lane: RhythmLane
        /// 0 — только появилась, 1 — исчезла.
        let age: Double
    }

    var trackTime: TimeInterval = 0
    /// Самое долгое время полёта нот кадра (окно отбора); положение ноты считается по её собственному.
    var scrollSeconds: Double = 2
    var notes: [Note] = []
    /// Яркость вспышки по дорожкам (0…1) и полосы пробела.
    var laneFlash = [Double](repeating: 0, count: RhythmFieldLayout.laneCount)
    var spaceFlash: Double = 0
    var label: Label?
    /// Число отсчёта 3-2-1; `nil` — трек идёт.
    var countdown: Int?
    var score = 0
    var combo = 0
    var multiplier = 1
    var health = RhythmGame.startHealth
    var progress: Double = 0
}

/// Поле игры: один `Canvas`. Шапка (очки, комбо, здоровье, прогресс), 8 дорожек цветами пальцев, ноты-плашки,
/// линия попадания, подписи пальцев, вспышки, оценка и отсчёт.
struct RhythmFieldCanvas: View {
    let frame: RhythmFieldFrame

    @Environment(\.palette) private var palette

    var body: some View {
        // Значения нужны внутри `Canvas` как копии: рисование не обращается к окружению и к игре.
        let frame = self.frame
        let keyOpacity = palette.keyOpacity
        Canvas { context, size in
            Self.draw(frame, keyOpacity: keyOpacity, in: &context, size: size)
        }
        .accessibilityHidden(true)
    }

    private static let fingerTitles: [String] = [
        String(localized: "мизинец"), String(localized: "безымянный"), String(localized: "средний"),
        String(localized: "указательный"), String(localized: "указательный"), String(localized: "средний"),
        String(localized: "безымянный"), String(localized: "мизинец"),
    ]

    static func color(forLane lane: RhythmLane) -> Color {
        switch lane {
        case .space: FingerPalette.color(.thumb)
        case .finger(let index): FingerPalette.color(RhythmLane.fingerOrder[index])
        }
    }

    // MARK: - Рисование

    private static func draw(_ frame: RhythmFieldFrame, keyOpacity: Double, in context: inout GraphicsContext,
                             size: CGSize) {
        let geometry = RhythmFieldLayout.geometry(in: size)
        drawLanes(frame, geometry, keyOpacity: keyOpacity, in: &context)
        drawNotes(frame, geometry, in: &context)
        drawLabel(frame, geometry, in: &context)
        drawFooter(geometry, in: &context)
        drawHud(frame, geometry, in: &context, size: size)
        if let number = frame.countdown {
            let text = context.resolve(Text("\(number)").font(.system(size: 120, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.primary.opacity(0.85)))
            context.draw(text, at: CGPoint(x: geometry.field.midX, y: geometry.field.minY + geometry.hitLineY * 0.45))
        }
    }

    private static func drawLanes(_ frame: RhythmFieldFrame, _ geometry: RhythmFieldLayout.Geometry, keyOpacity: Double,
                                  in context: inout GraphicsContext) {
        for index in 0..<RhythmFieldLayout.laneCount {
            let rect = geometry.laneRect(index)
            let color = color(forLane: .finger(index))
            context.fill(Path(rect.insetBy(dx: 1, dy: 0)), with: .color(color.opacity(0.07 + 0.08 * keyOpacity)))
            let flash = frame.laneFlash[index]
            if flash > 0 {
                context.fill(Path(rect.insetBy(dx: 1, dy: 0)), with: .color(color.opacity(0.45 * flash)))
            }
        }
        if frame.spaceFlash > 0 {
            let band = CGRect(x: geometry.field.minX, y: geometry.hitLine - 26, width: geometry.field.width, height: 52)
            context.fill(Path(roundedRect: band, cornerRadius: 10),
                         with: .color(color(forLane: .space).opacity(0.4 * frame.spaceFlash)))
        }
        // Линия попадания и «мишени» дорожек на ней.
        for index in 0..<RhythmFieldLayout.laneCount {
            let rect = geometry.laneRect(index).insetBy(dx: 4, dy: 0)
            let target = CGRect(x: rect.minX, y: geometry.hitLine - RhythmFieldLayout.noteHeight / 2,
                                width: rect.width, height: RhythmFieldLayout.noteHeight)
            context.stroke(Path(roundedRect: target, cornerRadius: 8),
                           with: .color(color(forLane: .finger(index)).opacity(0.7)), lineWidth: 2)
        }
        var line = Path()
        line.move(to: CGPoint(x: geometry.field.minX, y: geometry.hitLine))
        line.addLine(to: CGPoint(x: geometry.field.maxX, y: geometry.hitLine))
        context.stroke(line, with: .color(Color.primary.opacity(0.35)), lineWidth: 1)
    }

    private static func drawNotes(_ frame: RhythmFieldFrame, _ geometry: RhythmFieldLayout.Geometry,
                                  in context: inout GraphicsContext) {
        let height = RhythmFieldLayout.noteHeight
        // Дальние ноты рисуются первыми, чтобы ближние к линии были сверху.
        for note in frame.notes.reversed() {
            let offset = RhythmFieldLayout.noteOffset(noteTime: note.time, trackTime: frame.trackTime,
                                                      scrollSeconds: note.scrollSeconds, hitLineY: geometry.hitLineY)
            let centerY = geometry.field.minY + offset
            guard centerY > geometry.field.minY - height, centerY < geometry.field.maxY + height else { continue }
            let rect: CGRect
            switch note.lane {
            case .space:
                rect = CGRect(x: geometry.field.minX + 4, y: centerY - height / 2,
                              width: geometry.field.width - 8, height: height)
            case .finger(let index):
                let lane = geometry.laneRect(index)
                rect = CGRect(x: lane.minX + 4, y: centerY - height / 2, width: lane.width - 8, height: height)
            }
            let base = color(forLane: note.lane)
            let fill = note.missed ? Color.gray.opacity(0.35) : base.opacity(0.92)
            context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(fill))
            let text = note.lane == .space ? String(localized: "Пробел") : String(note.character).uppercased()
            let resolved = context.resolve(Text(text).font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(note.missed ? Color.secondary : Color.black.opacity(0.78)))
            context.draw(resolved, at: CGPoint(x: rect.midX, y: rect.midY))
        }
    }

    private static func drawLabel(_ frame: RhythmFieldFrame, _ geometry: RhythmFieldLayout.Geometry,
                                  in context: inout GraphicsContext) {
        guard let label = frame.label else { return }
        let x: CGFloat
        switch label.lane {
        case .space: x = geometry.field.midX
        case .finger(let index): x = geometry.laneRect(index).midX
        }
        let y = geometry.hitLine - 44 - CGFloat(label.age) * 14
        let text = context.resolve(Text(label.judgement.title).font(.system(size: 18, weight: .heavy, design: .rounded))
            .foregroundStyle(label.judgement.color.opacity(1 - label.age)))
        context.draw(text, at: CGPoint(x: x, y: y))
    }

    private static func drawFooter(_ geometry: RhythmFieldLayout.Geometry, in context: inout GraphicsContext) {
        for index in 0..<RhythmFieldLayout.laneCount {
            let rect = geometry.laneRect(index)
            let text = context.resolve(Text(fingerTitles[index]).font(.system(size: 11))
                .foregroundStyle(color(forLane: .finger(index))))
            context.draw(text, at: CGPoint(x: rect.midX, y: geometry.field.maxY + 16))
        }
    }

    private static func drawHud(_ frame: RhythmFieldFrame, _ geometry: RhythmFieldLayout.Geometry,
                                in context: inout GraphicsContext, size: CGSize) {
        let field = geometry.field
        let score = context.resolve(Text("\(frame.score)").font(.system(size: 30, weight: .bold, design: .rounded))
            .monospacedDigit())
        context.draw(score, at: CGPoint(x: field.minX, y: 28), anchor: .leading)

        let combo = context.resolve(Text("Комбо \(frame.combo)").font(.system(size: 20, weight: .semibold))
            .monospacedDigit())
        context.draw(combo, at: CGPoint(x: field.midX, y: 22))
        if frame.multiplier > 1 {
            let multiplier = context.resolve(Text("×\(frame.multiplier)").font(.system(size: 18, weight: .heavy,
                                                                                         design: .rounded))
                .foregroundStyle(Color.orange))
            context.draw(multiplier, at: CGPoint(x: field.midX, y: 44))
        }

        let hint = context.resolve(Text("Esc — пауза").font(.caption).foregroundStyle(Color.secondary))
        context.draw(hint, at: CGPoint(x: field.maxX, y: 22), anchor: .trailing)

        // Здоровье и прогресс трека: две тонкие полоски.
        bar(in: &context, frame: CGRect(x: field.minX, y: 58, width: field.width * 0.45, height: 8),
            value: Double(frame.health) / Double(RhythmGame.startHealth), color: healthColor(frame.health))
        let caption = context.resolve(Text("Здоровье").font(.caption2).foregroundStyle(Color.secondary))
        context.draw(caption, at: CGPoint(x: field.minX, y: 76), anchor: .leading)
        bar(in: &context, frame: CGRect(x: field.minX + field.width * 0.55, y: 58, width: field.width * 0.45, height: 8),
            value: frame.progress, color: .accentColor)
        let track = context.resolve(Text("Трек").font(.caption2).foregroundStyle(Color.secondary))
        context.draw(track, at: CGPoint(x: field.minX + field.width * 0.55, y: 76), anchor: .leading)
    }

    private static func healthColor(_ health: Int) -> Color {
        switch health {
        case 50...: Color(red: 0.25, green: 0.72, blue: 0.35)
        case 25...: Color(red: 0.95, green: 0.62, blue: 0.15)
        default: Color(red: 0.88, green: 0.27, blue: 0.27)
        }
    }

    private static func bar(in context: inout GraphicsContext, frame: CGRect, value: Double, color: Color) {
        context.fill(Path(roundedRect: frame, cornerRadius: 4), with: .color(Color.secondary.opacity(0.2)))
        let filled = CGRect(x: frame.minX, y: frame.minY, width: frame.width * CGFloat(min(1, max(0, value))),
                            height: frame.height)
        context.fill(Path(roundedRect: filled, cornerRadius: 4), with: .color(color))
    }
}
