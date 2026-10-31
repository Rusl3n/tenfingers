import SwiftUI
import TypingCore

/// Подписи промежуточного экрана плана (решение 16).
enum PlanInterstitial {
    /// «Пункт 2 из 4 готов · Дальше: Тренировка»; пункт брошен — «Пункт не засчитан · Дальше: …», а если он же
    /// следующий — «Пункт не засчитан · Ещё раз: …»; план выполнен — «План на сегодня выполнен».
    static func title(plan: DayPlan, finished: PlanSlot) -> String {
        guard let next = plan.next else { return String(localized: "План на сегодня выполнен") }
        let counted = plan.items.first { $0.slot == finished }?.done ?? false
        let done = plan.doneCount, total = plan.items.count
        let status = counted ? String(localized: "Пункт \(done) из \(total) готов")
                             : String(localized: "Пункт не засчитан")
        let name = DayPlanRows.title(next.slot)
        let then = next.slot == finished ? String(localized: "Ещё раз: \(name)") : String(localized: "Дальше: \(name)")
        return "\(status) · \(then)"
    }
}

/// Экран между пунктами плана: после любого выхода из запуска плана. «Продолжить» — следующий незасчитанный
/// пункт, «Хватит на сегодня» — на главную; план выполнен — только «На главную».
struct PlanInterstitialView: View {
    let plan: DayPlan
    let finished: PlanSlot
    let course: Course?
    /// Есть ли что запускать у следующего пункта (`DayPlanLoader.run`).
    let canContinue: Bool
    let onContinue: () -> Void
    let onHome: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: plan.isDone ? DayPlanRows.doneIcon : ToastCenter.planDoneIcon)
                .font(.system(size: 44))
                .foregroundStyle(plan.isDone ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
            Text(PlanInterstitial.title(plan: plan, finished: finished))
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let next = plan.next {
                Text(DayPlanRows.detail(next.action, course: course))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if plan.isDone {
                    Button("На главную", action: onHome)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Хватит на сегодня", action: onHome)
                    Button("Продолжить", action: onContinue)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
