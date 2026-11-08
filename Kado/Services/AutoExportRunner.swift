import Foundation
import SwiftData
import KadoCore

/// Where and whether to back up automatically, and how the last run
/// went. Per device, in the standard defaults: the folder bookmark only
/// means something on the device that made it.
enum AutoExportDefaults {
    static let enabledKey = "autoExport.enabled"
    static let bookmarkKey = "autoExport.folderBookmark"
    static let folderNameKey = "autoExport.folderName"
    static let lastRunKey = "autoExport.lastRunAt"
    /// Empty when the last run succeeded.
    static let lastErrorKey = "autoExport.lastError"
}

/// Runs `AutoExporter` against the folder the user picked: resolves the
/// security-scoped bookmark, holds the scope and a file coordinator
/// (the folder is usually in iCloud Drive) for the write, and records
/// the outcome for Settings to show. Never throws: a backup that can't
/// be written must not get in the way of the app going to background.
@MainActor
enum AutoExportRunner {
    /// Remembers a folder from the Files picker. Called while the
    /// picker's URL is still valid; the bookmark is what survives.
    static func rememberFolder(_ url: URL, defaults: UserDefaults = .standard) throws {
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(
            options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil
        )
        defaults.set(bookmark, forKey: AutoExportDefaults.bookmarkKey)
        defaults.set(url.lastPathComponent, forKey: AutoExportDefaults.folderNameKey)
        defaults.set("", forKey: AutoExportDefaults.lastErrorKey)
    }

    /// The scene-phase hook: does nothing unless the user turned it on.
    static func runIfEnabled(using context: ModelContext, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: AutoExportDefaults.enabledKey) else { return }
        run(using: context, defaults: defaults)
    }

    static func run(using context: ModelContext, defaults: UserDefaults = .standard) {
        do {
            guard let bookmark = defaults.data(forKey: AutoExportDefaults.bookmarkKey) else {
                throw AutoExportError.noFolder
            }
            var isStale = false
            let folder = try URL(
                resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale
            )
            let didStart = folder.startAccessingSecurityScopedResource()
            defer { if didStart { folder.stopAccessingSecurityScopedResource() } }
            if isStale {
                try? rememberFolder(folder, defaults: defaults)
            }

            var coordinationError: NSError?
            var writeError: Error?
            NSFileCoordinator().coordinate(writingItemAt: folder, options: [], error: &coordinationError) { url in
                do {
                    try AutoExporter().run(from: context, into: url)
                } catch {
                    writeError = error
                }
            }
            if let error = coordinationError ?? writeError {
                throw error
            }
            defaults.set(Date.now.timeIntervalSince1970, forKey: AutoExportDefaults.lastRunKey)
            defaults.set("", forKey: AutoExportDefaults.lastErrorKey)
        } catch {
            defaults.set(error.localizedDescription, forKey: AutoExportDefaults.lastErrorKey)
        }
    }
}

enum AutoExportError: LocalizedError {
    case noFolder

    var errorDescription: String? {
        switch self {
        case .noFolder: String(localized: "Choose a folder for automatic backups.")
        }
    }
}
