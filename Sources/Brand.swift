import AppKit
import SwiftUI

enum Brand {
    static func mark() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { bounds in
            drawPocket(in: bounds, color: .black)
            return true
        }
        image.isTemplate = true
        return image
    }

    static let rose = NSColor(srgbRed: 0.68, green: 0.15, blue: 0.36, alpha: 1)

    static func drawPocket(in bounds: CGRect, color: NSColor, fill: NSColor? = nil) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
        }

        let note = NSBezierPath()
        note.move(to: point(0.29, 0.47))
        note.line(to: point(0.29, 0.81))
        note.line(to: point(0.59, 0.81))
        note.line(to: point(0.72, 0.68))
        note.line(to: point(0.72, 0.49))

        let pocket = NSBezierPath()
        pocket.move(to: point(0.15, 0.52))
        pocket.line(to: point(0.46, 0.40))
        pocket.line(to: point(0.85, 0.57))
        pocket.line(to: point(0.85, 0.28))
        pocket.curve(to: point(0.73, 0.16), controlPoint1: point(0.85, 0.21), controlPoint2: point(0.80, 0.16))
        pocket.line(to: point(0.27, 0.16))
        pocket.curve(to: point(0.15, 0.28), controlPoint1: point(0.20, 0.16), controlPoint2: point(0.15, 0.21))
        pocket.close()

        for path in [note, pocket] {
            path.lineWidth = bounds.width * 0.095
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
        }

        color.setStroke()
        note.stroke()
        if let fill {
            fill.setFill()
            pocket.fill()
        }
        pocket.stroke()
    }
}

struct BrandMark: View {
    var body: some View {
        Image(nsImage: Brand.mark())
            .resizable()
            .frame(width: 23, height: 23)
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(Color(nsColor: Brand.rose), in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }
}

struct TucknoteSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content
            .tint(dark ? Color(red: 1, green: 0.58, blue: 0.75) : Color(red: 0.66, green: 0.15, blue: 0.35))
            .background(dark ? Color(red: 0.12, green: 0.085, blue: 0.105) : Color(red: 1, green: 0.975, blue: 0.984))
    }
}
