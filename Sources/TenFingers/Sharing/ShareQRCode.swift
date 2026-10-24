import CoreImage
import CoreImage.CIFilterBuiltins

/// QR-код со ссылкой на страницу приложения для карточек «Поделиться».
enum ShareQRCode {
    static let url = "https://github.com/Rusl3n/tenfingers"

    /// Модули QR (`CIQRCodeGenerator`, коррекция ошибок «M»): непрозрачные белые модули на прозрачном фоне,
    /// 1 пиксель = 1 модуль, без тихой зоны (`colorInvert` → `maskToAlpha`). Красится через `.renderingMode(.template)`.
    static func moduleMask(for string: String = url) -> CGImage? {
        guard let code = code(for: string) else { return nil }
        let invert = CIFilter.colorInvert()
        invert.inputImage = code
        let mask = CIFilter.maskToAlpha()
        mask.inputImage = invert.outputImage
        guard let output = mask.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// Чёрное на белом с тихой зоной 4 модуля — для проверки распознавания в тестах.
    static func plainImage(for string: String = url, scale: Int = 8) -> CGImage? {
        guard let code = code(for: string) else { return nil }
        let quiet: CGFloat = 4
        let modules = code.extent.width
        let side = (modules + 2 * quiet) * CGFloat(scale)
        let scaled = code
            .transformed(by: CGAffineTransform(translationX: quiet - code.extent.minX, y: quiet - code.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)))
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let plain = scaled.composited(over: CIImage(color: .white).cropped(to: canvas))
        return context.createCGImage(plain, from: canvas)
    }

    private static let context = CIContext()

    /// Модули как есть (чёрные на белом, 1 пиксель на модуль), края — ближайший сосед. Генератор добавляет вокруг
    /// кода пустую рамку в 1 модуль — она срезается, чтобы тихую зону задавал только потребитель.
    private static func code(for string: String) -> CIImage? {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(string.utf8)
        generator.correctionLevel = "M"
        guard let output = generator.outputImage else { return nil }
        return output.cropped(to: output.extent.insetBy(dx: 1, dy: 1)).samplingNearest()
    }
}
