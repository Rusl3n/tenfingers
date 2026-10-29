// Шаги уроков издания 2 по видам (спецификация фазы 6, §2.2, §2.3; §16, решения 4–7).

/// Шаг после разрешения: вид (с заменой sentences/text → phrases на этапах без text), длина, ряды, фокус, название.
public struct ResolvedStep: Equatable, Sendable {
    public let kind: ExerciseKind
    public let length: Int
    /// Ряды шага `rowWords` (из шаблона или урока); у остальных шагов — из шаблона, обычно пусто.
    public let rows: [RowName]
    /// Доля букв рядов у `rowWords`; у остальных шагов — из шаблона, обычно `nil`.
    public let minShare: Double?
    public let focus: StepFocus?
    /// Русский ключ названия: у разминки проверки этапа — «Разминка», иначе `kind.titleKey`.
    public let title: String
}

public enum StepTemplates {
    /// `minShare` по умолчанию (решение 6): «только ряд» — 1,0, пары и тройка — 0,6.
    static let singleRowShare = 1.0
    static let mixedRowsShare = 0.6

    /// Шаблон вида урока (§2.2) или `lesson.steps`, если задан.
    public static func templates(for ctx: LessonContext) -> [StepTemplate] {
        if let steps = ctx.lesson.steps { return steps }
        let stage = ctx.stageNumber
        switch ctx.lesson.resolvedKind {
        case .keys:
            if stage <= 1 {
                return [.init(.drill), .init(.combos), .init(.words), .init(.words), .init(.phrases), .init(.check)]
            }
            if stage <= 3 {
                return [.init(.drill), .init(.combos), .init(.words), .init(.focus),
                        .init(.rowWords, rows: newKeysRows(ctx), minShare: mixedRowsShare), .init(.phrases),
                        .init(.check)]
            }
            // Этап 4 («Буква Ё», «' и апостроф») — как этапы 5–6 (решение 7).
            return [.init(.drill), .init(.combos), .init(.words), .init(.sentences), .init(.sentences), .init(.text),
                    .init(.check)]
        case .rows:
            let rows = ctx.lesson.rows ?? []
            let drills: [StepTemplate]
            switch rows.count {
            case 1:
                drills = Array(repeating: .init(.rowWords, rows: rows), count: 3)
            case 2:
                drills = [.init(.rowWords, rows: [rows[0]], minShare: singleRowShare),
                          .init(.rowWords, rows: [rows[1]], minShare: singleRowShare),
                          .init(.rowWords, rows: rows)]
            default:
                // Три ряда (и испорченный урок без рядов — его отметит `CourseValidator`).
                drills = Array(repeating: .init(.rowWords, rows: rows.isEmpty ? RowName.allCases : rows), count: 3)
            }
            return drills + [.init(.phrases), .init(.focus), .init(.phrases), .init(.check)]
        case .text:
            let texts = stage >= 7 ? 3 : 2
            return [.init(.words), .init(.phrases), .init(.sentences), .init(.sentences)]
                + Array(repeating: .init(.text), count: texts) + [.init(.check)]
        case .review:
            return [.init(.drill, focus: .weakLetters), .init(.errorWords), .init(.focus, focus: .weakLetters),
                    .init(.focus, focus: .weakBigrams), .init(.errorWords), .init(.sentences), .init(.check)]
        case .speedup:
            return [.init(.words, focus: .strong), .init(.sprint, focus: .strong), .init(.sprint, focus: .strong),
                    .init(.sprint, focus: .strong), .init(.text), .init(.check)]
        case .tier:
            return [.init(.sentences), .init(.text), .init(.sprint), .init(.text), .init(.text), .init(.check)]
        case .stageCheck:
            return [.init(.words), .init(.text), .init(.check)]
        }
    }

    /// Шаблон → разрешённые шаги (решения 4–6).
    public static func resolve(_ ctx: LessonContext) -> [ResolvedStep] {
        let lengths = ctx.stage.lengths ?? StepLengths()
        let isStageCheck = ctx.lesson.resolvedKind == .stageCheck
        // Проверка этапа: check' = round(check × 1,5), разминка — round(check' / 3), средний шаг — длина text.
        let stageCheck = (Double(lengths.length(for: .check)) * 1.5).rounded()
        let stageCheckLengths = [Int((stageCheck / 3).rounded()), lengths.length(for: .text), Int(stageCheck)]

        return templates(for: ctx).enumerated().map { index, template in
            let replaced = !lengths.hasText && (template.kind == .sentences || template.kind == .text)
            let kind: ExerciseKind = replaced ? .phrases : template.kind
            let length: Int
            if let own = template.length {
                length = own
            } else if replaced {
                length = lengths.length(for: .phrases)
            } else if isStageCheck && stageCheckLengths.indices.contains(index) {
                length = stageCheckLengths[index]
            } else {
                length = lengths.length(for: kind)
            }
            let rows = template.rows ?? (kind == .rowWords ? ctx.lesson.rows ?? RowName.allCases : [])
            let minShare = template.minShare ?? (kind == .rowWords
                ? ctx.lesson.minShare ?? (rows.count == 1 ? singleRowShare : mixedRowsShare)
                : nil)
            let title = isStageCheck && index == 0 ? "Разминка" : kind.titleKey
            return ResolvedStep(kind: kind, length: length, rows: rows, minShare: minShare, focus: template.focus,
                                title: title)
        }
    }

    /// Шаг `rowWords` урока клавиш на этапах 2–3: ряд новых клавиш (первый по порядку `RowName`, где есть новая
    /// клавиша урока) и основной; новые клавиши в основном ряду (или их нет) — только основной.
    static func newKeysRows(_ ctx: LessonContext) -> [RowName] {
        let newKeys = Set(ctx.lesson.newCharacters)
        guard let row = RowName.allCases.first(where: { !(ctx.rows[$0] ?? []).isDisjoint(with: newKeys) }),
              row != .home else { return [.home] }
        return [row, .home]
    }
}
