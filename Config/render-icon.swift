import AppKit
import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let image = render(size: size)
    try writePNG(image, to: iconset.appendingPathComponent("icon_\(size).png"))
}

let contents = """
{
  "images" : [
    { "filename" : "icon_16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try contents.write(to: iconset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print(iconset.path)

func render(size: Int) -> CGImage {
    let s = CGFloat(size)
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // Terminal and Notes use the same footprint: a 824px continuous
    // rounded square on a 1024px canvas, with a 100px transparent margin.
    // Filling the canvas is what made this icon look larger than the others.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.2237
    let mask = continuousPlate(size: size, body: body, radius: radius, fill: CGColor(gray: 1, alpha: 1), border: nil)
    context.saveGState()
    context.clip(to: CGRect(x: 0, y: 0, width: s, height: s), mask: mask)
    context.translateBy(x: body.minX, y: body.minY)
    context.scaleBy(x: body.width / s, y: body.height / s)
    if let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            CGColor(srgbRed: 0.95, green: 0.93, blue: 0.89, alpha: 1),
            CGColor(srgbRed: 0.88, green: 0.85, blue: 0.79, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: s * 0.5, y: s),
            end: CGPoint(x: s * 0.5, y: 0),
            options: []
        )
    }
    context.setStrokeColor(CGColor(srgbRed: 0.78, green: 0.16, blue: 0.14, alpha: 1))
    context.setLineWidth(s * 0.078)
    context.setLineCap(.round)
    context.move(to: CGPoint(x: s * 0.22, y: s * 0.30))
    context.addQuadCurve(
        to: CGPoint(x: s * 0.78, y: s * 0.40),
        control: CGPoint(x: s * 0.48, y: s * 0.20)
    )
    context.strokePath()

    context.saveGState()
    context.translateBy(x: s * 0.46, y: s * 0.52)
    context.rotate(by: -.pi * 0.22)
    let pen = CGRect(x: -s * 0.075, y: -s * 0.22, width: s * 0.15, height: s * 0.40)
    context.addPath(CGPath(roundedRect: pen, cornerWidth: s * 0.075, cornerHeight: s * 0.075, transform: nil))
    context.setFillColor(CGColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1))
    context.fillPath()

    context.setFillColor(CGColor(srgbRed: 0.78, green: 0.16, blue: 0.14, alpha: 1))
    context.move(to: CGPoint(x: -s * 0.075, y: s * 0.15))
    context.addLine(to: CGPoint(x: s * 0.075, y: s * 0.15))
    context.addLine(to: CGPoint(x: 0, y: s * 0.30))
    context.closePath()
    context.fillPath()
    context.restoreGState()
    context.restoreGState()

    let border = continuousPlate(
        size: size,
        body: body,
        radius: radius,
        fill: nil,
        border: (max(1, body.width * 0.012), CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
    )
    context.draw(border, in: CGRect(x: 0, y: 0, width: s, height: s))
    return context.makeImage()!
}

func continuousPlate(size: Int, body: CGRect, radius: CGFloat, fill: CGColor?, border: (CGFloat, CGColor)?) -> CGImage {
    let layer = CALayer()
    layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
    layer.isGeometryFlipped = true
    let plate = CALayer()
    plate.frame = body
    plate.backgroundColor = fill ?? CGColor(gray: 0, alpha: 0)
    plate.cornerRadius = radius
    plate.cornerCurve = .continuous
    if let border {
        plate.borderWidth = border.0
        plate.borderColor = border.1
    }
    layer.addSublayer(plate)
    let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    layer.render(in: context)
    return context.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "icon", code: 2)
    }
}
