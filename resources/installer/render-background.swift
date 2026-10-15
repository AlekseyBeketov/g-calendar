import AppKit

// Editable vector source for the approved Finder design. Coordinates are points;
// the TIFF stores a 2x representation with a 640 x 420 point logical size.
let size = CGSize(width: 640, height: 420)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: 1280, height: 840, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.scaleBy(x: 2, y: 2)
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
let colors = [color(0.94, 0.975, 1), color(1, 1, 1), color(0.87, 0.94, 1)] as CFArray
let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.48, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 540, y: 0), end: CGPoint(x: 140, y: 420),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

let lowerWave = CGMutablePath()
lowerWave.move(to: CGPoint(x: 0, y: 190))
lowerWave.addCurve(to: CGPoint(x: 640, y: 420), control1: CGPoint(x: 160, y: 250), control2: CGPoint(x: 260, y: 360))
lowerWave.addLine(to: CGPoint(x: 0, y: 420))
lowerWave.closeSubpath()
context.setFillColor(color(0.69, 0.84, 1, 0.31))
context.addPath(lowerWave)
context.fillPath()

let upperWave = CGMutablePath()
upperWave.move(to: CGPoint(x: 465, y: 0))
upperWave.addCurve(to: CGPoint(x: 640, y: 108), control1: CGPoint(x: 530, y: 20), control2: CGPoint(x: 535, y: 90))
upperWave.addLine(to: CGPoint(x: 640, y: 0))
upperWave.closeSubpath()
context.setFillColor(color(0.69, 0.84, 1, 0.26))
context.addPath(upperWave)
context.fillPath()

// Only decoration is baked in. Finder supplies the real draggable app/folder icons.
context.setStrokeColor(color(0.62, 0.69, 0.78))
context.setLineWidth(8)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: 294, y: 150))
context.addLine(to: CGPoint(x: 345, y: 150))
context.strokePath()
context.move(to: CGPoint(x: 332, y: 136))
context.addLine(to: CGPoint(x: 347, y: 150))
context.addLine(to: CGPoint(x: 332, y: 164))
context.strokePath()

let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
bitmap.size = NSSize(width: size.width, height: size.height)
let destination = URL(fileURLWithPath: CommandLine.arguments[1])
// TIFF compression tag 5 is lossless LZW; retain Retina size and the opaque alpha.
try bitmap.representation(using: .tiff, properties: [.compressionMethod: NSNumber(value: 5)])!.write(to: destination)
print("INSTALLER_BACKGROUND=\(destination.path)")
