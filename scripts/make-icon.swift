// Рисует иконку приложения (клавиша «А» с засечкой и огоньком) и собирает AppIcon.icns.
// Запуск: swift scripts/make-icon.swift <выходная папка>
import AppKit
import SwiftUI

struct AppIconView: View {
    var body: some View {
        ZStack {
            // Подложка по сетке иконок macOS: 824×824 на холсте 1024
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.64, blue: 0.47),
                                              Color(red: 0.86, green: 0.38, blue: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 10)

            keycap.offset(x: -18, y: 36)

            // Тёмная подложка огонька отделяет его от оранжевого фона
            Image(systemName: "flame.fill")
                .font(.system(size: 324, weight: .bold))
                .foregroundStyle(Color(red: 0.62, green: 0.18, blue: 0.06))
                .offset(x: 230, y: -228)

            // Светлая сердцевина: просвечивает сквозь внутренний вырез символа
            Ellipse()
                .fill(Color(red: 1.0, green: 0.93, blue: 0.62))
                .frame(width: 104, height: 150)
                .offset(x: 226, y: -186)

            Image(systemName: "flame.fill")
                .font(.system(size: 300, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.86, blue: 0.30),
                                                         Color(red: 1.0, green: 0.45, blue: 0.10)],
                                                startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(red: 0.45, green: 0.15, blue: 0.04).opacity(0.45), radius: 10, y: 6)
                .offset(x: 230, y: -235)
        }
        .frame(width: 1024, height: 1024)
    }

    private var keycap: some View {
        ZStack {
            // «Юбка» клавиши — даёт объём
            RoundedRectangle(cornerRadius: 96, style: .continuous)
                .fill(Color(red: 0.80, green: 0.62, blue: 0.52))
                .frame(width: 500, height: 500)
                .offset(y: 26)
                .shadow(color: .black.opacity(0.25), radius: 20, y: 16)
            RoundedRectangle(cornerRadius: 90, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 1.0, green: 0.97, blue: 0.94),
                                              Color(red: 0.96, green: 0.89, blue: 0.84)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 470, height: 460)
            Text("А")
                .font(.system(size: 280, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.36, green: 0.15, blue: 0.06))
                .offset(y: -18)
            Capsule()
                .fill(Color(red: 0.36, green: 0.15, blue: 0.06).opacity(0.75))
                .frame(width: 110, height: 18)
                .offset(y: 150)
        }
    }
}

@MainActor func renderPNG(size: Int, to url: URL) throws {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = CGFloat(size) / 1024
    guard let cgImage = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

@MainActor func main() throws {
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build")
let iconset = output.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    try renderPNG(size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try renderPNG(size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try renderPNG(size: 1024, to: output.appendingPathComponent("AppIcon-preview.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil завершился с кодом \(iconutil.terminationStatus)") }
print("Готово: \(output.appendingPathComponent("AppIcon.icns").path)")
}

try MainActor.assumeIsolated { try main() }
