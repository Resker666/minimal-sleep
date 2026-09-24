import Foundation

enum SoundOrigin: Equatable, Sendable {
    case recordedRain(author: String, license: String)
    case proceduralApproximation
    case generatedNoise
    case imported
}

struct SoundDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let resourceBaseName: String
    let resourceExtension: String
    let origin: SoundOrigin
    let importedSoundID: UUID?
    let directResourceURL: URL?

    init(
        id: String,
        title: String,
        resourceBaseName: String,
        resourceExtension: String,
        origin: SoundOrigin,
        importedSoundID: UUID? = nil,
        directResourceURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.resourceBaseName = resourceBaseName
        self.resourceExtension = resourceExtension
        self.origin = origin
        self.importedSoundID = importedSoundID
        self.directResourceURL = directResourceURL
    }

    static func imported(_ sound: ImportedSound, fileURL: URL) -> SoundDescriptor {
        SoundDescriptor(
            id: "imported-\(sound.id.uuidString.lowercased())",
            title: sound.displayName,
            resourceBaseName: fileURL.deletingPathExtension().lastPathComponent,
            resourceExtension: fileURL.pathExtension,
            origin: .imported,
            importedSoundID: sound.id,
            directResourceURL: fileURL
        )
    }

    var attribution: String? {
        guard case let .recordedRain(author, license) = origin else { return nil }
        return "\(author) / \(license)"
    }

    var isProceduralApproximation: Bool {
        origin == .proceduralApproximation
    }
}

enum SoundCatalog {
    static let builtIn: [SoundDescriptor] = [
        SoundDescriptor(
            id: "recorded-rain-heavy",
            title: "大雨剪辑",
            resourceBaseName: "rain-01",
            resourceExtension: "m4a",
            origin: .recordedRain(author: "Resker666", license: "CC BY 4.0")
        ),
        SoundDescriptor(
            id: "recorded-rain-thunder",
            title: "雨雷剪辑",
            resourceBaseName: "rain-04",
            resourceExtension: "m4a",
            origin: .recordedRain(author: "Resker666", license: "CC BY 4.0")
        ),
        SoundDescriptor(
            id: "procedural-heavy-rain",
            title: "合成大雨",
            resourceBaseName: "heavy_rain",
            resourceExtension: "wav",
            origin: .proceduralApproximation
        ),
        SoundDescriptor(
            id: "procedural-ocean-waves",
            title: "合成海浪",
            resourceBaseName: "ocean_waves",
            resourceExtension: "wav",
            origin: .proceduralApproximation
        ),
        SoundDescriptor(
            id: "white-noise",
            title: "白噪声",
            resourceBaseName: "white_noise",
            resourceExtension: "wav",
            origin: .generatedNoise
        ),
    ]
}
