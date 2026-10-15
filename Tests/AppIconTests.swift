import Foundation
import CoreGraphics
import ImageIO

// Compare native ICNS-decoded representations with the approved raster master.
// Checking only the largest embedded PNG misses malformed legacy 16/32px data.
func loadImage(_ path: String) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw NSError(domain: "AppIconTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Cannot decode \(path)"])
    }
    return image
}

func pixels(_ image: CGImage, size: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                    CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    }
    return bytes
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw NSError(domain: "AppIconTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Expected master PNG and native-decoded iconset"])
    }
    let master = try loadImage(CommandLine.arguments[1])
    guard master.width == 1024, master.height == 1024 else {
        fatalError("Approved icon master must be 1024×1024")
    }
    for base in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
            let decoded = try loadImage(CommandLine.arguments[2] + "/" + filename)
            let size = base * scale
            guard decoded.width == size, decoded.height == size else {
                fatalError("Wrong dimensions: \(filename)")
            }
            let expected = pixels(master, size: size)
            let actual = pixels(decoded, size: size)
            let error = zip(expected, actual).reduce(0.0) { $0 + Double(abs(Int($1.0) - Int($1.1))) }
                / Double(expected.count)
            // Native legacy encodings quantize small representations. Corrupt PNG
            // payloads in legacy ICNS chunks exceed this bound by a wide margin.
            guard error < 25 else {
                throw NSError(domain: "AppIconTests", code: 3,
                              userInfo: [NSLocalizedDescriptionKey:
                                "Corrupt icon representation \(filename): mean channel error \(error)"])
            }
            print("PASS \(filename) native roundtrip error=\(String(format: "%.2f", error))")
        }
    }
} catch {
    fputs("FAIL \(error.localizedDescription)\n", stderr)
    exit(1)
}
