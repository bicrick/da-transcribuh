import SwiftUI

struct DonePanelView: View {
    @ObservedObject var session: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Session saved")
                    .font(.headline)
                Spacer(minLength: 12)
                Button {
                    session.dismissDone()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            Text(session.doneSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let confirmation = session.copyConfirmation {
                Text(confirmation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = session.transcriptionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Copy notes") { session.copyNotes() }
                Button("Copy tile sheet") { session.copySheet() }
                    .disabled(!session.hasSheet)
                Button("Show in Finder") { session.revealSession() }
            }
        }
        .padding(16)
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
