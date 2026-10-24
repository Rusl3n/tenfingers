import AppKit
import SwiftUI

/// PNG карточки: `ImageRenderer` с масштабом 2 (2400×1260, 2160×2160 или 2160×3840); у прозрачного фона — альфа-канал.
@MainActor
enum ShareCardRenderer {
    enum Failure: Error {
        case render, encode
    }

    /// `scale` 1 — для картинок README (градиенты в PNG тяжёлые).
    static func png(_ view: ShareCardView, scale: CGFloat = 2) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = view.options.background != .transparent
        guard let cgImage = renderer.cgImage else { throw Failure.render }
        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw Failure.encode
        }
        return data
    }
}
