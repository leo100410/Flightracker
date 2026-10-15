import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct DiagnosticEvent: Codable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var process: String
    public var session: UUID
    public var build: String
    public var event: String
    public init(process: String, session: UUID, build: String, event: String, at: Date = Date()) {
        id = UUID(); self.at = at; self.process = process
        self.session = session; self.build = build
        self.event = String(event.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").prefix(800))
    }
}

/// Separate advisory lock protects concurrent WidgetKit processes. Oldest events rotate out.
public struct DiagnosticJournal: Sendable {
    public let directory: URL
    public let limit: Int
    public init(directory: URL, limit: Int = 524_288) { self.directory = directory; self.limit = limit }
    private var file: URL { directory.appendingPathComponent("events.jsonl") }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("journal.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        // A suspended extension must never block another provider's execution budget.
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw CocoaError(.fileLocking) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
    public func append(_ event: DiagnosticEvent) throws {
        try locked {
            var line = try JSONEncoder().encode(event); line.append(10)
            guard line.count <= limit else { throw CocoaError(.fileWriteOutOfSpace) }
            if !FileManager.default.fileExists(atPath: file.path) {
                try Data().write(to: file, options: .atomic)
            }
            let handle = try FileHandle(forUpdating: file)
            defer { try? handle.close() }
            var size = try handle.seekToEnd()
            if size > 0 {
                try handle.seek(toOffset: size - 1)
                let last = try handle.read(upToCount: 1)
                try handle.seekToEnd()
                if last?.first != 10 { try handle.write(contentsOf: Data([10])); size += 1 }
            }
            if size + UInt64(line.count) > UInt64(limit) {
                let bytes = try Data(contentsOf: file)
                // Rotate to half capacity to avoid rewriting on every subsequent event.
                let tail = bytes.suffix(limit / 2)
                let retained = tail.firstIndex(of: 10).map { Data(tail[tail.index(after: $0)...]) } ?? Data()
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
                try handle.write(contentsOf: retained)
            }
            try handle.write(contentsOf: line)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            #endif
        }
    }
    public func merge(_ events: [DiagnosticEvent]) throws {
        try locked {
            var existing = try readUnlocked()
            var ids = Set(existing.map(\.id))
            existing.append(contentsOf: events.filter { ids.insert($0.id).inserted })
            existing.sort { $0.at < $1.at }
            let encoder = JSONEncoder()
            var lines: [Data] = []
            var size = 0
            for event in existing.reversed() {
                var line = try encoder.encode(event); line.append(10)
                guard size + line.count <= limit else { break }
                lines.append(line); size += line.count
            }
            var output = Data()
            for line in lines.reversed() { output.append(line) }
            try output.write(to: file, options: .atomic)
            #if os(iOS)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            #endif
        }
    }
    private func readUnlocked() throws -> [DiagnosticEvent] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        let bytes = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        return bytes.split(separator: 10).compactMap { try? decoder.decode(DiagnosticEvent.self, from: Data($0)) }
    }
    public func read() throws -> [DiagnosticEvent] { try locked { try readUnlocked() } }
}
