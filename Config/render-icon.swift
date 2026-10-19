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
    context.setFillColor(CGColor(srgbRed: 0.91, green: 0.885, blue: 0.835, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: s, height: s))

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
