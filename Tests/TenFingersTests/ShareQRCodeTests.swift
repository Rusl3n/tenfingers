import AppKit
import CoreImage
import Foundation
import Testing
@testable import TenFingers

/// Строки, закодированные в QR-коды картинки (распознаёт `CIDetector`).
func qrMessages(in image: CIImage) -> [String] {
    let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    return (detector?.features(in: image) ?? []).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
}

@Test func plainQRCodeIsRecognisedAndHoldsTheAppLink() throws {
    let image = try #require(ShareQRCode.plainImage())
    #expect(qrMessages(in: CIImage(cgImage: image)) == [ShareQRCode.url])
    #expect(ShareQRCode.url == "https://github.com/Rusl3n/tenfingers")
}

@Test func moduleMaskIsSquareWithOneModulePerPixel() throws {
    let mask = try #require(ShareQRCode.moduleMask())
    #expect(mask.width == mask.height)
    // Версия 1 — 21 модуль, каждая следующая на 4 больше.
    #expect(mask.width >= 21 && (mask.width - 21) % 4 == 0)
    // Без тихой зоны: во всех трёх углах сразу начинаются поисковые узоры (непрозрачные модули).
    let rep = NSBitmapImageRep(cgImage: mask)
    let last = mask.width - 1
    for (x, y) in [(0, 0), (last, 0), (0, last)] {
        #expect(try #require(rep.colorAt(x: x, y: y)).alphaComponent == 1)
    }
    // Белые модули (цвет красит `.template`).
    #expect(try #require(rep.colorAt(x: 0, y: 0)).redComponent == 1)
}

@Test func plainImageScaleIsAWholeNumberOfPixelsPerModule() throws {
    let mask = try #require(ShareQRCode.moduleMask())
    let image = try #require(ShareQRCode.plainImage(scale: 8))
    #expect(image.width == (mask.width + 8) * 8)
    #expect(image.height == image.width)
}
