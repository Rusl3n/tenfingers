import SwiftUI

extension View {
    /// Алерт «Не удалось сохранить результат» с «Повторить» и «Отмена».
    func saveErrorAlert(_ coordinator: ExerciseCoordinator) -> some View {
        @Bindable var coordinator = coordinator
        return alert("Не удалось сохранить результат", isPresented: $coordinator.showSaveError) {
            Button("Повторить") { coordinator.retrySave() }
            Button("Отмена", role: .cancel) { coordinator.cancelSave() }
        } message: {
            Text(coordinator.saveError ?? "")
        }
    }
}
