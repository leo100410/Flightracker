"""Exercise the actual file journal on Linux; no iOS frameworks or UI are simulated."""
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
CHECKS = r'''
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let journal = DiagnosticJournal(directory: directory, limit: 4096)
let session = UUID()
let first = DiagnosticEvent(process: "widget", session: session, build: "6", event: "provider begin", at: Date(timeIntervalSince1970: 100))
try journal.append(first)
let second = DiagnosticEvent(process: "widget", session: session, build: "6", event: "network timeout", at: Date(timeIntervalSince1970: 101))
try journal.append(second)
let reopened = DiagnosticJournal(directory: directory, limit: 4096)
precondition(try reopened.read().map(\.id) == [first.id, second.id])
try journal.merge([second, first])
precondition(try journal.read().count == 2)
for index in 0..<100 {
    try journal.append(DiagnosticEvent(process: "app", session: session, build: "6", event: "event \(index)", at: Date(timeIntervalSince1970: Double(200 + index))))
}
let rotated = try journal.read()
precondition(rotated.last?.event == "event 99" && rotated.count < 100)
precondition(!rotated.contains { $0.id == first.id })
let bytes = try Data(contentsOf: directory.appendingPathComponent("events.jsonl"))
precondition(bytes.count <= 4096)
precondition(bytes.split(separator: 10).count == rotated.count)
// Simulate a process dying during a write; the next complete event must survive.
let partial = try FileHandle(forWritingTo: directory.appendingPathComponent("events.jsonl"))
try partial.seekToEnd()
try partial.write(contentsOf: Data("{unfinished".utf8)); try partial.close()
let recovery = DiagnosticEvent(process: "widget", session: session, build: "6", event: "recovered")
try journal.append(recovery)
let recovered = try journal.read()
precondition(recovered.last?.id == recovery.id)
let cleaned = DiagnosticEvent(process: "app", session: session, build: "6", event: "one\ntwo" + String(repeating: "x", count: 2000))
precondition(!cleaned.event.contains("\n") && cleaned.event.count == 800)
let descriptor = open(directory.appendingPathComponent("journal.lock").path, O_RDWR)
precondition(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0)
do {
    try journal.append(first)
    fatalError("Must not wait on a lock held by a suspended process")
} catch { }
flock(descriptor, LOCK_UN); close(descriptor)
print("Diagnostic journal checks passed: persistence, merge/deduplication, bounded rotation, sanitization, nonblocking locking.")
'''

if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="skynear-diagnostics-") as work:
        work = pathlib.Path(work)
        main = work / "main.swift"
        # precondition's autoclosure is nonthrowing.
        source = CHECKS.replace('precondition(try reopened.read().map(\\.id) == [first.id, second.id])',
                                'let persisted = try reopened.read(); precondition(persisted.map(\\.id) == [first.id, second.id])')
        source = source.replace('precondition(try journal.read().count == 2)',
                                'let merged = try journal.read(); precondition(merged.count == 2)')
        main.write_text(source, encoding="utf-8")
        executable = work / "checks"
        subprocess.run(["swiftc", "-swift-version", "6", str(ROOT / "Sources/RadarCore/DiagnosticJournal.swift"),
                        str(main), "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(work / "journal")], check=True, timeout=10)
