import Foundation
import SwiftData
import KadoCore

/// Writes the lossless JSON backup into a folder the user picked once
/// (typically in iCloud Drive), without them tapping Export.
///
/// Two kinds of file, both the exact bytes Settings › Export Data ›
/// JSON produces, so either imports back unchanged:
/// - `Kado-latest.json`, rewritten on every run.
/// - `Kado-YYYY-MM-DD.json`, written at most once per day: the first
///   run of a day leaves it, later runs that day only refresh `latest`.
///   The newest `keptDatedCopies` are kept; older ones are deleted.
@MainActor
struct AutoExporter {
    static let latestFilename = "Kado-latest.json"
    static let keptDatedCopies = 30

    let exporter: any BackupExporting
    let calendar: Calendar
    let fileManager: FileManager

    init(
        exporter: (any BackupExporting)? = nil,
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) {
        // Resolved here rather than as a default argument, which Swift
        // evaluates outside the MainActor this exporter's init needs.
        self.exporter = exporter ?? DefaultBackupExporter()
        self.calendar = calendar
        self.fileManager = fileManager
    }

    /// What a run wrote.
    struct Outcome: Equatable {
        /// The dated copy, when this run was the day's first.
        let datedCopy: URL?
        /// Dated copies deleted to stay within `keptDatedCopies`.
        let pruned: [URL]
    }

    /// Exports the store into `folder`. The caller owns access to the
    /// folder (security scope, coordination); this only writes files.
    @discardableResult
    func run(from context: ModelContext, into folder: URL, now: Date = .now) throws -> Outcome {
        let data = try exporter.exportData(from: context)
        try data.write(to: folder.appendingPathComponent(Self.latestFilename), options: .atomic)

        let dated = folder.appendingPathComponent(datedFilename(for: now))
        var datedCopy: URL?
        if !fileManager.fileExists(atPath: dated.path) {
            try data.write(to: dated, options: .atomic)
            datedCopy = dated
        }
        return Outcome(datedCopy: datedCopy, pruned: try prune(folder))
    }

    /// `Kado-2026-11-08.json`, in the user's calendar so "once a day"
    /// means their day. Digits forced to ASCII, whatever the locale.
    func datedFilename(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0
        )
        return "Kado-\(stamp).json"
    }

    /// Deletes the oldest dated copies past `keptDatedCopies`. Only
    /// touches files named like ours; anything else in the folder is
    /// the user's.
    private func prune(_ folder: URL) throws -> [URL] {
        let names = try fileManager.contentsOfDirectory(atPath: folder.path)
            .filter(Self.isDatedCopy)
            .sorted()
        let excess = names.dropLast(Self.keptDatedCopies)
        let urls = excess.map { folder.appendingPathComponent($0) }
        for url in urls {
            try fileManager.removeItem(at: url)
        }
        return urls
    }

    /// `Kado-` + `YYYY-MM-DD` + `.json`. The fixed-width date sorts
    /// chronologically as text.
    static func isDatedCopy(_ name: String) -> Bool {
        name.range(of: #"^Kado-\d{4}-\d{2}-\d{2}\.json$"#, options: .regularExpression) != nil
    }
}
