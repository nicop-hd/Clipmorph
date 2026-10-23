import SwiftUI

/// The robot head from the site's panel preview (site/index.html, `.bot`), drawn in its 80×66 viewBox.
/// While `isBusy`, the eyes turn yellow and blink like the site's `led` animation.
struct BotHead: View {
    var isBusy = false

    var body: some View {
        if isBusy {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let dimmed = Int(context.date.timeIntervalSinceReferenceDate / 0.25) % 2 == 1
                head(pupil: Self.sun.opacity(dimmed ? 0.25 : 1))
            }
        } else {
            head(pupil: Self.cyan)
        }
    }

    private func head(pupil: Color) -> some View {
        Canvas { context, size in
            let scale = min(size.width / 80, size.height / 66)
            context.translateBy(x: (size.width - 80 * scale) / 2, y: (size.height - 66 * scale) / 2)
            context.scaleBy(x: scale, y: scale)

            let face = Path(roundedRect: CGRect(x: 2, y: 2, width: 76, height: 44), cornerRadius: 18)
            context.fill(face, with: .linearGradient(Self.chrome, startPoint: CGPoint(x: 0, y: 2), endPoint: CGPoint(x: 0, y: 46)))
            context.stroke(face, with: .color(Self.outline), lineWidth: 3)

            for x in [23.0, 57.0] {
                context.fill(Path(ellipseIn: CGRect(x: x - 14, y: 10, width: 28, height: 28)), with: .color(Self.socket))
                context.fill(Path(ellipseIn: CGRect(x: x - 8, y: 16, width: 16, height: 16)), with: .color(pupil))
            }

            context.fill(Path(CGRect(x: 28, y: 46, width: 24, height: 12)), with: .color(Self.outline))
            context.fill(Path(roundedRect: CGRect(x: 14, y: 58, width: 52, height: 6), cornerRadius: 2), with: .color(Self.pink))
        }
        .frame(width: 26, height: 22)
        .accessibilityHidden(true)
    }

    private static let outline = Color(red: 0x2B / 255, green: 0x14 / 255, blue: 0x50 / 255)
    private static let socket = Color(red: 0x12 / 255, green: 0x0A / 255, blue: 0x22 / 255)
    private static let cyan = Color(red: 0x25 / 255, green: 0xE7 / 255, blue: 0xFF / 255)
    private static let sun = Color(red: 0xFF / 255, green: 0xE3 / 255, blue: 0x8A / 255)
    private static let pink = Color(red: 0xFF / 255, green: 0x2D / 255, blue: 0x75 / 255)
    private static let chrome = Gradient(stops: [
        .init(color: .white, location: 0),
        .init(color: Color(red: 0xD8 / 255, green: 0xDE / 255, blue: 0xEA / 255), location: 0.52),
        .init(color: Color(red: 0x8E / 255, green: 0x9A / 255, blue: 0xBA / 255), location: 0.54),
        .init(color: Color(red: 0xEE / 255, green: 0xF2 / 255, blue: 0xFA / 255), location: 1),
    ])
}
