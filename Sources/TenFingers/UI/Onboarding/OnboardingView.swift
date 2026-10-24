import AppKit
import SwiftUI

/// Знакомство из четырёх шагов (§1 спецификации фазы 5). Лист `RootView`, пока `onboardingCompleted` не стоит.
/// Всё введённое живёт в черновике и применяется только по «Готово»; «Пропустить» ставит один флаг.
struct OnboardingView: View {
    private static let stepCount = 4

    @State private var step = 1
    @State private var draft = OnboardingDraft.load()

    private var isLastStep: Bool { step == Self.stepCount }
    /// Перезапуск нужен и возможен: «Готово и перезапустить» становится кнопкой по умолчанию.
    private var restarts: Bool {
        isLastStep && AppRelauncher.canRelaunch && draft.needsRestart(atLaunch: InterfaceLanguage.atLaunch)
    }

    var body: some View {
        VStack(spacing: 16) {
            StepDotsView(current: step, total: Self.stepCount)
            content
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            buttons
        }
        .padding(24)
        .frame(width: 520, height: 400)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 1: welcome
        case 2: profile
        case 3: adult
        default: language
        }
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon).resizable().frame(width: 72, height: 72)
            }
            Text("Добро пожаловать в «Десять пальцев»").font(.title2.bold())
            VStack(spacing: 8) {
                Text("Курс шаг за шагом знакомит с клавиатурой — от основного ряда до цифр и знаков.")
                Text("Тренировка подстраивается под ваши слабые буквы, практика — свободный набор текстов.")
                Text("Занимайтесь каждый день, чтобы огонь серии не погас.")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var profile: some View {
        VStack(spacing: 12) {
            Text("Как вас подписать?").font(.title2.bold())
            VStack(spacing: 8) {
                LabeledTextField(title: "Никнейм", text: $draft.nickname, prompt: "Например, Rusl3n", labelWidth: LabeledTextField.profileLabelWidth)
                LabeledTextField(title: "Имя", text: $draft.fullName, prompt: "Ваше имя", labelWidth: LabeledTextField.profileLabelWidth)
            }
            Text("Используются на карточках «Поделиться»").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var adult: some View {
        VStack(spacing: 10) {
            Toggle("Мне есть 18", isOn: $draft.isAdult)
            Text("Включает «Взрослый юмор»: ачивки с крепким словцом. Выключение скрывает их.")
                .foregroundStyle(.secondary)
        }
    }

    private var language: some View {
        VStack(spacing: 12) {
            Text("Язык интерфейса").font(.title2.bold())
            Picker("Язык интерфейса", selection: $draft.language) {
                ForEach(InterfaceLanguage.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text("Язык курса выбирается отдельно").font(.caption).foregroundStyle(.secondary)
            // Без перезапуска предложить нечего (`swift run`): плашка только сообщает.
            if !AppRelauncher.canRelaunch, draft.needsRestart(atLaunch: InterfaceLanguage.atLaunch) {
                LanguageRestartBanner(relaunch: {})
            }
        }
    }

    private var buttons: some View {
        HStack {
            Button("Пропустить знакомство") { OnboardingDraft.skip() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if step > 1 {
                Button("Назад") { step -= 1 }
            }
            if !isLastStep {
                Button("Далее") { step += 1 }
                    .keyboardShortcut(.defaultAction)
            } else if restarts {
                Button("Готово") { draft.finish() }
                Button("Готово и перезапустить") {
                    draft.finish()
                    AppRelauncher.relaunch()
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Готово") { draft.finish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
