import Foundation

public struct ModelPhoto: Codable, Sendable {
    public var code: String
    public var title: String
    public var filename: String
    public var author: String
    public var license: String
    public var source: String
    public var licenseURL: String
    public var data: Data? {
        ModelPhotos.bytes[code]
    }
}
public enum ModelPhotos {
    static let bytes: [String: Data] = {
        var result: [String: Data] = [:]
        for photo in catalog {
            if let url = RadarResources.url(forResource: photo.filename, withExtension: "jpg"),
               let data = try? Data(contentsOf: url) { result[photo.code] = data }
        }
        return result
    }()
    public static let catalog: [ModelPhoto] = {
        guard let url = RadarResources.url(forResource: "ModelPhotos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ModelPhoto].self, from: data) else { return [] }
        return entries
    }()
    public static func reference(for plane: Plane) -> ModelPhoto? {
        // Use actual type data only. Never derive an aircraft model from a callsign.
        if let code = plane.typeCode?.uppercased(), let photo = catalog.first(where: { $0.code == code }) { return photo }
        let name = plane.metadata?.aircraft?.type?.lowercased() ?? ""
        return catalog.first { name == $0.title.lowercased() || name == $0.code.lowercased() }
    }
}
