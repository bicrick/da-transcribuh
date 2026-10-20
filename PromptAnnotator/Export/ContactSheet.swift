import AppKit
import CoreText

struct SheetMetrics: Equatable {
    var targetWidth: CGFloat = 1280
    var captionHeight: CGFloat = 56
    var spacing: CGFloat = 28
    var margin: CGFloat = 36
    /// Keeps the number and clock readable when a snippet is narrower than the caption.
    var minimumCaptionWidth: CGFloat = 180

    static let standard = SheetMetrics()
}

struct SheetLayout: Equatable {
    struct Tile: Equatable {
        var index: Int
        var captionRect: CGRect
        var imageRect: CGRect
    }

    var tiles: [Tile]
    var canvasSize: CGSize

    static func make(imageSizes: [CGSize], metrics: SheetMetrics = .standard) -> SheetLayout {
        guard !imageSizes.isEmpty else {
            return SheetLayout(tiles: [], canvasSize: .zero)
        }

        let fitted = imageSizes.map { fittedSize(for: $0, maxWidth: metrics.targetWidth) }
        let contentWidth = fitted
            .map { max($0.width, metrics.minimumCaptionWidth) }
            .max() ?? 0

        var tiles: [Tile] = []
        var y = metrics.margin
        for (offset, size) in fitted.enumerated() {
            let captionWidth = max(size.width, metrics.minimumCaptionWidth)
            let caption = CGRect(
                x: metrics.margin,
                y: y,
                width: captionWidth,
                height: metrics.captionHeight
            )
            let image = CGRect(
                x: metrics.margin,
                y: caption.maxY,
                width: size.width,
                height: size.height
            )
            tiles.append(Tile(index: offset + 1, captionRect: caption, imageRect: image))
            y = image.maxY + metrics.spacing
        }
        y -= metrics.spacing
        y += metrics.margin

        return SheetLayout(
            tiles: tiles,
            canvasSize: CGSize(width: metrics.margin * 2 + contentWidth, height: y)
        )
    }

    /// Scales a frame down to `maxWidth`. A narrower snippet keeps its capture size.
    static func fittedSize(for source: CGSize, maxWidth: CGFloat) -> CGSize {
        guard source.width > 0 else {
            return CGSize(width: maxWidth, height: 0)
        }
        let width = min(source.width, maxWidth)
        let scale = width / source.width
        return CGSize(width: width.rounded(), height: (source.height * scale).rounded())
    }

    /// Converts a top-left rect into Core Graphics' bottom-left space.
    static func flipped(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: canvasHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

enum ContactSheet {
    static func render(
        images: [CGImage],
        commitOffsets: [TimeInterval],
        metrics: SheetMetrics = .standard
    ) -> CGImage? {
        let sizes = images.map { CGSize(width: $0.width, height: $0.height) }
        let layout = SheetLayout.make(imageSizes: sizes, metrics: metrics)
        guard layout.canvasSize.width > 0, layout.canvasSize.height > 0 else { return nil }

        let width = Int(layout.canvasSize.width.rounded())
        let height = Int(layout.canvasSize.height.rounded())
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let canvasHeight = CGFloat(height)
        context.setFillColor(NSColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        for (tile, image) in zip(layout.tiles, images) {
            let caption = SheetLayout.flipped(tile.captionRect, canvasHeight: canvasHeight)
            let imageRect = SheetLayout.flipped(tile.imageRect, canvasHeight: canvasHeight)

            context.setFillColor(NSColor.white.cgColor)
            context.fill(caption)
            context.draw(image, in: imageRect)
            drawCaption(
                index: tile.index,
                offset: commitOffsets.indices.contains(tile.index - 1) ? commitOffsets[tile.index - 1] : 0,
                in: caption,
                context: context
            )
        }

        NSGraphicsContext.current = previous
        return context.makeImage()
    }

    private static func drawCaption(index: Int, offset: TimeInterval, in caption: CGRect, context: CGContext) {
        let circle = CGRect(x: caption.minX + 16, y: caption.midY - 16, width: 32, height: 32)
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: circle)

        let number = NSAttributedString(
            string: "\(index)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
        )
        let numberSize = number.size()
        number.draw(at: CGPoint(
            x: circle.midX - numberSize.width / 2,
            y: circle.midY - numberSize.height / 2
        ))

        let time = NSAttributedString(
            string: TimeFormat.clock(offset),
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 20, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
        )
        let timeSize = time.size()
        time.draw(at: CGPoint(
            x: circle.maxX + 14,
            y: caption.midY - timeSize.height / 2
        ))
    }
}
