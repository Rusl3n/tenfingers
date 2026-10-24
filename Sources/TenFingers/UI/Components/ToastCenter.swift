import Observation
import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let icon: String
    let message: String
    let tint: Color
}

/// Откладывает действие на `duration`; возвращает отмену. В тестах подменяется ручным таймером.
typealias ToastTimer = @MainActor (Duration, @escaping @MainActor () -> Void) -> @MainActor () -> Void

/// Всплывающее сообщение сверху окна: одно за раз, исчезает само. Лежит в environment.
@MainActor @Observable
final class ToastCenter {
    private(set) var current: Toast?
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private let timer: ToastTimer
    @ObservationIgnored private var cancelDismiss: (@MainActor () -> Void)?

    init(duration: Duration = .seconds(3), timer: @escaping ToastTimer = ToastCenter.sleepingTimer) {
        self.duration = duration
        self.timer = timer
    }

    /// Таймер приложения: `Task.sleep`.
    static let sleepingTimer: ToastTimer = { duration, action in
        let task = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }

    func show(_ toast: Toast) {
        cancelDismiss?()
        current = toast
        let id = toast.id
        cancelDismiss = timer(duration) { [weak self] in self?.dismiss(id: id) }
    }

    /// День впервые стал «полным огнём».
    func showFullFlame() {
        show(Toast(icon: "flame.fill", message: String(localized: "Полный огонь! Дневная цель выполнена"), tint: .orange))
    }

    func dismiss(id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        cancelDismiss?()
        cancelDismiss = nil
        current = nil
    }
}

/// Показывает текущее сообщение `ToastCenter` по верхнему краю; клики проходят сквозь него.
struct ToastOverlay: View {
    let toasts: ToastCenter
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            if let toast = toasts.current {
                HStack(spacing: 10) {
                    Image(systemName: toast.icon).font(.title3).foregroundStyle(toast.tint)
                    Text(toast.message).font(.headline)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(palette.card, in: Capsule())
                .overlay(Capsule().stroke(toast.tint.opacity(0.5)))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.35), value: toasts.current)
        .allowsHitTesting(false)
    }
}
