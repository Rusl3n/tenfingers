import SwiftUI
import TypingCore

/// Экран настроек: переключатель разделов сверху и содержимое выбранного раздела.
/// Пока двигается ползунок размера или сдвига, миниатюра вырастает в клавиатуру реального размера поверх экрана,
/// а после — сжимается обратно (`KeyboardMorph`).
struct SettingsView: View {
    @AppStorage(SettingsKey.settingsSection) private var sectionRaw = SettingsSection.general.rawValue
    @State private var preview = KeyboardPreviewState()
    @State private var miniature = KeyboardMiniatureFrame()

    private var section: SettingsSection { SettingsSection(rawValue: sectionRaw) ?? .general }
    private var wantsFullSize: Bool { preview.showsFullSize && section == .keyboard }

    var body: some View {
        VStack(spacing: 0) {
            sectionBar
            content
            Text(AppVersion.settingsLine(info: AppVersion.current))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.vertical, 6)
        }
        .overlay(alignment: .bottom) {
            if preview.isOverlayShown {
                KeyboardPreviewOverlay(miniature: miniature, isPresented: wantsFullSize,
                                       // Ползунок снова схвачен во время сжатия: оверлей остаётся и растёт заново.
                                       onDismissed: { if !wantsFullSize { preview.isOverlayShown = false } })
            }
        }
        .coordinateSpace(.named(KeyboardMorph.space))
        .onChange(of: wantsFullSize) { _, show in if show { preview.isOverlayShown = true } }
        // Прямоугольник миниатюры не сбрасываем: раздел «Клавиатура» меряет его заново, как только появляется.
        .onChange(of: sectionRaw) { preview = KeyboardPreviewState() }
        .navigationTitle("Настройки")
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general: GeneralSettingsView()
        case .learning: LearningSettingsView()
        case .keyboard: KeyboardSettingsView(preview: $preview, miniature: miniature)
        case .sounds: SoundSettingsView()
        case .reminders: ReminderSettingsView()
        case .profile: ProfileSettingsView()
        case .data: DataSettingsView()
        }
    }

    private var sectionBar: some View {
        HStack(spacing: 6) {
            ForEach(SettingsSection.allCases) { item in
                Button { sectionRaw = item.rawValue } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon).font(.system(size: 18))
                        Text(item.title).font(.caption)
                    }
                    .frame(minWidth: 72)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(item == section ? Color.accentColor.opacity(0.18) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .foregroundStyle(item == section ? Color.accentColor : Color.secondary)
                .accessibilityAddTraits(item == section ? .isSelected : [])
            }
        }
        .padding(.top, 12)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

/// Оверлей с клавиатурой реального размера. Размер, сдвиг и прямоугольник миниатюры читает сам: шаг ползунка
/// пересчитывает только его, а не весь экран настроек с панелью разделов.
private struct KeyboardPreviewOverlay: View {
    let miniature: KeyboardMiniatureFrame
    let isPresented: Bool
    let onDismissed: () -> Void
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @Environment(KeyboardLayoutService.self) private var layout

    var body: some View {
        KeyboardLivePreview(snapshot: layout.snapshot, unit: KeyboardSizing.clampedUnit(keyboardUnit),
                            offset: keyboardOffset, miniatureFrame: miniature.rect, isPresented: isPresented,
                            onDismissed: onDismissed)
    }
}
