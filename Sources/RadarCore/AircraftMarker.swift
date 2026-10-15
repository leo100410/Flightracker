import SwiftUI

/// North-facing, locally drawn silhouettes shared by the app and map widget.
public struct AircraftSilhouette: Shape {
    public var family: AircraftFamily
    public init(family: AircraftFamily) { self.family = family }
    public func path(in rect: CGRect) -> Path {
        let spec = family.profile
        let scale = min(rect.width, rect.height) / max(spec.length, spec.span)
        let length = spec.length * scale, span = spec.span * scale
        let body = max(2, spec.body * scale)
        let x = rect.midX, top = rect.midY - length / 2
        var path = Path()
        func polygon(_ points: [CGPoint]) {
            let area = points.indices.reduce(CGFloat.zero) { result, index in
                let next = points[(index + 1) % points.count]
                return result + points[index].x * next.y - next.x * points[index].y
            }
            path.addLines(area < 0 ? Array(points.reversed()) : points); path.closeSubpath()
        }
        // Rounded nose, parallel cabin and a tapered tail, instead of a capsule.
        path.move(to: CGPoint(x: x, y: top))
        path.addCurve(to: CGPoint(x: x + body / 2, y: top + length * 0.16),
                      control1: CGPoint(x: x + body * 0.35, y: top + length * 0.015),
                      control2: CGPoint(x: x + body / 2, y: top + length * 0.08))
        path.addLine(to: CGPoint(x: x + body / 2, y: top + length * 0.69))
        path.addLine(to: CGPoint(x: x + body * 0.16, y: top + length * 0.98))
        path.addQuadCurve(to: CGPoint(x: x - body * 0.16, y: top + length * 0.98),
                          control: CGPoint(x: x, y: top + length))
        path.addLine(to: CGPoint(x: x - body / 2, y: top + length * 0.69))
        path.addLine(to: CGPoint(x: x - body / 2, y: top + length * 0.16))
        path.addCurve(to: CGPoint(x: x, y: top),
                      control1: CGPoint(x: x - body / 2, y: top + length * 0.08),
                      control2: CGPoint(x: x - body * 0.35, y: top + length * 0.015))
        path.closeSubpath()
        for side in [-1.0, 1.0] {
            let root = top + length * 0.32
            polygon([CGPoint(x: x, y: root),
                     CGPoint(x: x + side * span / 2, y: root + length * spec.sweep),
                     CGPoint(x: x + side * span * 0.48, y: root + length * (spec.sweep + 0.045)),
                     CGPoint(x: x + side * span * 0.16, y: root + length * 0.25),
                     CGPoint(x: x, y: root + length * 0.27)])
            let tailSpan = spec.layout == .rear ? 0.25 : 0.22
            polygon([CGPoint(x: x, y: top + length * 0.78),
                     CGPoint(x: x + side * span * tailSpan, y: top + length * 0.92),
                     CGPoint(x: x + side * span * tailSpan, y: top + length * 0.95),
                     CGPoint(x: x, y: top + length * 0.92)])
            for index in 0..<(spec.engines / 2) {
                let rear = spec.layout == .rear
                let offset = rear ? body * 0.85 : span * (0.22 + Double(index) * 0.16)
                let engineY = top + length * (rear ? 0.72 : (0.32 + Double(index) * 0.12))
                let engineX = x + side * offset
                path.addRoundedRect(in: CGRect(x: engineX - body * 0.3, y: engineY,
                                               width: body * 0.6, height: length * 0.12),
                                    cornerSize: CGSize(width: body * 0.2, height: body * 0.2))
                if spec.layout == .prop {
                    path.addRect(CGRect(x: engineX - span * 0.1, y: engineY, width: span * 0.2, height: 1.5))
                }
            }
        }
        if spec.engines == 3 {
            path.addRect(CGRect(x: x - body * 0.25, y: top + length * 0.83, width: body * 0.5, height: length * 0.17))
        }
        if spec.layout == .rotor {
            path.addRect(CGRect(x: x - span / 2, y: rect.midY - 1, width: span, height: 2))
            path.addRect(CGRect(x: x - 1, y: rect.midY - span / 2, width: 2, height: span))
        }
        return path
    }
}

public struct AircraftMarker: View {
    public var plane: Plane
    public var size: CGFloat
    public init(plane: Plane, size: CGFloat = 30) { self.plane = plane; self.size = size }
    public var body: some View {
        AircraftSilhouette(family: plane.aircraftFamily)
            .fill(plane.markerIsGround ? Color.gray : Color.cyan)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(plane.track.flatMap { $0.isFinite ? $0 : nil } ?? 0))
            .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
            .padding(6)
            .overlay(Circle().strokeBorder(.white.opacity(plane.isEstimated ? 0.9 : 0),
                style: StrokeStyle(lineWidth: 1, dash: plane.isEstimated ? [3, 3] : [])))
            .accessibilityLabel(plane.label + (plane.isEstimated ? ", Geschätzt" : ""))
    }
}
