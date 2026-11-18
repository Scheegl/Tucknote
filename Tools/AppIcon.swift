import AppKit

@main
enum AppIcon {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        var images = Data()
        for (size, type) in [(16, "icp4"), (32, "icp5"), (64, "icp6"), (128, "ic07"),
                             (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
            let pixels = CGFloat(size)
            let image = NSImage(size: CGSize(width: pixels, height: pixels), flipped: false) { bounds in
                let tile = bounds.insetBy(dx: pixels * 0.08, dy: pixels * 0.08)
                Brand.rose.setFill()
                NSBezierPath(roundedRect: tile, xRadius: pixels * 0.20, yRadius: pixels * 0.20).fill()
                Brand.drawPocket(
                    in: bounds.insetBy(dx: pixels * 0.15, dy: pixels * 0.15),
                    color: NSColor(srgbRed: 1, green: 0.95, blue: 0.97, alpha: 1),
                    fill: NSColor(srgbRed: 0.83, green: 0.33, blue: 0.53, alpha: 1)
                )
                return true
            }
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            image.draw(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            let data = bitmap.representation(using: .png, properties: [:])!
            appendChunk(type, contents: data, to: &images)
        }
        var file = Data()
        appendChunk("icns", contents: images, to: &file)
        try file.write(to: output)
    }

    private static func appendChunk(_ type: String, contents: Data, to output: inout Data) {
        output.append(contentsOf: type.utf8)
        var length = UInt32(contents.count + 8).bigEndian
        withUnsafeBytes(of: &length) { output.append(contentsOf: $0) }
        output.append(contents)
    }
}
