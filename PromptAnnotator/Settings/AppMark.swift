import SwiftUI

/// Home / onboarding hero mark — white double-pane tile with d + inverted-t (not the Dock AppIcon).
struct AppLogo: View {
    var side: CGFloat = 72

    var body: some View {
        InkDtMark(side: side)
    }
}
