import SwiftUI
import UniformTypeIdentifiers
import KadoCore

/// Settings section for the automatic backup: a toggle, the folder it
/// writes into (picked once in Files, usually in iCloud Drive), and how
/// the last run went. The writing itself happens when the app goes to
/// the background (`KadoApp`), through `AutoExportRunner`.
struct AutoExportSection: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage(AutoExportDefaults.enabledKey) private var isEnabled = false
    @AppStorage(AutoExportDefaults.folderNameKey) private var folderName = ""
    @AppStorage(AutoExportDefaults.lastRunKey) private var lastRunAt: Double = 0
    @AppStorage(AutoExportDefaults.lastErrorKey) private var lastError = ""

    @State private var isPickingFolder = false

    var body: some View {
        Section {
            Toggle("Back up automatically", isOn: $isEnabled)
            if isEnabled {
                Button {
                    isPickingFolder = true
                } label: {
                    LabeledContent(
                        String(localized: "Folder"),
                        value: folderName.isEmpty ? String(localized: "Choose…") : folderName
                    )
                }
                Button("Back up now") {
                    AutoExportRunner.run(using: modelContext)
                }
                .disabled(folderName.isEmpty)
            }
        } header: {
            Text("Automatic backup")
                .foregroundStyle(Color.kadoForegroundSecondary)
        } footer: {
            footer
        }
        .listRowBackground(Color.kadoBackgroundSecondary)
        .onChange(of: isEnabled) { _, enabled in
            if enabled && folderName.isEmpty {
                isPickingFolder = true
            }
        }
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try AutoExportRunner.rememberFolder(url)
                AutoExportRunner.run(using: modelContext)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("When Kadō goes to the background, it saves Kado-latest.json and one dated copy a day (the last 30 are kept) into this folder, in the same format as Export Data › JSON.")
            if !lastError.isEmpty {
                Text("Last automatic backup failed: \(lastError)")
                    .foregroundStyle(.red)
            } else if lastRunAt > 0 {
                Text("Last automatic backup: \(Date(timeIntervalSince1970: lastRunAt).formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .foregroundStyle(Color.kadoForegroundSecondary)
    }
}

#Preview("Off") {
    Form { AutoExportSection() }
}

#Preview("Dark") {
    Form { AutoExportSection() }
        .preferredColorScheme(.dark)
}
