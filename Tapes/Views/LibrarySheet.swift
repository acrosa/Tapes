import SwiftUI
import GridKit

/// The shelf of tapes, plus the few preferences the app has.
struct LibrarySheet: View {
    @Environment(Recorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("theme") private var storedTheme = ""
    @AppStorage("haptics") private var haptics = true
    @AppStorage("showsGrid") private var showsGrid = false
    @State private var renaming: TapeMeta?
    @State private var newName = ""

    var body: some View {
        let theme = Theme.resolve(stored: storedTheme, system: systemScheme)
        let _ = Palette.current = theme.colors
        NavigationStack {
            List {
                Section {
                    ForEach(recorder.tapes) { tape in
                        Button {
                            recorder.open(tape)
                            dismiss()
                        } label: {
                            row(tape)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            if tape.id != recorder.tape.id {
                                Button("Delete", role: .destructive) { recorder.delete(tape.id) }
                            }
                            Button("Rename") {
                                newName = tape.name
                                renaming = tape
                            }
                        }
                    }
                }
                .listRowBackground(Palette.key)
                Section {
                    HStack(spacing: Rhythm.u(3)) {
                        ForEach(Theme.allCases) { option in
                            ThemeTile(theme: option, selected: option == theme) {
                                storedTheme = option.rawValue
                            }
                        }
                    }
                    .padding(.vertical, Rhythm.u(1))
                    .listRowInsets(EdgeInsets(top: Rhythm.u(2), leading: Rhythm.u(4), bottom: Rhythm.u(2), trailing: Rhythm.u(4)))
                } header: {
                    header("Finish")
                }
                .listRowBackground(Palette.key)
                Section {
                    let _ = recorder.routeRevision
                    if recorder.inputs.isEmpty {
                        Button("Choose an input…") { recorder.prepareInputs() }
                    } else {
                        Picker("Input", selection: Binding(get: { recorder.inputChoice }, set: { recorder.inputChoice = $0 })) {
                            Text("Automatic").tag("")
                            ForEach(recorder.inputs) { Text($0.name).tag($0.id) }
                        }
                    }
                    Toggle("Hear the input", isOn: Binding(get: { recorder.hearsInput }, set: { recorder.hearsInput = $0 }))
                } header: {
                    header("Sound")
                } footer: {
                    Text(soundNote)
                        .foregroundStyle(Palette.legend)
                }
                .listRowBackground(Palette.key)
                Section {
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Show layout grid", isOn: $showsGrid)
                } header: {
                    header("Preferences")
                }
                .listRowBackground(Palette.key)
            }
            // Rows are raised parts: key colour with ink on them. Headers are print on the faceplate.
            .foregroundStyle(Palette.ink)
            .tint(Palette.lamp)
            .scrollContentBackground(.hidden)
            .background(Palette.surface)
            .navigationTitle("Tapes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The sheet keeps its name for VoiceOver, but prints no title: the tapes speak for themselves.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
                ToolbarItem(placement: .topBarLeading) {
                    Button("New tape", systemImage: "plus") {
                        recorder.newTape()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename tape", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Rename") {
                    if let renaming { recorder.rename(renaming.id, to: newName) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(storedTheme.isEmpty ? nil : theme.scheme)
    }

    /// What is connected now, and what happens when something is plugged in.
    private var soundNote: String {
        var lines: [String] = []
        if let input = recorder.inputName, let output = recorder.outputName {
            lines.append("Now: recording from \(input), playing through \(output).")
        } else if let output = recorder.outputName {
            lines.append("Now: playing through \(output).")
        }
        lines.append("With nothing plugged in, Tapes records the built-in microphone and plays through the speaker.")
        lines.append("Plug in an instrument and Tapes records that instead. You hear it live, through this device or your headphones. While the tape plays, you hear the tape.")
        lines.append("Turn Hear the input off for a microphone that sits near the speaker.")
        return lines.joined(separator: "\n")
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Palette.legend)
    }

    private func row(_ tape: TapeMeta) -> some View {
        HStack(spacing: Rhythm.u(3)) {
            Lamp(on: tape.id == recorder.tape.id)
            VStack(alignment: .leading, spacing: 0) {
                Text(tape.name)
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                Text(tape.modified, format: .dateTime.day().month().hour().minute())
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            Text(tape.duration > 0 ? DisplayView.counter(tape.duration) : "empty")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Palette.inkSecondary)
        }
        .padding(.vertical, Rhythm.u(1))
    }
}

/// A finish shown as a small piece of the appliance in that finish: its faceplate, display
/// window, a key with a lit lamp, and the record dot. The chosen one has a ring around it.
private struct ThemeTile: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let colors = theme.colors
        Button(action: action) {
            VStack(spacing: Rhythm.u(2)) {
                VStack(spacing: Rhythm.u(2)) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(colors.glass)
                        .frame(height: Rhythm.u(5))
                        .overlay(alignment: .leading) {
                            Capsule().fill(colors.displayInk).frame(width: Rhythm.u(6), height: 3).padding(.leading, Rhythm.u(2))
                        }
                    HStack(spacing: Rhythm.u(2)) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colors.key)
                            .shadow(color: .black.opacity(colors.lift), radius: 1.5, y: 1)
                            .overlay { Circle().fill(colors.lamp).frame(width: 6, height: 6) }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colors.key)
                            .shadow(color: .black.opacity(colors.lift), radius: 1.5, y: 1)
                            .overlay { Circle().fill(colors.signal).frame(width: 10, height: 10) }
                    }
                    .frame(height: Rhythm.u(7))
                }
                .padding(Rhythm.u(2))
                .background(colors.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 0.5)
                }
                .padding(3)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(selected ? Palette.ink : .clear, lineWidth: 1.5)
                }
                Text(theme.name)
                    .font(.footnote)
                    .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) finish")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The system share sheet for an exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
