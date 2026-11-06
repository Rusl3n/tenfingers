import AppKit
import SwiftUI

/// Знакомство из пяти шагов (пятый — «Замерить скорость сейчас?») (§1 спецификации фазы 5). Лист `RootView`, пока `onboardingCompleted` не стоит.
/// Всё введённое живёт в черновике и применяется только по «Готово»; «Пропустить» ставит один флаг.
struct OnboardingView: View {
    private static let stepCount = 5

    /// «Замерить (1 минута)»: знакомство завершено, замер открывает `RootView`.
    var onMeasure: () -> Void = {}

    @State private var step = 1
    @State private var draft = OnboardingDraft.load()

    private var isLastStep: Bool { step == Self.stepCount }

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
        case 4: language
        default: measure
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

    private var measure: some View {
        VStack(spacing: 12) {
            Image(systemName: "timer").font(.system(size: 40)).foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Замерить скорость сейчас?").font(.title2.bold())
            Text("Одна минута набора без Backspace. Этот замер станет точкой отсчёта: дальше приложение покажет, во сколько раз вы стали быстрее.")
                .foregroundStyle(.secondary)
            // Перезапуск для смены языка: замер при этом не открывается.
            if draft.needsRestart(atLaunch: InterfaceLanguage.atLaunch) {
                LanguageRestartBanner(relaunch: {
                    draft.finish()
                    AppRelauncher.relaunch()
                })
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
            } else {
                Button("Позже") { draft.finish() }
                Button("Замерить (1 минута)") {
                    // Сначала просьба о замере, потом закрытие знакомства: лист закрывается уже с ней.
                    onMeasure()
                    draft.finish()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
