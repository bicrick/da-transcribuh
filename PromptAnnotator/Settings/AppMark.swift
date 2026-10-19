import SwiftUI

/// Menu-bar mark. The pen stays with the menu bar color; the dot turns red while recording.
struct AppMenuMark: View {
    var recording: Bool

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .frame(width: 2.4, height: 9)
                .rotationEffect(.degrees(-38))
                .offset(x: -0.5, y: 0.5)
            Circle()
                .fill(recording ? Color.red : Color.primary)
                .frame(width: 4.5, height: 4.5)
                .offset(x: 4.2, y: -4)
        }
        .frame(width: 16, height: 16)
        .foregroundStyle(.primary)
        .accessibilityLabel(recording ? "Prompt Annotator, recording" : "Prompt Annotator")
    }
}

/// The same mark, drawn large for the home page.
struct AppLogo: View {
    var side: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(Color(red: 0.91, green: 0.885, blue: 0.835))
            Capsule(style: .continuous)
                .fill(Color(red: 0.78, green: 0.16, blue: 0.14))
                .frame(width: side * 0.42, height: side * 0.075)
                .rotationEffect(.degrees(-8))
                .offset(y: side * 0.18)
            Capsule(style: .continuous)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
                .frame(width: side * 0.14, height: side * 0.40)
                .rotationEffect(.degrees(-40))
                .offset(x: -side * 0.02, y: side * 0.02)
            Circle()
                .fill(Color(red: 0.78, green: 0.16, blue: 0.14))
                .frame(width: side * 0.16, height: side * 0.16)
                .offset(x: side * 0.16, y: -side * 0.16)
        }
        .frame(width: side, height: side)
        .accessibilityLabel("Prompt Annotator")
    }
}
