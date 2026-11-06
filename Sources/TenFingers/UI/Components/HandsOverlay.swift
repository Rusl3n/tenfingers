import SwiftUI
import TypingCore

/// Нажатие, которое показывают кончики: клавиша, нужен ли Shift и какой большой палец жмёт пробел.
struct HandsPress: Equatable {
    let keyCode: UInt16
    var shift = false
    var spaceHalf: Hand? = nil
}

/// Что нужно слою кончиков от экрана: нажатие, его начало и двигаются ли кружки.
struct HandsState: Equatable {
    var press: HandsPress?
    var startedAt: Date = .distantPast
    var moves = true
    /// Последовательность нажатий (повтор замера): несколько пальцев одновременно; `press` при этом не используется.
    var sequence: HandsSequence?
}

/// Нажатие в разгаре: сколько прошло и сколько оно длится (при быстром темпе короче 520 мс).
struct ActiveHandsPress: Equatable {
    let press: HandsPress
    let elapsedMs: Double
    var durationMs = FingerPress.durationMs
}

/// Запись нажатий для повтора: `presses` идут вровень с `playback.keys` (`nil` — знака нет в раскладке).
/// Время считает сам слой: от `startedAt`, а при `frozenAtMs` стоит на этом моменте (пауза, конец).
struct HandsSequence: Equatable {
    let id: UUID
    let playback: ReplayPlayback
    let presses: [HandsPress?]
    var startedAt: Date = .distantPast
    var frozenAtMs: Double?

    static func == (lhs: HandsSequence, rhs: HandsSequence) -> Bool {
        lhs.id == rhs.id && lhs.startedAt == rhs.startedAt && lhs.frozenAtMs == rhs.frozenAtMs
    }

    var isRunning: Bool { frozenAtMs == nil }

    func elapsedMs(now: Date) -> Double { frozenAtMs ?? now.timeIntervalSince(startedAt) * 1000 }

    /// Нажатия, идущие в момент `ms`, по порядку начала.
    func active(atMs ms: Double) -> [ActiveHandsPress] {
        playback.active(atMs: ms).compactMap { item in
            presses[item.index].map { ActiveHandsPress(press: $0, elapsedMs: item.elapsedMs, durationMs: item.durationMs) }
        }
    }
}

/// Кружок одного кончика в данный момент.
struct FingerTip: Equatable {
    /// Левый и правый большие пальцы различаются, поэтому `Finger` сам по себе не идентификатор.
    let id: String
    let finger: Finger
    let point: PlanePoint
    let isDown: Bool
}

/// Клавиша на плоскости клавиатуры в базовых единицах `KeyboardView`.
struct KeyFrame: Equatable {
    let center: PlanePoint
    let width: Double
    let height: Double
}

/// Чистая часть кончиков: где стоят клавиши, где кружки в момент нажатия и что вообще рисовать.
enum HandsOverlayModel {
    /// Центры и размеры клавиш в тех же единицах, в которых `KeyboardView` рисует клавиатуру.
    static func keyFrames(shape: KeyboardShape, unit: Double = KeyboardSizing.baseUnit,
                          spacing: Double = KeyboardSizing.keySpacing) -> [UInt16: KeyFrame] {
        var frames: [UInt16: KeyFrame] = [:]
        let height = unit * 0.92
        for (index, row) in KeyboardGeometry.rows(for: shape).enumerated() {
            var x = index == 4 ? (unit + spacing) * 4 : 0
            let y = Double(index) * (height + spacing) + height / 2
            for slot in row {
                let width = slot.width * unit + (slot.width - 1) * spacing
                frames[slot.keyCode] = KeyFrame(center: PlanePoint(x: x + width / 2, y: y), width: width, height: height)
                x += width + spacing
            }
        }
        return frames
    }

    static func keyboardWidth(unit: Double = KeyboardSizing.baseUnit, spacing: Double = KeyboardSizing.keySpacing) -> Double {
        15 * unit + 14 * spacing
    }

    /// Кончики больших пальцев: ⅓ и ⅔ ширины пробела.
    static func thumbPoints(_ frames: [UInt16: KeyFrame]) -> (left: PlanePoint, right: PlanePoint) {
        guard let space = frames[KeyboardGeometry.space] else { return (PlanePoint(x: 0, y: 0), PlanePoint(x: 0, y: 0)) }
        let left = space.center.x - space.width / 2
        return (PlanePoint(x: left + space.width / 3, y: space.center.y),
                PlanePoint(x: left + space.width * 2 / 3, y: space.center.y))
    }

    static func layout(shape: KeyboardShape, unit: Double = KeyboardSizing.baseUnit,
                       spacing: Double = KeyboardSizing.keySpacing) -> FingerTipsLayout {
        let frames = keyFrames(shape: shape, unit: unit, spacing: spacing)
        var homes: [Finger: PlanePoint] = [:]
        for finger in Finger.allCases where finger != .thumb {
            if let frame = frames[finger.homeKeyCode] { homes[finger] = frame.center }
        }
        return FingerTipsLayout(homeKeys: homes, space: thumbPoints(frames), keyPitch: unit + spacing,
                                keyboardCenterX: keyboardWidth(unit: unit, spacing: spacing) / 2)
    }

    /// Кончики двигаются только при включённой настройке и без «Уменьшить движение»; иначе стоят.
    static func movesTips(setting: Bool, reduceMotion: Bool) -> Bool { setting && !reduceMotion }

    /// Все десять кружков в момент `elapsedMs` нажатия. Без движения (или без нажатия) все стоят дома.
    static func tips(layout: FingerTipsLayout, frames: [UInt16: KeyFrame], press: HandsPress?,
                     elapsedMs: Double, moves: Bool) -> [FingerTip] {
        tips(layout: layout, frames: frames, active: press.map { [ActiveHandsPress(press: $0, elapsedMs: elapsedMs)] } ?? [],
             moves: moves)
    }

    /// То же для нескольких одновременных нажатий (по порядку начала). Палец занят одним нажатием: позднее заменяет раннее.
    static func tips(layout: FingerTipsLayout, frames: [UInt16: KeyFrame], active: [ActiveHandsPress],
                     moves: Bool) -> [FingerTip] {
        let active = moves ? active : []
        var result: [FingerTip] = []
        for finger in Finger.allCases where finger != .thumb {
            var point = layout.home(finger)
            var isDown = false
            for item in active {
                let progress = FingerPress.progress(elapsedMs: item.elapsedMs, durationMs: item.durationMs)
                let down = FingerPress.isDown(elapsedMs: item.elapsedMs, durationMs: item.durationMs)
                if finger == FingerMap.finger(for: item.press.keyCode), let target = frames[item.press.keyCode]?.center {
                    point = layout.position(finger: finger, target: target, progress: progress)
                    isDown = down
                } else if item.press.shift, finger == shiftFinger(item.press),
                          let target = frames[FingerMap.shiftKey(for: item.press.keyCode)]?.center {
                    point = layout.position(finger: finger, target: target, progress: progress)
                    isDown = down
                }
            }
            result.append(FingerTip(id: finger.rawValue, finger: finger, point: point, isDown: isDown))
        }
        var leftDown = false, rightDown = false
        for item in active where item.press.keyCode == KeyboardGeometry.space {
            let down = FingerPress.isDown(elapsedMs: item.elapsedMs, durationMs: item.durationMs)
            let right = (item.press.spaceHalf ?? .right) == .right
            if right { rightDown = down; leftDown = false } else { leftDown = down; rightDown = false }
        }
        result.append(FingerTip(id: "thumbLeft", finger: .thumb, point: layout.thumbs.left, isDown: leftDown))
        result.append(FingerTip(id: "thumbRight", finger: .thumb, point: layout.thumbs.right, isDown: rightDown))
        return result
    }

    private static func shiftFinger(_ press: HandsPress) -> Finger {
        FingerMap.shiftKey(for: press.keyCode) == KeyboardGeometry.rightShift ? .rightPinky : .leftPinky
    }

    /// Клавиши, подсвеченные как нажатые в момент `elapsedMs`.
    static func pressedKeys(press: HandsPress?, elapsedMs: Double, moves: Bool) -> [UInt16] {
        guard moves, let press else { return [] }
        return pressedKeys(active: [ActiveHandsPress(press: press, elapsedMs: elapsedMs)])
    }

    /// Подсвеченные клавиши для нескольких нажатий; движение кончиков не нужно (при «Уменьшить движение» тоже).
    static func pressedKeys(active: [ActiveHandsPress]) -> [UInt16] {
        var keys: [UInt16] = []
        for item in active where FingerPress.isDown(elapsedMs: item.elapsedMs, durationMs: item.durationMs) {
            keys.append(item.press.keyCode)
            if item.press.shift { keys.append(FingerMap.shiftKey(for: item.press.keyCode)) }
        }
        return keys
    }
}

/// Прозрачный слой над клавиатурой: десять кружков-кончиков и пунктирная дуга нажатия. Размер — базовый, как у
/// `KeyboardView`; масштабирует его `ScaledKeyboardView`. В покое — статичный `Canvas`, `TimelineView(.animation)`
/// живёт только пока идёт нажатие (520 мс).
struct HandsOverlay: View {
    let shape: KeyboardShape
    var press: HandsPress?
    /// Когда началось нажатие `press`.
    var startedAt: Date = .distantPast
    var moves = true
    var sequence: HandsSequence?
    @Environment(\.palette) private var palette

    var body: some View {
        let layout = HandsOverlayModel.layout(shape: shape)
        let frames = HandsOverlayModel.keyFrames(shape: shape)
        Group {
            if let sequence {
                if sequence.isRunning {
                    TimelineView(.animation) { context in
                        canvas(layout: layout, frames: frames, active: sequence.active(atMs: sequence.elapsedMs(now: context.date)),
                               highlightsAlways: true)
                    }
                } else {
                    canvas(layout: layout, frames: frames, active: sequence.active(atMs: sequence.frozenAtMs ?? 0),
                           highlightsAlways: true)
                }
            } else if moves, press != nil {
                TimelineView(.animation) { context in
                    canvas(layout: layout, frames: frames, active: single(context.date.timeIntervalSince(startedAt) * 1000))
                }
            } else {
                canvas(layout: layout, frames: frames, active: single(0))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func single(_ elapsedMs: Double) -> [ActiveHandsPress] {
        press.map { [ActiveHandsPress(press: $0, elapsedMs: elapsedMs)] } ?? []
    }

    private func canvas(layout: FingerTipsLayout, frames: [UInt16: KeyFrame], active: [ActiveHandsPress],
                        highlightsAlways: Bool = false) -> some View {
        Canvas { context, _ in
            let shown = highlightsAlways || moves ? active : []
            for key in HandsOverlayModel.pressedKeys(active: shown) {
                guard let frame = frames[key] else { continue }
                let rect = CGRect(x: frame.center.x - frame.width / 2, y: frame.center.y - frame.height / 2,
                                  width: frame.width, height: frame.height)
                context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.accentColor), lineWidth: 3)
            }
            if moves {
                for item in active where item.elapsedMs < item.durationMs {
                    for (finger, target) in arcTargets(press: item.press, frames: frames) {
                        let arc = layout.arc(finger: finger, to: target)
                        guard arc.start != arc.end else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: arc.start.x, y: arc.start.y))
                        path.addQuadCurve(to: CGPoint(x: arc.end.x, y: arc.end.y),
                                          control: CGPoint(x: arc.control.x, y: arc.control.y))
                        context.stroke(path, with: .color(FingerPalette.color(finger).opacity(0.9)),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                    }
                }
            }
            for tip in HandsOverlayModel.tips(layout: layout, frames: frames, active: active, moves: moves) {
                let d = layout.diameter(pressing: tip.isDown)
                let rect = CGRect(x: tip.point.x - d / 2, y: tip.point.y - d / 2, width: d, height: d)
                context.fill(Path(ellipseIn: rect), with: .color(FingerPalette.color(tip.finger).opacity(0.8)))
                context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85)), lineWidth: 1.5)
            }
        }
    }

    /// Пальцы, у которых рисуется дуга: нажимающий и (с Shift) мизинец противоположной руки.
    private func arcTargets(press: HandsPress, frames: [UInt16: KeyFrame]) -> [(Finger, PlanePoint)] {
        var result: [(Finger, PlanePoint)] = []
        if let finger = FingerMap.finger(for: press.keyCode), let target = frames[press.keyCode]?.center {
            result.append((finger, target))
        }
        if press.shift {
            let shift = FingerMap.shiftKey(for: press.keyCode)
            if let target = frames[shift]?.center {
                result.append((shift == KeyboardGeometry.rightShift ? .rightPinky : .leftPinky, target))
            }
        }
        return result
    }
}
