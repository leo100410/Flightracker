import SwiftUI
import UIKit
import BackgroundTasks
import RadarCore

@MainActor
enum AppDiagnostics {
    static var refreshStatus: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: "Verfügbar"
        case .denied: "Deaktiviert"
        case .restricted: "Eingeschränkt"
        @unknown default: "Unbekannt"
        }
    }
    static func capture(_ reason: String) {
        BackgroundRefresh.inspectConfiguration()
        RadarDiagnostics.record("shared storage \(SharedWidgetStorage.inspect(process: "app"))")
        RadarDiagnostics.record("app environment reason=\(reason) backgroundRefresh=\(refreshStatus) lowPower=\(ProcessInfo.processInfo.isLowPowerModeEnabled) thermal=\(ProcessInfo.processInfo.thermalState.rawValue) state=\(UIApplication.shared.applicationState.rawValue)")
    }
}

struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var records: [DiagnosticEvent] = []
    @State private var pending = "Wird geprüft …"
    @State private var sharedStatus = "Wird geprüft …"
    @State private var exportURL: URL?
    @State private var error: String?
    @State private var busy = false
    var importMessage: String?

    var body: some View {
        List {
            Section("Aktualisierung · Build \(RadarDiagnostics.build)") {
                LabeledContent("Hintergrundaktualisierung", value: AppDiagnostics.refreshStatus)
                LabeledContent("Stromsparmodus", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "Ein" : "Aus")
                LabeledContent("Geplante App-Aufgabe", value: pending)
                LabeledContent("Installierter Task", value: BackgroundRefresh.identifier)
                LabeledContent("Konfiguration", value: BackgroundRefresh.permittedIdentifiers.contains(BackgroundRefresh.identifier) && BackgroundRefresh.modes.contains("fetch") ? "Passend" : "Abweichung – siehe Log")
                Text("Gemeinsamer Speicher: " + sharedStatus)
                    .font(.caption).textSelection(.enabled)
                if let time = UserDefaults.standard.object(forKey: "skynear.background-success.v1") as? Double {
                    LabeledContent("Letzter App-Hintergrunderfolg", value: localTime(Date(timeIntervalSince1970: time)))
                }
                Text("Ein geplanter Termin ist keine Zusage von iOS. Widget-Abrufe laufen unabhängig von der App-Aufgabe.")
                    .font(.caption).foregroundStyle(.secondary)
                if let failure = UserDefaults.standard.string(forKey: "skynear.background-error.v1") {
                    Text(failure).foregroundStyle(.orange).font(.caption)
                }
            }
            Section("Widget-Protokoll übernehmen") {
                Text("Nach dem Test im Widget auf „Diagnose“ tippen. Dadurch wird dessen gespeichertes Protokoll in diese App übernommen. Bei mehreren Widgets den Link in jedem Widget verwenden.")
                Text("Der Link enthält den Stand bei Erstellung der angezeigten Timeline. Wenn die Signierung gemeinsamen Speicher erlaubt, liest der Export zusätzlich aktuelle Widget-Ereignisse direkt. peerLastSeen zeigt, ob auch der andere Prozess diesen Speicher erreicht hat.")
                    .font(.caption).foregroundStyle(.secondary)
                if let importMessage { Text(importMessage).font(.caption) }
                if let time = UserDefaults.standard.object(forKey: "skynear.widget-import-captured") as? Double {
                    LabeledContent("Übernommener Widget-Stand", value: localTime(Date(timeIntervalSince1970: time)))
                } else { Text("Noch kein Widget-Protokoll übernommen").foregroundStyle(.orange) }
            }
            Section("Logdatei") {
                Button("Logdatei erstellen / aktualisieren") { Task { await prepareExport() } }
                    .disabled(busy)
                if busy { ProgressView() }
                if let exportURL { ShareLink("SkyNear-Diagnose.log teilen", item: exportURL) }
                if let error { Text(error).foregroundStyle(.orange) }
                Text("Die Datei enthält App- und übernommene Widget-Ereignisse mit Uhrzeit, Build, Abrufstatus und Datenalter. Keine Koordinaten, Flugzeugkennungen oder Zugangsdaten. Alte Einträge werden bei 512 KiB entfernt; ein Widget-Link enthält höchstens 160 aktuelle Einträge.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Letzte Ereignisse") {
                ForEach(records.suffix(30).reversed()) { event in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(localTime(event.at)) · \(event.process) · Build \(event.build)").font(.caption2).foregroundStyle(.secondary)
                        Text(event.event).font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Aktualisierungsdiagnose")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { dismiss() } } }
        .task { await reload() }
        .onChange(of: phase) { _, value in if value == .active { Task { await reload() } } }
        .refreshable { await reload() }
    }
    private func localTime(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .standard) }
    private func reload() async {
        AppDiagnostics.capture("diagnostics screen")
        sharedStatus = SharedWidgetStorage.inspect(process: "app")
        let requests = await BGTaskScheduler.shared.pendingTaskRequests()
        let request = requests.first { $0.identifier == BackgroundRefresh.identifier }
        pending = request.map { $0.earliestBeginDate.map(localTime) ?? "Ohne frühesten Termin" } ?? "Keine"
        RadarDiagnostics.record("background inspection pending=\(request != nil) earliest=\(RadarDiagnostics.stamp(request?.earliestBeginDate))")
        do { records = try await Task.detached { try RadarDiagnostics.events() }.value }
        catch { self.error = RadarDiagnostics.errorCode(error) }
    }
    private func prepareExport() async {
        busy = true; error = nil; exportURL = nil
        defer { busy = false }
        await reload()
        RadarDiagnostics.record("export requested")
        do { exportURL = try await Task.detached { try RadarDiagnostics.exportReport() }.value }
        catch { self.error = "Export fehlgeschlagen: " + RadarDiagnostics.errorCode(error) }
    }
}
