import CoreGraphics
import Foundation
import ImageIO
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

    // macOS app icons are a superellipse, not a filled square. Transparent
    // corners let the Dock draw its own shadow and the system outline.
    let shape = squircle(size: s, inset: s * 0.012)
    context.saveGState()
    context.addPath(shape)
    context.clip()
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
    let body = CGRect(x: -s * 0.075, y: -s * 0.22, width: s * 0.15, height: s * 0.40)
    context.addPath(CGPath(roundedRect: body, cornerWidth: s * 0.075, cornerHeight: s * 0.075, transform: nil))
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

    context.addPath(shape)
    context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.18))
    context.setLineWidth(max(1, s * 0.016))
    context.strokePath()

    context.saveGState()
    context.addPath(shape)
    context.clip()
    context.addPath(shape)
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55))
    context.setLineWidth(max(1, s * 0.012))
    context.strokePath()
    context.restoreGState()
    return context.makeImage()!
}

func squircle(size: CGFloat, inset: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let n: CGFloat = 5
    let radius = size / 2 - inset
    let center = size / 2
    let steps = max(96, Int(size))
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t)
        let st = sin(t)
        let point = CGPoint(
            x: center + radius * copysign(pow(abs(ct), 2 / n), ct),
            y: center + radius * copysign(pow(abs(st), 2 / n), st)
        )
        if i == 0 {
            path.move(to: point)
        } else {
            path.addLine(to: point)
        }
    }
    path.closeSubpath()
    return path
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
