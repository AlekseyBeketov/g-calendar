import AppKit
import Foundation

@main
struct AppIconGenerator {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("usage: GenerateAppIcon <iconset-directory>") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outputs: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
        ]
        for (name, size) in outputs {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            let context = NSGraphicsContext(bitmapImageRep: rep)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            drawIcon(size: CGFloat(size))
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            guard let data = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "g-calendar.icon", code: 1) }
            try data.write(to: root.appendingPathComponent(name), options: .atomic)
        }
    }

    private static func drawIcon(size: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        NSColor(calibratedRed: 0.16, green: 0.31, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.035, dy: size * 0.035), xRadius: size * 0.23, yRadius: size * 0.23).fill()

        let page = CGRect(x: size * 0.20, y: size * 0.17, width: size * 0.60, height: size * 0.66)
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: page, xRadius: size * 0.09, yRadius: size * 0.09).fill()
        let header = CGRect(x: page.minX, y: page.maxY - size * 0.20, width: page.width, height: size * 0.20)
        NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: header, xRadius: size * 0.09, yRadius: size * 0.09).fill()
        NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.82, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(x: header.minX, y: header.minY, width: header.width, height: size * 0.07)).fill()

        let dotSize = size * 0.09
        for (column, row) in [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1)] {
            let x = page.minX + size * 0.13 + CGFloat(column) * size * 0.17
            let y = page.minY + size * 0.12 + CGFloat(row) * size * 0.17
            NSColor(calibratedRed: 0.13, green: 0.55, blue: 0.45, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)).fill()
        }
    }
}
