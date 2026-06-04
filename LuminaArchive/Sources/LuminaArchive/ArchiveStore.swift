import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

final class FolderNode: NSObject {
    let url: URL
    weak var parent: FolderNode?
    private(set) var children: [FolderNode] = []
    private var didLoadChildren = false

    init(url: URL, parent: FolderNode? = nil) {
        self.url = url.standardizedFileURL
        self.parent = parent
    }

    var name: String {
        url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    func loadChildren() {
        guard !didLoadChildren else { return }
        didLoadChildren = true
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]
        ) else {
            children = []
            return
        }

        children = items.compactMap { childURL in
            let values = try? childURL.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            guard values?.isDirectory == true, values?.isPackage != true else { return nil }
            return FolderNode(url: childURL, parent: self)
        }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

final class ArchiveStore {
    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "webp",
        "bmp", "jp2", "cr2", "cr3", "nef", "arw", "raf", "rw2", "dng"
    ]

    func scan(_ root: URL) -> [ModelFolder] {
        let root = root.standardizedFileURL
        if isModelFolder(root) || containsImages(root) {
            return [makeModelFolder(root)]
        }

        let children = immediateDirectories(root)
        let modelFolders = children
            .filter { isModelFolder($0) || containsImages($0) }
            .map(makeModelFolder)
            .filter { !$0.images.isEmpty || $0.profileURL != nil }

        if modelFolders.isEmpty {
            return [makeModelFolder(root)].filter { !$0.images.isEmpty || $0.profileURL != nil }
        }

        return modelFolders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func isModelFolder(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent("profile.md").path)
    }

    private func containsImages(_ url: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return items.contains { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    private func immediateDirectories(_ url: URL) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func makeModelFolder(_ url: URL) -> ModelFolder {
        let profile = url.appendingPathComponent("profile.md")
        let profileURL = FileManager.default.fileExists(atPath: profile.path) ? profile : nil
        return ModelFolder(
            url: url,
            name: url.lastPathComponent,
            profileURL: profileURL,
            images: imageAssets(in: url)
        )
    }

    private func imageAssets(in url: URL) -> [ImageAsset] {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var assets: [ImageAsset] = []
        for case let fileURL as URL in enumerator {
            guard imageExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            assets.append(ImageAsset(
                url: fileURL,
                name: fileURL.deletingPathExtension().lastPathComponent,
                byteCount: Int64(values?.fileSize ?? 0)
            ))
        }

        return assets.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }
}
