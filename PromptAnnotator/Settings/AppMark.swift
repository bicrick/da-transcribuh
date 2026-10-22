import SwiftUI

/// The shipped app icon, so the window mark cannot drift from the Dock icon.
struct AppLogo: View {
    var side: CGFloat = 72

    var body: some View {
        Image("AppMark")
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .overlay(Rectangle().strokeBorder(Ink.label, lineWidth: 1.5))
            .accessibilityLabel("da transcribuh")
    }
}
