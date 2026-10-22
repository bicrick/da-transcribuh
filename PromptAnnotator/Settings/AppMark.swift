import SwiftUI

/// Home / onboarding hero mark — square dt with Paint shadow (not the Dock AppIcon).
struct AppLogo: View {
    var side: CGFloat = 72

    var body: some View {
        InkDtMark(side: side, shadow: Ink.paintRed)
    }
}
