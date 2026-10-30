// Renders the DMG window background in the app's Ink / MS Paint style.
//
//   swift Config/dmg/render-background.swift Config/dmg
//
// Writes background.png (600x400), background@2x.png (1200x800) and
// background.tiff (both, for Retina). Layout matches scripts/release.sh:
// app icon centered at (150, 190), Applications at (450, 190), icon size 128.
// Each card holds an icon and its Finder label.
import AppKit
import CoreText
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Config/dmg")
let root = outDir.deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appendingPathComponent("PromptAnnotator/Fonts/DepartureMono-Regular.otf")
CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)

let W: CGFloat = 600, H: CGFloat = 400
let black = CGColor(gray: 0, alpha: 1)
let paper = CGColor(gray: 1, alpha: 1)
let grey = CGColor(red: 0x66 / 255, green: 0x66 / 255, blue: 0x66 / 255, alpha: 1)
let fill = CGColor(red: 0xF0 / 255, green: 0xF0 / 255, blue: 0xF0 / 255, alpha: 1)

func font(_ size: CGFloat) -> CTFont {
    CTFontCreateWithName("DepartureMono-Regular" as CFString, size, nil)
}

func render(scale: CGFloat) -> CGImage {
    let ctx = CGContext(
        data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.scaleBy(x: scale, y: scale)
    // Top-left origin, like Finder's icon coordinates.
    ctx.translateBy(x: 0, y: H)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setShouldAntialias(false)
    ctx.interpolationQuality = .none

    ctx.setFillColor(paper)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // Two Ink cards with the hard 3pt bevel, one behind each icon.
    for cx in [150.0, 450.0] as [CGFloat] {
        let card = CGRect(x: cx - 84, y: 92, width: 168, height: 204)
        ctx.setFillColor(black)
        ctx.fill(card.offsetBy(dx: 3, dy: 3))
        ctx.setFillColor(cx == 150 ? paper : fill)
        ctx.fill(card)
        ctx.setStrokeColor(black)
        ctx.setLineWidth(2)
        ctx.stroke(card.insetBy(dx: 1, dy: 1))
    }

    // Pixel arrow on a 6pt grid between the cards, with the same bevel.
    let u: CGFloat = 6, cy: CGFloat = 190
    var blocks: [CGRect] = [CGRect(x: 252, y: cy - u, width: 66, height: 2 * u)]
    for i in 0..<5 {
        let half = CGFloat(5 - i) * u
        blocks.append(CGRect(x: 318 + CGFloat(i) * u, y: cy - half, width: u, height: 2 * half))
    }
    ctx.setFillColor(grey)
    for b in blocks { ctx.fill(b.offsetBy(dx: 3, dy: 3)) }
    ctx.setFillColor(black)
    for b in blocks { ctx.fill(b) }

    ctx.setShouldAntialias(true)
    text("drag me into Applications", size: 22, color: black, centerX: W / 2, baseline: 60, in: ctx)
    text("da transcribuh", size: 12, color: grey, centerX: W / 2, baseline: 350, in: ctx)
    return ctx.makeImage()!
}

func text(_ s: String, size: CGFloat, color: CGColor, centerX: CGFloat, baseline: CGFloat, in ctx: CGContext) {
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font(size),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: centerX - CGFloat(width) / 2, y: baseline)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func writePNG(_ image: CGImage, _ name: String, dpi: CGFloat) throws {
    let url = outDir.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "png", code: 1) }
    print(url.path)
}

try writePNG(render(scale: 1), "background.png", dpi: 72)
try writePNG(render(scale: 2), "background@2x.png", dpi: 144)
