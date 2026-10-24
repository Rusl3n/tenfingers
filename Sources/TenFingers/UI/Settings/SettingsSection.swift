import Foundation
import Observation

/// Раздел экрана настроек. `rawValue` хранится в `@AppStorage`.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, learning, keyboard, sounds, reminders, profile, data

    var id: String { rawValue }

    /// Русский текст-ключ в `Localizable.strings`.
    var titleKey: String {
        switch self {
        case .general: "Общие"
        case .learning: "Обучение"
        case .keyboard: "Клавиатура"
        case .sounds: "Звуки"
        case .reminders: "Напоминания"
        case .profile: "Профиль"
        case .data: "Данные"
        }
    }

    var title: String { Bundle.main.localizedString(forKey: titleKey, value: titleKey, table: nil) }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .learning: "graduationcap"
        case .keyboard: "keyboard"
        case .sounds: "speaker.wave.2"
        case .reminders: "bell"
        case .profile: "person.crop.circle"
        case .data: "externaldrive"
        }
    }
}

/// Нужно ли показывать клавиатуру в реальном размере: пока перетаскивается хотя бы один из ползунков.
struct KeyboardPreviewState: Equatable {
    var isEditingSize = false
    var isEditingOffset = false
    /// Оверлей с клавиатурой в иерархии (растёт, показан или сжимается обратно); миниатюра при этом скрыта.
    var isOverlayShown = false

    var showsFullSize: Bool { isEditingSize || isEditingOffset }
}

/// Прямоугольник миниатюры клавиатуры в пространстве `KeyboardMorph.space`: отсюда вырастает клавиатура.
/// Отдельный наблюдаемый объект, а не поле `KeyboardPreviewState`: прямоугольник меняется на каждом шаге ползунка
/// размера, и запись в состояние экрана пересчитывала бы весь экран настроек вместе с формой раздела.
/// Так его читает только оверлей с клавиатурой.
@MainActor @Observable
final class KeyboardMiniatureFrame {
    var rect: CGRect?
}
