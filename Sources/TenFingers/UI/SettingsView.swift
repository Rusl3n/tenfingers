import SwiftUI
import TypingCore

/// Экран настроек: переключатель разделов сверху и содержимое выбранного раздела.
/// Пока двигается ползунок размера или сдвига, миниатюра вырастает в клавиатуру реального размера поверх экрана,
/// а после — сжимается обратно (`KeyboardMorph`).
struct SettingsView: View {
    @AppStorage(SettingsKey.settingsSection) private var sectionRaw = SettingsSection.general.rawValue
    @AppStorage(SettingsKey.keyboardUnit) private var keyboardUnit = KeyboardSizing.defaultUnit
    @AppStorage(SettingsKey.keyboardOffset) private var keyboardOffset = KeyboardSizing.defaultOffset
    @Environment(KeyboardLayoutService.self) private var layout
    @State private var preview = KeyboardPreviewState()

    private var section: SettingsSection { SettingsSection(rawValue: sectionRaw) ?? .general }
    private var wantsFullSize: Bool { preview.showsFullSize && section == .keyboard }

    var body: some View {
        VStack(spacing: 0) {
            sectionBar
            content
        }
        .overlay(alignment: .bottom) {
            if preview.isOverlayShown {
                KeyboardLivePreview(snapshot: layout.snapshot, unit: KeyboardSizing.clampedUnit(keyboardUnit),
                                    offset: keyboardOffset, miniatureFrame: preview.miniatureFrame,
                                    isPresented: wantsFullSize,
                                    // Ползунок снова схвачен во время сжатия: оверлей остаётся и растёт заново.
                                    onDismissed: { if !wantsFullSize { preview.isOverlayShown = false } })
            }
        }
        .coordinateSpace(.named(KeyboardMorph.space))
        .onChange(of: wantsFullSize) { _, show in if show { preview.isOverlayShown = true } }
        .onChange(of: sectionRaw) { preview = KeyboardPreviewState() }
        .navigationTitle("Настройки")
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general: GeneralSettingsView()
        case .learning: LearningSettingsView()
        case .keyboard: KeyboardSettingsView(preview: $preview)
        case .sounds: SoundSettingsView()
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
