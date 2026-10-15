import Foundation

/// Family resolution uses only aircraft type codes and aircraft reference data.
public enum AircraftFamily: String, CaseIterable, Sendable {
    case a220, a300, a310, a318, a319, a320, a321, a330, a340, a350, a380, b707, b717, b727, b737, b747, b757, b767, b777, b787, erj, ejet, crj, dash8, atr42, atr72
    case airbus, boeing, embraer, bombardier, atr, cessna, gulfstream, helicopter, generic

    public static func resolve(code: String?, reference: String? = nil, manufacturer: String? = nil) -> Self {
        for value in [code, reference].compactMap({ $0 }) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if let family = codes[normalized] { return family }
            // Full reference names have a model boundary; do not guess from arbitrary prefixes.
            let model = normalized.replacingOccurrences(of: "AIRBUS ", with: "").replacingOccurrences(of: "BOEING ", with: "")
            for (name, family) in referenceNames {
                if model == name || model.hasPrefix(name + "-") || model.hasPrefix(name + " ") || model == name + "NEO" { return family }
            }
        }
        let maker = manufacturer?.lowercased() ?? ""
        if maker.contains("airbus") { return .airbus }
        if maker.contains("boeing") { return .boeing }
        if maker.contains("embraer") { return .embraer }
        if maker.contains("bombardier") { return .bombardier }
        if maker.contains("atr") { return .atr }
        if maker.contains("cessna") || maker.contains("textron") { return .cessna }
        if maker.contains("gulfstream") { return .gulfstream }
        return .generic
    }
    private static let codes: [String: Self] = {
        var result: [String: Self] = [:]
        for code in "BCS1 BCS3".split(separator: " ") { result[String(code)] = .a220 }
        for code in "A30B A306".split(separator: " ") { result[String(code)] = .a300 }
        for code in "A310".split(separator: " ") { result[String(code)] = .a310 }
        for code in "A318".split(separator: " ") { result[String(code)] = .a318 }
        for code in "A319 A19N".split(separator: " ") { result[String(code)] = .a319 }
        for code in "A320 A20N".split(separator: " ") { result[String(code)] = .a320 }
        for code in "A321 A21N".split(separator: " ") { result[String(code)] = .a321 }
        for code in "A332 A333 A338 A339".split(separator: " ") { result[String(code)] = .a330 }
        for code in "A342 A343 A345 A346".split(separator: " ") { result[String(code)] = .a340 }
        for code in "A359 A35K".split(separator: " ") { result[String(code)] = .a350 }
        for code in "A388".split(separator: " ") { result[String(code)] = .a380 }
        for code in "B701 B703 B707".split(separator: " ") { result[String(code)] = .b707 }
        for code in "B712".split(separator: " ") { result[String(code)] = .b717 }
        for code in "B721 B722 B727".split(separator: " ") { result[String(code)] = .b727 }
        for code in "B731 B732 B733 B734 B735 B736 B737 B738 B739 B37M B38M B39M B3XM".split(separator: " ") { result[String(code)] = .b737 }
        for code in "B741 B742 B743 B744 B748 B74R B74S".split(separator: " ") { result[String(code)] = .b747 }
        for code in "B752 B753".split(separator: " ") { result[String(code)] = .b757 }
        for code in "B762 B763 B764".split(separator: " ") { result[String(code)] = .b767 }
        for code in "B772 B773 B77L B77W B778 B779".split(separator: " ") { result[String(code)] = .b777 }
        for code in "B788 B789 B78X".split(separator: " ") { result[String(code)] = .b787 }
        for code in "E135 E145".split(separator: " ") { result[String(code)] = .erj }
        for code in "E170 E175 E190 E195 E75L E75S E290 E295".split(separator: " ") { result[String(code)] = .ejet }
        for code in "CRJ1 CRJ2 CRJ7 CRJ9 CRJX".split(separator: " ") { result[String(code)] = .crj }
        for code in "DH8A DH8B DH8C DH8D".split(separator: " ") { result[String(code)] = .dash8 }
        for code in "AT43 AT44 AT45 AT46".split(separator: " ") { result[String(code)] = .atr42 }
        for code in "AT72 AT73 AT75 AT76".split(separator: " ") { result[String(code)] = .atr72 }
        for code in ["R22", "R44", "R66", "EC35", "EC45", "H135", "H145", "B06", "B407"] { result[code] = .helicopter }
        return result
    }()
    private static let referenceNames: [(String, Self)] = [
        ("A220", .a220),
        ("A300", .a300),
        ("A310", .a310),
        ("A318", .a318),
        ("A319", .a319),
        ("A320", .a320),
        ("A321", .a321),
        ("A330", .a330),
        ("A340", .a340),
        ("A350", .a350),
        ("A380", .a380),
        ("707", .b707),
        ("717", .b717),
        ("727", .b727),
        ("737", .b737),
        ("747", .b747),
        ("757", .b757),
        ("767", .b767),
        ("777", .b777),
        ("787", .b787),
        ("EMBRAER ERJ", .erj), ("EMBRAER 190", .ejet), ("EMBRAER 195", .ejet),
        ("CRJ", .crj), ("DASH 8", .dash8), ("ATR 42", .atr42), ("ATR 72", .atr72)
    ]
    public var profile: AircraftProfile {
        switch self {
        case .a220: AircraftProfile(length: 35, span: 35, body: 4, engines: 2, layout: .wing, sweep: 0.3)
        case .a300: AircraftProfile(length: 54, span: 45, body: 6, engines: 2, layout: .wing, sweep: 0.3)
        case .a310: AircraftProfile(length: 47, span: 44, body: 6, engines: 2, layout: .wing, sweep: 0.3)
        case .a318: AircraftProfile(length: 31, span: 34, body: 4, engines: 2, layout: .wing, sweep: 0.3)
        case .a319: AircraftProfile(length: 34, span: 34, body: 4, engines: 2, layout: .wing, sweep: 0.3)
        case .a320: AircraftProfile(length: 38, span: 35, body: 4, engines: 2, layout: .wing, sweep: 0.3)
        case .a321: AircraftProfile(length: 45, span: 35, body: 4, engines: 2, layout: .wing, sweep: 0.3)
        case .a330: AircraftProfile(length: 63, span: 60, body: 6, engines: 2, layout: .wing, sweep: 0.3)
        case .a340: AircraftProfile(length: 70, span: 63, body: 6, engines: 4, layout: .wing, sweep: 0.3)
        case .a350: AircraftProfile(length: 70, span: 65, body: 6, engines: 2, layout: .wing, sweep: 0.3)
        case .a380: AircraftProfile(length: 73, span: 80, body: 9, engines: 4, layout: .wing, sweep: 0.3)
        case .b707: AircraftProfile(length: 46, span: 44, body: 4, engines: 4, layout: .wing, sweep: 0.38)
        case .b717: AircraftProfile(length: 38, span: 28, body: 4, engines: 2, layout: .rear, sweep: 0.38)
        case .b727: AircraftProfile(length: 47, span: 33, body: 4, engines: 3, layout: .rear, sweep: 0.38)
        case .b737: AircraftProfile(length: 40, span: 36, body: 4, engines: 2, layout: .wing, sweep: 0.38)
        case .b747: AircraftProfile(length: 71, span: 65, body: 8, engines: 4, layout: .wing, sweep: 0.38)
        case .b757: AircraftProfile(length: 52, span: 38, body: 4, engines: 2, layout: .wing, sweep: 0.38)
        case .b767: AircraftProfile(length: 55, span: 48, body: 5, engines: 2, layout: .wing, sweep: 0.38)
        case .b777: AircraftProfile(length: 71, span: 65, body: 6, engines: 2, layout: .wing, sweep: 0.38)
        case .b787: AircraftProfile(length: 63, span: 60, body: 6, engines: 2, layout: .wing, sweep: 0.38)
        case .erj: AircraftProfile(length: 28, span: 20, body: 3, engines: 2, layout: .rear, sweep: 0.38)
        case .ejet: AircraftProfile(length: 36, span: 29, body: 4, engines: 2, layout: .wing, sweep: 0.38)
        case .crj: AircraftProfile(length: 32, span: 24, body: 3, engines: 2, layout: .rear, sweep: 0.38)
        case .dash8: AircraftProfile(length: 29, span: 28, body: 3, engines: 2, layout: .prop, sweep: 0.12)
        case .atr42: AircraftProfile(length: 23, span: 25, body: 3, engines: 2, layout: .prop, sweep: 0.12)
        case .atr72: AircraftProfile(length: 27, span: 27, body: 3, engines: 2, layout: .prop, sweep: 0.12)
        case .airbus: AircraftFamily.a320.profile
        case .boeing: AircraftFamily.b737.profile
        case .embraer: AircraftFamily.ejet.profile
        case .bombardier, .gulfstream: AircraftFamily.crj.profile
        case .atr: AircraftFamily.atr72.profile
        case .cessna: AircraftProfile(length: 11, span: 13, body: 1.5, engines: 1, layout: .prop, sweep: 0.04)
        case .helicopter: AircraftProfile(length: 12, span: 12, body: 3, engines: 0, layout: .rotor, sweep: 0)
        case .generic: AircraftProfile(length: 38, span: 34, body: 4, engines: 2, layout: .wing, sweep: 0.25)
        }
    }
}
public struct AircraftProfile: Sendable, Equatable {
    public enum Layout: Sendable { case wing, rear, prop, rotor }
    public var length: Double
    public var span: Double
    public var body: Double
    public var engines: Int
    public var layout: Layout
    public var sweep: Double
}
public extension Plane {
    var aircraftFamily: AircraftFamily {
        .resolve(code: typeCode, reference: metadata?.aircraft?.type, manufacturer: metadata?.aircraft?.manufacturer)
    }
    // Prediction status deliberately does not participate in marker color.
    var markerIsGround: Bool { onGround }
}
