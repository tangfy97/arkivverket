import Foundation

enum CorpusVaultExportError: LocalizedError {
    case missingCorpusRoot
    case invalidCorpusRoot(URL)
    case noImages
    case missingDestination
    case modelWriteFailed

    var errorDescription: String? {
        switch self {
        case .missingCorpusRoot:
            "CorpusVault root not configured."
        case let .invalidCorpusRoot(url):
            "CorpusVault root is invalid: \(url.path)"
        case .noImages:
            "No images to export."
        case .missingDestination:
            "Choose a CorpusVault model and pose group."
        case .modelWriteFailed:
            "Could not update CorpusVault models.json."
        }
    }
}

struct CorpusVaultModelChoice: Hashable {
    let id: String
    let name: String
}

struct CorpusVaultGroupChoice: Hashable {
    let id: String
    let name: String
    let folder: String
}

final class CorpusVaultExporter {
    static let shared = CorpusVaultExporter()

    private let fileManager = FileManager.default

    func exportCurrentImage(model: ModelFolder, image: ImageAsset) throws -> URL {
        try export(modelName: model.name, images: [image.url])
    }

    func exportImages(model: ModelFolder, images: [ImageAsset]) throws -> URL {
        try export(modelName: model.name, images: images.map(\.url))
    }

    func exportFolder(model: ModelFolder) throws -> URL {
        try export(modelName: model.name, images: model.images.map(\.url))
    }

    func destinationOptions() throws -> (models: [CorpusVaultModelChoice], groups: [CorpusVaultGroupChoice]) {
        let root = try corpusRoot()
        let models = try loadModels(root: root).compactMap { payload -> CorpusVaultModelChoice? in
            guard let id = payload["id"] as? String else { return nil }
            let fallbackName = ((payload["profile"] as? [String: Any])?["objective"] as? [String: Any])?["name"] as? String
            let name = payload["name"] as? String ?? fallbackName ?? id
            return CorpusVaultModelChoice(id: id, name: name)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let groups = try loadGroups(root: root).map {
            CorpusVaultGroupChoice(id: $0.id, name: $0.name, folder: $0.folder)
        }
        return (models, groups)
    }

    func appendImages(_ images: [ImageAsset], toModelID modelID: String, groupID: String) throws -> URL {
        try appendImages(images.map(\.url), toModelID: modelID, groupID: groupID)
    }

    private func export(modelName: String, images: [URL]) throws -> URL {
        guard !images.isEmpty else { throw CorpusVaultExportError.noImages }
        let root = try corpusRoot()
        let env = Self.loadCorpusEnv()
        let groups = try loadGroups(root: root)
        guard let intakeGroup = intakeGroup(from: groups, env: env) else {
            throw CorpusVaultExportError.invalidCorpusRoot(root)
        }

        var models = try loadModels(root: root)
        let now = Self.isoNow()
        let modelID = "mdl_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10))"
        let groupFolder = sanitizeFolderName(intakeGroup.folder.isEmpty ? intakeGroup.name : intakeGroup.folder)
        let destinationDir = root
            .appendingPathComponent("photos")
            .appendingPathComponent(modelID)
            .appendingPathComponent(groupFolder)
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        var relativePaths: [String] = []
        for url in images {
            let filename = uniqueFilename(url.lastPathComponent, in: destinationDir)
            let destination = destinationDir.appendingPathComponent(filename)
            try fileManager.copyItem(at: url, to: destination)
            relativePaths.append("photos/\(modelID)/\(groupFolder)/\(filename)")
        }

        let model = Self.makeModelPayload(
            id: modelID,
            name: modelName,
            groupID: intakeGroup.id,
            relativePaths: relativePaths,
            timestamp: now
        )
        models.append(model)
        try saveModels(models, root: root)
        return root
    }

    private func appendImages(_ images: [URL], toModelID modelID: String, groupID: String) throws -> URL {
        guard !images.isEmpty else { throw CorpusVaultExportError.noImages }
        let root = try corpusRoot()
        let groups = try loadGroups(root: root)
        guard let group = groups.first(where: { $0.id == groupID }) else {
            throw CorpusVaultExportError.missingDestination
        }

        var models = try loadModels(root: root)
        guard let modelIndex = models.firstIndex(where: { ($0["id"] as? String) == modelID }) else {
            throw CorpusVaultExportError.missingDestination
        }

        let groupFolder = sanitizeFolderName(group.folder.isEmpty ? group.name : group.folder)
        let destinationDir = root
            .appendingPathComponent("photos")
            .appendingPathComponent(modelID)
            .appendingPathComponent(groupFolder)
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        var relativePaths: [String] = []
        for url in images {
            let filename = uniqueFilename(url.lastPathComponent, in: destinationDir)
            let destination = destinationDir.appendingPathComponent(filename)
            try fileManager.copyItem(at: url, to: destination)
            relativePaths.append("photos/\(modelID)/\(groupFolder)/\(filename)")
        }

        var model = models[modelIndex]
        var photos = model["photos"] as? [String: Any] ?? [:]
        var existingPaths = photos[groupID] as? [String] ?? []
        existingPaths.append(contentsOf: relativePaths)
        photos[groupID] = existingPaths
        model["photos"] = photos
        model["updated_at"] = Self.isoNow()
        models[modelIndex] = model

        try saveModels(models, root: root)
        return root
    }

    private func corpusRoot() throws -> URL {
        let envRoot = Self.loadCorpusEnv()["CORPUSVAULT_ROOT"]
        let candidates = [
            envRoot.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) },
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/corpus")
        ].compactMap { $0 }

        guard let root = candidates.first(where: isCorpusRoot) else {
            throw CorpusVaultExportError.missingCorpusRoot
        }
        return root
    }

    private func isCorpusRoot(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent("data/models.json").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("data/groups.json").path)
    }

    private func loadGroups(root: URL) throws -> [CorpusGroup] {
        let data = try Data(contentsOf: root.appendingPathComponent("data/groups.json"))
        return try JSONDecoder().decode([CorpusGroup].self, from: data)
    }

    private func intakeGroup(from groups: [CorpusGroup], env: [String: String]) -> CorpusGroup? {
        if let id = env["CORPUSVAULT_IMPORT_GROUP_ID"], let group = groups.first(where: { $0.id == id }) {
            return group
        }
        if let name = env["CORPUSVAULT_IMPORT_GROUP_NAME"], let group = groups.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
                || $0.folder.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return group
        }
        return groups.first
    }

    private func loadModels(root: URL) throws -> [[String: Any]] {
        let data = try Data(contentsOf: root.appendingPathComponent("data/models.json"))
        guard let models = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CorpusVaultExportError.modelWriteFailed
        }
        return models
    }

    private func saveModels(_ models: [[String: Any]], root: URL) throws {
        guard JSONSerialization.isValidJSONObject(models) else {
            throw CorpusVaultExportError.modelWriteFailed
        }
        let data = try JSONSerialization.data(withJSONObject: models, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("data/models.json"), options: .atomic)
    }

    private static func makeModelPayload(
        id: String,
        name: String,
        groupID: String,
        relativePaths: [String],
        timestamp: String
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "profile": [
                "schema_version": 2,
                "objective": [
                    "name": name,
                    "age": "",
                    "height_cm": "",
                    "weight_kg": "",
                    "body_type": "",
                    "notes": "",
                    "appearance": [
                        "face_shape": "",
                        "hair": "",
                        "skin_color": "",
                        "facial_hair": "",
                        "tattoos_piercings_scars": "",
                        "overall_vibe": "",
                        "other": ""
                    ],
                    "penis": [
                        "visible_erect_length": "",
                        "thickness": "",
                        "shape": "",
                        "circumcision": "",
                        "color": "",
                        "vein_prominence": "",
                        "balls_position_size": "",
                        "other_visible_details": ""
                    ],
                    "other_body": [
                        "ass_shape": "",
                        "leg_lines": "",
                        "body_proportions": "",
                        "skin_texture": "",
                        "other_observable": ""
                    ]
                ],
                "ai_erotic": [
                    "enabled": false,
                    "cock_detail_touch": "",
                    "personality_play_style": "",
                    "unique_selling_points": "",
                    "client_reactions": "",
                    "sensory_details": "",
                    "generated_at": ""
                ]
            ],
            "photos": [
                groupID: relativePaths
            ],
            "created_at": timestamp,
            "updated_at": timestamp
        ]
    }

    private func uniqueFilename(_ filename: String, in directory: URL) -> String {
        let safe = sanitizeFilename(filename.isEmpty ? "image.jpg" : filename)
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension.isEmpty ? "jpg" : (safe as NSString).pathExtension
        var candidate = "\(base).\(ext)"
        var index = 1
        while fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = "\(base)-\(index).\(ext)"
            index += 1
        }
        return candidate
    }

    private func sanitizeFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    private func sanitizeFolderName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitizeFilename(trimmed.isEmpty ? "Intake" : trimmed)
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func loadCorpusEnv() -> [String: String] {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".corpusvault/corpus.env")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let comment = value.firstIndex(of: "#") {
                value = String(value[..<comment]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty, !value.isEmpty {
                values[key] = value
            }
        }
        return values
    }
}

private struct CorpusGroup: Codable {
    var id: String
    var name: String
    var folder: String
    var maxPhotos: Int?
    var description: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, folder, description
        case maxPhotos = "max_photos"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CorpusModel: Codable {
    var id: String
    var name: String
    var profile: CorpusProfile
    var photos: [String: [String]]
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, profile, photos
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct CorpusProfile: Codable {
    var objective: CorpusObjective
    var aiErotic: CorpusAI
    var schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case objective
        case aiErotic = "ai_erotic"
        case schemaVersion = "schema_version"
    }

    init(name: String) {
        objective = CorpusObjective(name: name)
        aiErotic = CorpusAI()
        schemaVersion = 2
    }
}

private struct CorpusObjective: Codable {
    var name: String
    var age = ""
    var heightCm = ""
    var weightKg = ""
    var bodyType = ""
    var notes = ""
    var appearance = CorpusAppearance()
    var penis = CorpusPenis()
    var otherBody = CorpusOtherBody()

    enum CodingKeys: String, CodingKey {
        case name, age, notes, appearance, penis
        case heightCm = "height_cm"
        case weightKg = "weight_kg"
        case bodyType = "body_type"
        case otherBody = "other_body"
    }
}

private struct CorpusAppearance: Codable {
    var faceShape = ""
    var hair = ""
    var skinColor = ""
    var facialHair = ""
    var tattoosPiercingsScars = ""
    var overallVibe = ""
    var other = ""

    enum CodingKeys: String, CodingKey {
        case hair, other
        case faceShape = "face_shape"
        case skinColor = "skin_color"
        case facialHair = "facial_hair"
        case tattoosPiercingsScars = "tattoos_piercings_scars"
        case overallVibe = "overall_vibe"
    }
}

private struct CorpusPenis: Codable {
    var visibleErectLength = ""
    var thickness = ""
    var shape = ""
    var circumcision = ""
    var color = ""
    var veinProminence = ""
    var ballsPositionSize = ""
    var otherVisibleDetails = ""

    enum CodingKeys: String, CodingKey {
        case thickness, shape, circumcision, color
        case visibleErectLength = "visible_erect_length"
        case veinProminence = "vein_prominence"
        case ballsPositionSize = "balls_position_size"
        case otherVisibleDetails = "other_visible_details"
    }
}

private struct CorpusOtherBody: Codable {
    var assShape = ""
    var legLines = ""
    var bodyProportions = ""
    var skinTexture = ""
    var otherObservable = ""

    enum CodingKeys: String, CodingKey {
        case assShape = "ass_shape"
        case legLines = "leg_lines"
        case bodyProportions = "body_proportions"
        case skinTexture = "skin_texture"
        case otherObservable = "other_observable"
    }
}

private struct CorpusAI: Codable {
    var enabled = false
    var cockDetailTouch = ""
    var personalityPlayStyle = ""
    var uniqueSellingPoints = ""
    var clientReactions = ""
    var sensoryDetails = ""
    var generatedAt = ""

    enum CodingKeys: String, CodingKey {
        case enabled
        case cockDetailTouch = "cock_detail_touch"
        case personalityPlayStyle = "personality_play_style"
        case uniqueSellingPoints = "unique_selling_points"
        case clientReactions = "client_reactions"
        case sensoryDetails = "sensory_details"
        case generatedAt = "generated_at"
    }
}
