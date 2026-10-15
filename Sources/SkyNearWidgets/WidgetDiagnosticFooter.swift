import SwiftUI
import RadarCore

struct WidgetDiagnosticFooter: View {
    var load: WidgetLoad
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text("Abruf")
                if let time = load.diagnosticAt { Text(time, style: .time) } else { Text("–") }
                Text("· API")
                if let time = load.real?.fetchedAt { Text(time, style: .time) } else { Text("–") }
                Spacer(minLength: 1)
                if let url = load.diagnosticURL { Link("Diagnose", destination: url).fontWeight(.bold) }
            }
            Text("\(load.diagnosticStatus) · Build \(RadarDiagnostics.build)")
        }
        .font(.system(size: 8)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).unredacted()
    }
}
