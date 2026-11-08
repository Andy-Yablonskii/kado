import Testing
import Foundation
import SwiftData
@testable import Kado
import KadoCore

@Suite("AutoExporter")
@MainActor
struct AutoExporterTests {
    let container: ModelContainer
    let folder: URL
    let exporter = AutoExporter(exporter: DefaultBackupExporter(appVersion: "test"), calendar: TestCalendar.utc)

    init() throws {
        container = try ModelContainer(
            for: HabitRecord.self, CompletionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let habit = HabitRecord(name: "Meditate", type: .binary)
        container.mainContext.insert(habit)
        container.mainContext.insert(CompletionRecord(date: TestCalendar.day(0), value: HardDay.value, habit: habit))
        try container.mainContext.save()
    }

    private func files() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test("The first run of a day writes the latest file and that day's dated copy")
    func firstRunWritesBoth() throws {
        let outcome = try exporter.run(from: container.mainContext, into: folder, now: TestCalendar.day(0))
        #expect(try files() == ["Kado-2026-04-13.json", "Kado-latest.json"])
        #expect(outcome.datedCopy?.lastPathComponent == "Kado-2026-04-13.json")
    }

    @Test("A second run the same day refreshes latest but leaves the dated copy alone")
    func secondRunSameDay() throws {
        try exporter.run(from: container.mainContext, into: folder, now: TestCalendar.day(0))
        let dated = folder.appendingPathComponent("Kado-2026-04-13.json")
        let before = try Data(contentsOf: dated)

        container.mainContext.insert(HabitRecord(name: "Read", type: .binary))
        try container.mainContext.save()
        let outcome = try exporter.run(from: container.mainContext, into: folder, now: TestCalendar.day(0))

        #expect(outcome.datedCopy == nil)
        #expect(try Data(contentsOf: dated) == before)
        let latest = try DefaultBackupImporter().parse(
            data: Data(contentsOf: folder.appendingPathComponent(AutoExporter.latestFilename))
        )
        #expect(latest.habits.count == 2)
    }

    @Test("What it writes imports back losslessly, hard days included")
    func importsBack() throws {
        try exporter.run(from: container.mainContext, into: folder, now: TestCalendar.day(0))
        let document = try DefaultBackupImporter().parse(
            data: Data(contentsOf: folder.appendingPathComponent(AutoExporter.latestFilename))
        )
        // Field-for-field losslessness is `BackupRoundTripTests`' job;
        // this pins that the file *is* that backup.
        let records = try container.mainContext.fetch(FetchDescriptor<HabitRecord>())
        #expect(document.habits.map(\.id) == records.map(\.id))
        #expect(document.habits.first?.completions.first?.value == HardDay.value)
    }

    @Test("Only the newest dated copies are kept, and other files are left alone")
    func prunesOldDatedCopies() throws {
        try Data("mine".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        for offset in 0..<(AutoExporter.keptDatedCopies + 3) {
            try exporter.run(from: container.mainContext, into: folder, now: TestCalendar.day(-offset))
        }
        let dated = try files().filter(AutoExporter.isDatedCopy)
        #expect(dated.count == AutoExporter.keptDatedCopies)
        #expect(dated.last == "Kado-2026-04-13.json")
        #expect(dated.first == exporter.datedFilename(for: TestCalendar.day(-(AutoExporter.keptDatedCopies - 1))))
        #expect(try files().contains("notes.txt"))
        #expect(try files().contains(AutoExporter.latestFilename))
    }

    @Test("Only our own dated names count as dated copies")
    func datedCopyNames() {
        #expect(AutoExporter.isDatedCopy("Kado-2026-11-08.json"))
        #expect(!AutoExporter.isDatedCopy("Kado-latest.json"))
        #expect(!AutoExporter.isDatedCopy("kado-backup-2026-11-08.json"))
        #expect(!AutoExporter.isDatedCopy("Kado-2026-11-08.json.bak"))
    }
}
