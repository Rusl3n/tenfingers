import SwiftUI
import TypingCore

/// Строка карточки «План на сегодня»: значок пункта (у засчитанного — галочка), название и подпись.
struct DayPlanRow: Equatable {
    let slot: PlanSlot
    let icon: String
    let title: String
    let detail: String
    let done: Bool
}

/// Подписи пунктов плана (решение 17): название по пункту, подпись — урок, буквы, палец или источник текста.
enum DayPlanRows {
    static let doneIcon = "checkmark.circle.fill"

    static func icon(_ slot: PlanSlot) -> String {
        switch slot {
        case .warmup: "sunrise"
        case .lesson: "graduationcap"
        case .training: "target"
        case .text: "text.book.closed"
        }
    }

    /// Название пункта в карточке и на промежуточном экране.
    static func title(_ slot: PlanSlot) -> String {
        switch slot {
        case .warmup: String(localized: "Разминка")
        case .lesson: String(localized: "Новый урок")
        case .training: String(localized: "Тренировка")
        case .text: String(localized: "Текст")
        }
    }

    static func detail(_ action: PlanAction, course: Course?) -> String {
        switch action {
        case let .refresh(lessonId):
            let name = lessonTitle(lessonId, course: course)
            return String(localized: "Освежить «\(name)»")
        case let .review(focus, _):
            let letters = focus.map(String.init).joined(separator: " ")
            return letters.isEmpty ? String(localized: "Повтор") : String(localized: "Повтор: \(letters)")
        case let .lesson(lessonId, retake):
            let name = lessonTitle(lessonId, course: course)
            return retake ? String(localized: "Пересдать проверку · \(name)") : name
        case let .finger(finger, drill, _):
            let title = drill == .accuracy ? String(localized: "Точность пальца") : String(localized: "Скорость пальца")
            return "\(title) · \(finger.displayName)"
        case .adaptive:
            return String(localized: "Адаптивная тренировка")
        case let .text(stageIndex, _, _):
            guard let stageIndex, let stages = course?.stages, stages.indices.contains(stageIndex) else {
                return String(localized: "Фразы из изученных букв")
            }
            return stages[stageIndex].localizedTitle
        }
    }

    /// Строка второго возврата: «Ещё: Освежить «…»».
    static func extra(_ lessonId: String, course: Course?) -> String {
        let name = lessonTitle(lessonId, course: course)
        return String(localized: "Ещё: Освежить «\(name)»")
    }

    private static func lessonTitle(_ id: String, course: Course?) -> String {
        course?.lessons.first { $0.id == id }?.localizedTitle ?? id
    }
}

/// Данные карточки: строки, второй возврат, выполнен ли план и есть ли что запускать «Продолжить».
struct DayPlanCardModel: Equatable {
    /// Логический день плана: по нему вкладка узнаёт, что план новый (`HomeTabNews`).
    let day: String
    let rows: [DayPlanRow]
    let extra: String?
    let isDone: Bool
    let canContinue: Bool

    static func make(plan: DayPlan, course: Course?, canContinue: Bool) -> DayPlanCardModel {
        DayPlanCardModel(
            day: plan.day,
            rows: plan.items.map {
                DayPlanRow(slot: $0.slot, icon: $0.done ? DayPlanRows.doneIcon : DayPlanRows.icon($0.slot),
                           title: DayPlanRows.title($0.slot), detail: DayPlanRows.detail($0.action, course: course),
                           done: $0.done)
            },
            extra: plan.extraRefresh.map { DayPlanRows.extra($0, course: course) },
            isDone: plan.isDone, canContinue: canContinue)
    }
}

/// Содержимое вкладки «План на сегодня» (§10.1, решение 17): четыре пункта и одна кнопка «Продолжить» — первый
/// незасчитанный пункт. План выполнен — «План выполнен» вместо кнопки. Заголовок вкладки и рамка — в `HomeTabsSection`.
struct DayPlanCard: View {
    let model: DayPlanCardModel
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if model.isDone {
                    Label("План выполнен", systemImage: DayPlanRows.doneIcon)
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    Button("Продолжить", action: start)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canContinue)
                }
                Spacer()
                InfoButton(text: HelpText.dayPlan)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.rows, id: \.slot) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.icon)
                            .foregroundStyle(row.done ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                            .frame(width: 22)
                        Text(row.title).font(.headline)
                        Text(row.detail).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if let extra = model.extra {
                    Text(extra).font(.subheadline).foregroundStyle(.secondary).padding(.leading, 32)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
