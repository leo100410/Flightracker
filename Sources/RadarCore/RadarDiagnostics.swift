import Foundation
import os
import Compression

public enum RadarDiagnostics {
    private static let logger = Logger(subsystem: "de.leola.skynear", category: "Refresh")
    private static let queue = DispatchQueue(label: "de.leola.skynear.diagnostics")
    private static let session = UUID()
    public static var process: String { Bundle.main.bundleURL.pathExtension == "appex" ? "widget" : "app" }
    public static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    private static var journal: DiagnosticJournal {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return DiagnosticJournal(directory: base.appendingPathComponent("SkyNearDiagnostics"))
    }
    public static func record(_ event: String) {
        // Operational facts only: no coordinates, flight IDs, URLs or credentials.
        logger.info("\(event, privacy: .public)")
        queue.sync {
            let entry = DiagnosticEvent(process: process, session: session, build: build, event: event)
            do {
                try journal.append(entry)
            } catch {
                UserDefaults.standard.set(stamp(Date()) + " " + errorCode(error), forKey: "skynear.diagnostic-write-error")
            }
            if let folder = SharedWidgetStorage.directory {
                do { try DiagnosticJournal(directory: folder.appendingPathComponent("Diagnostics")).append(entry) }
                catch { UserDefaults.standard.set(stamp(Date()) + " " + errorCode(error), forKey: "skynear.shared-journal-error") }
            }
        }
    }
    public static func errorCode(_ error: any Error) -> String {
        let value = error as NSError
        return "\(value.domain):\(value.code)"
    }
    public static func stamp(_ date: Date?) -> String {
        guard let date else { return "none" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    public static func events() throws -> [DiagnosticEvent] {
        try queue.sync {
            if let folder = SharedWidgetStorage.directory {
                do {
                    let shared = try DiagnosticJournal(directory: folder.appendingPathComponent("Diagnostics")).read()
                    try journal.merge(shared)
                } catch {
                    UserDefaults.standard.set(stamp(Date()) + " " + errorCode(error), forKey: "skynear.shared-journal-error")
                }
            }
            return try journal.read()
        }
    }
    struct Transfer: Codable {
        var version = 1
        var captured: Date
        var available: Int
        var events: [DiagnosticEvent]
        var writeError: String?
    }
    // Bounded compressed snapshot: no assumption that app and extension share a container.
    public static func widgetTransferURL() -> URL? {
        do {
            return try transferURL(events: events().filter { $0.process == "widget" },
                                   writeError: UserDefaults.standard.string(forKey: "skynear.diagnostic-write-error"))
        } catch { record("diagnostic transfer failed \(errorCode(error))") }
        return nil
    }
    static func transferURL(events all: [DiagnosticEvent], writeError: String? = nil) throws -> URL? {
        var selected = Array(all.suffix(160))
        while !selected.isEmpty {
            let data = try JSONEncoder().encode(Transfer(captured: Date(), available: all.count, events: selected, writeError: writeError))
            if data.count <= 200_000, let packed = compress(data), packed.count <= 6_000 {
                let token = packed.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
                return URL(string: "skynear://diagnostics?v=1&log=\(token)")
            }
            selected = Array(selected.dropFirst(max(1, selected.count / 4)))
        }
        return nil
    }
    static func decodedTransfer(_ url: URL) throws -> Transfer {
        guard url.scheme == "skynear", url.host == "diagnostics", url.absoluteString.count <= 9_000,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.first(where: { $0.name == "v" })?.value == "1",
              var token = parts.queryItems?.first(where: { $0.name == "log" })?.value else {
            throw CocoaError(.fileReadCorruptFile)
        }
        token = token.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        token += String(repeating: "=", count: (4 - token.count % 4) % 4)
        guard let packed = Data(base64Encoded: token), packed.count <= 6_000,
              let data = decompress(packed) else { throw CocoaError(.fileReadCorruptFile) }
        var transfer = try JSONDecoder().decode(Transfer.self, from: data)
        guard transfer.version == 1, transfer.events.count <= 160,
              transfer.available >= transfer.events.count, (transfer.writeError?.count ?? 0) <= 200,
              transfer.events.allSatisfy({ $0.process == "widget" && $0.event.count <= 800 && $0.build.count <= 30 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for index in transfer.events.indices {
            transfer.events[index].event = transfer.events[index].event.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        }
        return transfer
    }
    public static func importWidgetURL(_ url: URL) throws -> Int {
        let transfer = try decodedTransfer(url)
        try queue.sync { try journal.merge(transfer.events) }
        UserDefaults.standard.set(transfer.captured.timeIntervalSince1970, forKey: "skynear.widget-import-captured")
        if let writeError = transfer.writeError { record("widget journal previously failed \(writeError)") }
        record("widget import captured=\(stamp(transfer.captured)) transferred=\(transfer.events.count) available=\(transfer.available)")
        return transfer.events.count
    }
    public static func exportReport() throws -> URL {
        let records = try events()
        var text = "SkyNear diagnosis | build \(build) | exported \(stamp(Date()))\n"
        text += "OS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        text += "Shared storage: \(SharedWidgetStorage.inspect(process: process))\n"
        text += "Times: UTC. real/measurement = source data time; display = prediction time.\n"
        text += "Bounded journal: 512 KiB; oldest events rotate out. Widget links carry up to 160 recent events.\n"
        text += "Widget imports are snapshots captured during timeline preparation, NOT continuous access to the extension.\n"
        text += "Events record code paths, not proof that iOS displayed or scheduled content.\n"
        text += "No coordinates, aircraft identifiers, URLs, tokens or certificates are collected.\n"
        if let error = UserDefaults.standard.string(forKey: "skynear.diagnostic-write-error") { text += "LAST JOURNAL WRITE ERROR (events may be missing): \(error)\n" }
        if let error = UserDefaults.standard.string(forKey: "skynear.shared-journal-error") { text += "LAST SHARED JOURNAL ERROR (events may be missing): \(error)\n" }
        let summary: [(String, (DiagnosticEvent) -> Bool)] = [
            ("Last app measurement", { $0.event.hasPrefix("app nearby accepted") }),
            ("Last widget measurement/cache", { $0.event.hasPrefix("widget load finished") }),
            ("Last widget provider", { $0.event.hasPrefix("provider ") && $0.event.contains("begin") }),
            ("Last widget timeline", { $0.event.hasPrefix("provider ") && $0.event.contains("ready") }),
            ("Last app background execution", { $0.event.hasPrefix("background execution begin") }),
            ("Last scheduling failure", { $0.event.hasPrefix("background schedule rejected") }),
            ("Last installed configuration", { $0.event.hasPrefix("background installed") })
        ]
        for (label, matches) in summary {
            let last = records.last(where: matches)
            text += "\(label): \(last.map { stamp($0.at) + " " + $0.event } ?? "not recorded")\n"
        }
        text += "Widget coverage ends: \(stamp(records.last(where: { $0.process == "widget" })?.at)). Later execution cannot be inferred from missing entries.\n"
        if !records.contains(where: { $0.process == "widget" }) { text += "WIDGET LOG MISSING: tap Diagnose in a widget before exporting.\n" }
        for event in records {
            text += "\(stamp(event.at)) [\(event.process) build=\(event.build) session=\(event.session.uuidString.prefix(8))] \(event.event)\n"
        }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("SkyNear-Diagnose.log")
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
    private static func compress(_ data: Data) -> Data? {
        var destination = [UInt8](repeating: 0, count: data.count + 1024)
        let size = destination.count
        let count = data.withUnsafeBytes { raw in
            compression_encode_buffer(&destination, size, raw.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return count > 0 ? Data(destination.prefix(count)) : nil
    }
    private static func decompress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var destination = [UInt8](repeating: 0, count: 200_001)
        let count = data.withUnsafeBytes { raw in
            compression_decode_buffer(&destination, 200_001, raw.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
        }
        return count > 0 && count <= 200_000 ? Data(destination.prefix(count)) : nil
    }
}
