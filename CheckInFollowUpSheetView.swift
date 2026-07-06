import SwiftUI

struct CheckInFollowUpSheetView: View {
    let checkIn: CheckIn
    let onNoIssues: () -> Void
    let onSaveNote: (String) -> Void
    let onLogIncident: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAddingNote = false
    @State private var noteText = ""

    var body: some View {
        // Uses the system drag indicator; no custom handle (which showed a second bar).
        VStack(alignment: .leading, spacing: 16) {
            header
            contextCard

            if isAddingNote {
                noteEditor
            } else {
                actionButtons
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FactTrailTheme.background(for: colorScheme).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Anything to add?")
                .font(.system(size: 20, weight: .bold, design: .default))
                .lineSpacing(2)
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            Text("Your last check-in is saved. Add a note, start an incident, or mark it complete.")
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image("codoc-location-pin")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(FactTrailTheme.aiAccent(for: colorScheme))

                VStack(alignment: .leading, spacing: 2) {
                    Text(checkIn.displayLabel)
                        .font(.system(size: 16, weight: .semibold, design: .default))
                        .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

                    Text(DateFormatter.factTrailDateTime.string(from: checkIn.createdAt))
                        .font(.system(size: 13, weight: .regular, design: .default))
                        .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
                }
            }

            let address = checkIn.address.trimmingCharacters(in: .whitespacesAndNewlines)
            if !address.isEmpty {
                Text(address)
                    .font(.system(size: 13, weight: .regular, design: .default))
                    .foregroundStyle(FactTrailTheme.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FactTrailTheme.aiSoftBackground(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FactTrailTheme.aiAccent(for: colorScheme).opacity(0.24), lineWidth: 1)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                onNoIssues()
                dismiss()
            } label: {
                Text("Nothing happened")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())

            Button {
                withAnimation(.snappy) {
                    isAddingNote = true
                }
            } label: {
                Text("Add a note")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailGlassButtonStyle())

            Button {
                onLogIncident()
                dismiss()
            } label: {
                Text("Record an event")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(FactTrailGlassButtonStyle())
        }
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add a note")
                .font(.system(size: 18, weight: .semibold, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))

            TextEditor(text: $noteText)
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundStyle(FactTrailTheme.primaryText(for: colorScheme))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(10)
                .background(FactTrailTheme.surface(for: colorScheme), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(FactTrailTheme.border(for: colorScheme), lineWidth: 1)
                }

            Button("Save note") {
                onSaveNote(noteText.trimmingCharacters(in: .whitespacesAndNewlines))
                dismiss()
            }
            .buttonStyle(FactTrailPrimaryButtonStyle())
            .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Back") {
                withAnimation(.snappy) {
                    isAddingNote = false
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(FactTrailTheme.mutedText(for: colorScheme))
            .frame(maxWidth: .infinity)
        }
    }
}
