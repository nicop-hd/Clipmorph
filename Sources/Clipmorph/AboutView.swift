import SwiftUI

struct AboutView: View {
    // Matches the night-sky background of AboutHeader.png so the header blends into the window.
    private static let background = Color(red: 0x12 / 255, green: 0x0A / 255, blue: 0x22 / 255)
    private static let width: CGFloat = 520

    private var version: String {
        "Version \(UpdateService.currentVersion)"
    }

    var body: some View {
        VStack(spacing: 0) {
            if let url = Bundle.main.url(forResource: "AboutHeader", withExtension: "png"),
               let header = NSImage(contentsOf: url), header.size.width > 0 {
                // Fixed height: the window sizes to the content's minimum, which would collapse a flexible image.
                Image(nsImage: header)
                    .resizable()
                    .frame(width: Self.width, height: Self.width * header.size.height / header.size.width)
            }
            VStack(spacing: 6) {
                Text(version)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("Built by Nico P.")
                    .font(.callout)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .frame(width: Self.width)
        .background(Self.background)
        .environment(\.colorScheme, .dark)
    }
}
