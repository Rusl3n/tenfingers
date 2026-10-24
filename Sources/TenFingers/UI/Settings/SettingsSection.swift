import Foundation

/// Раздел экрана настроек. `rawValue` хранится в `@AppStorage`.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, learning, keyboard, sounds

    var id: String { rawValue }

    /// Русский текст-ключ в `Localizable.strings`.
    var titleKey: String {
        switch self {
        case .general: "Общие"
        case .learning: "Обучение"
        case .keyboard: "Клавиатура"
        case .sounds: "Звуки"
        }
    }

    var title: String { Bundle.main.localizedString(forKey: titleKey, value: titleKey, table: nil) }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .learning: "graduationcap"
        case .keyboard: "keyboard"
        case .sounds: "speaker.wave.2"
        }
    }
}

/// Нужно ли показывать клавиатуру в реальном размере: пока перетаскивается хотя бы один из ползунков.
struct KeyboardPreviewState: Equatable {
    var isEditingSize = false
    var isEditingOffset = false
    /// Прямоугольник миниатюры в пространстве `KeyboardMorph.space`: отсюда вырастает клавиатура.
    var miniatureFrame: CGRect?
    /// Оверлей с клавиатурой в иерархии (растёт, показан или сжимается обратно); миниатюра при этом скрыта.
    var isOverlayShown = false

    var showsFullSize: Bool { isEditingSize || isEditingOffset }
}
