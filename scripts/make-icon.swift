import AppKit

let outputDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "Resources/AppIcon.iconset")

let canvas: CGFloat = 1024
let iconScale: CGFloat = 0.83

func makeImage(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    return rep
}

func degrees(_ value: CGFloat) -> CGFloat { value * .pi / 180 }

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

let inset = canvas * (1 - iconScale) / 2
let body = CGRect(x: inset, y: inset, width: canvas * iconScale, height: canvas * iconScale)
let radius = body.width * 0.224
let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()

let bgGradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 0.16, green: 0.23, blue: 0.32, alpha: 1),
        CGColor(srgbRed: 0.05, green: 0.09, blue: 0.14, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: body.minX, y: body.maxY),
    end: CGPoint(x: body.maxX, y: body.minY),
    options: []
)

ctx.setShadow(offset: .zero, blur: 40, color: CGColor(srgbRed: 0.2, green: 0.75, blue: 0.9, alpha: 0.25))
ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.12, blue: 0.19, alpha: 1))
ctx.addPath(bodyPath)
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)

let center = CGPoint(x: body.midX, y: body.midY + body.height * 0.05)
let ringRadius = body.width * 0.29
let ringWidth = body.width * 0.058

ctx.setLineWidth(ringWidth)
ctx.setLineCap(.round)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.13))
ctx.addArc(center: center, radius: ringRadius, startAngle: degrees(135), endAngle: degrees(-135), clockwise: true)
ctx.strokePath()

let progress: CGFloat = 0.68
let endAngle = degrees(135 - 270 * progress)
let arcGradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 0.31, green: 0.82, blue: 0.77, alpha: 1),
        CGColor(srgbRed: 0.25, green: 0.6, blue: 0.96, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.saveGState()
ctx.addArc(center: center, radius: ringRadius, startAngle: degrees(135), endAngle: endAngle, clockwise: true)
ctx.replacePathWithStrokedPath()
ctx.addPath(CGPath(rect: body.insetBy(dx: -10, dy: -10), transform: nil))
ctx.clip()
ctx.drawLinearGradient(
    arcGradient,
    start: CGPoint(x: center.x - ringRadius, y: center.y + ringRadius),
    end: CGPoint(x: center.x + ringRadius, y: center.y - ringRadius),
    options: []
)
ctx.restoreGState()

let needleLength = ringRadius - ringWidth * 0.9
let needleEnd = CGPoint(
    x: center.x + cos(endAngle) * needleLength,
    y: center.y + sin(endAngle) * needleLength
)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
ctx.setLineWidth(body.width * 0.02)
ctx.move(to: CGPoint(x: center.x - cos(endAngle) * body.width * 0.045, y: center.y - sin(endAngle) * body.width * 0.045))
ctx.addLine(to: needleEnd)
ctx.strokePath()

ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
ctx.addArc(center: center, radius: body.width * 0.032, startAngle: 0, endAngle: degrees(360), clockwise: false)
ctx.fillPath()

var tickAngle = degrees(135)
for _ in 0...9 {
    let inner = ringRadius + ringWidth * 0.45
    let outer = ringRadius + ringWidth * 0.85
    let alpha: CGFloat = tickAngle >= endAngle ? 0.55 : 0.18
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha))
    ctx.setLineWidth(body.width * 0.008)
    ctx.move(to: CGPoint(x: center.x + cos(tickAngle) * inner, y: center.y + sin(tickAngle) * inner))
    ctx.addLine(to: CGPoint(x: center.x + cos(tickAngle) * outer, y: center.y + sin(tickAngle) * outer))
    ctx.strokePath()
    tickAngle -= degrees(270.0 / 9)
}

let dotY = body.minY + body.height * 0.16
let dotOffset = body.width * 0.16
let dotColors: [(CGFloat, CGFloat, CGFloat)] = [
    (0.2, 0.83, 0.6),
    (0.98, 0.75, 0.14),
    (0.42, 0.47, 0.55)
]
for (index, rgb) in dotColors.enumerated() {
    let x = center.x + (CGFloat(index) - 1) * dotOffset
    let color = CGColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    ctx.setShadow(offset: .zero, blur: 18, color: color.copy(alpha: 0.6))
    ctx.setFillColor(color)
    ctx.addArc(center: CGPoint(x: x, y: dotY), radius: body.width * 0.026, startAngle: 0, endAngle: degrees(360), clockwise: false)
    ctx.fillPath()
}
ctx.setShadow(offset: .zero, blur: 0, color: nil)

ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08))
ctx.addPath(bodyPath)
ctx.clip()
let gloss = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.35),
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
    ] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    gloss,
    start: CGPoint(x: body.midX, y: body.maxY),
    end: CGPoint(x: body.midX, y: body.maxY - body.height * 0.45),
    options: []
)

ctx.restoreGState()
image.unlockFocus()

try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in sizes {
    let rep = makeImage(pixels: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: outputDir.appendingPathComponent(name))
}

print("iconset -> \(outputDir.path)")
