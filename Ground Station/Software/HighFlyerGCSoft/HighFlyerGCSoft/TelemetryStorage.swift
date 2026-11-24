import Foundation

final class TelemetryStorage {

    private let fileURL: URL
    private var fileHandle: FileHandle?

    init() {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]

        try! FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        fileURL = directory.appendingPathComponent("Telemetry.jsonl")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(
                atPath: fileURL.path,
                contents: nil
            )
        }

        do {
            fileHandle = try FileHandle(forWritingTo: fileURL)
            try fileHandle?.seekToEnd()
        } catch {
            print("Storage initialization error: \(error)")
        }
    }

    func Save(_ data: [Telemetry]) {
        do {
            let encoder = JSONEncoder()

            for point in data {
                var record = try encoder.encode(point)
                record.append(0x0A) // New line

                try fileHandle?.write(contentsOf: record)
            }

            // Flush data to storage
            try fileHandle?.synchronize()

        } catch {
            print("Storage error: \(error)")
        }
    }

    func Load() -> [Telemetry] {

        do {
            let fileData = try Data(contentsOf: fileURL)

            let records = fileData.split(separator: 0x0A)

            return records.compactMap { record in
                try? JSONDecoder().decode(
                    Telemetry.self,
                    from: Data(record)
                )
            }

        } catch {
            print("Loading error: \(error)")
            return []
        }
    }

    deinit {
        try? fileHandle?.close()
    }
}
