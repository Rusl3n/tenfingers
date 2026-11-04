// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "TenFingers",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "TenFingers", targets: ["TenFingers"])],
    targets: [
        .target(name: "TypingCore", resources: [.process("Resources")]),
        // Модель widget.json: только Foundation, её читают приложение и виджет
        .target(name: "WidgetSnapshot"),
        .executableTarget(name: "TenFingers", dependencies: ["TypingCore", "WidgetSnapshot"]),
        // Расширение WidgetKit: make-bundle.sh кладёт его в TenFingers.app/Contents/PlugIns/TenFingersWidget.appex
        .executableTarget(
            name: "TenFingersWidget", dependencies: ["WidgetSnapshot"], resources: [.process("Resources")],
            // Точка входа расширения — _NSExtensionMain, как у системных виджетов: с обычной main процесс сразу выходит
            // и галерея не получает описание виджета (проверено на пробной установке 7c)
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]
        ),
        .testTarget(name: "TypingCoreTests", dependencies: ["TypingCore"]),
        .testTarget(name: "TenFingersTests", dependencies: ["TenFingers", "TenFingersWidget", "TypingCore", "WidgetSnapshot"]),
    ]
)
