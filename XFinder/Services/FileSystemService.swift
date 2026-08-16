import Foundation

struct FileSystemService {
    private let fileManager = FileManager.default

    private var itemResourceKeys: Set<URLResourceKey> {
        [
            .nameKey,
            .isDirectoryKey,
            .isPackageKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey
        ]
    }

    func contents(of directory: URL, showHiddenFiles: Bool) throws -> [FileItem] {
        let keys = itemResourceKeys
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: options
        )

        return try urls.map { try makeItem(for: $0, keys: keys) }
        .sorted {
            if $0.canNavigateInto != $1.canNavigateInto {
                return $0.canNavigateInto
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func search(
        in root: URL,
        matching query: String,
        showHiddenFiles: Bool
    ) throws -> [FileItem] {
        let keys = itemResourceKeys
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !showHiddenFiles {
            options.insert(.skipsHiddenFiles)
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [FileItem] = []

        for case let url as URL in enumerator {
            try Task.checkCancellation()

            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if !showHiddenFiles, values.isHidden == true {
                if values.isDirectory == true { enumerator.skipDescendants() }
                continue
            }

            let name = values.name ?? url.lastPathComponent
            guard name.localizedCaseInsensitiveContains(needle) else { continue }
            results.append(makeItem(for: url, values: values))
        }

        return results.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    func mountedVolumes() -> [SidebarLocation] {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey,
            .volumeIsLocalKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .isDirectoryKey
        ]
        var urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: []
        ) ?? []

        let volumesFolder = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if let additionalURLs = try? fileManager.contentsOfDirectory(
            at: volumesFolder,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) {
            urls.append(contentsOf: additionalURLs)
        }

        var seenPaths = Set<String>()

        return urls.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else { return nil }
            let values = try? standardizedURL.resourceValues(forKeys: keys)
            guard values?.isDirectory == true else { return nil }
            guard values?.volumeIsInternal != true else { return nil }
            let systemImage: String
            if values?.volumeIsLocal == false {
                systemImage = "network"
            } else if values?.volumeIsRemovable == true || values?.volumeIsEjectable == true {
                systemImage = "externaldrive"
            } else {
                systemImage = "externaldrive"
            }
            return SidebarLocation(
                title: values?.volumeLocalizedName ?? standardizedURL.lastPathComponent,
                systemImage: systemImage,
                url: standardizedURL
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func createFolder(in directory: URL, baseName: String) throws -> URL {
        var candidate = directory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }
        try fileManager.createDirectory(at: candidate, withIntermediateDirectories: false)
        return candidate
    }

    func rename(_ item: FileItem, to newName: String) throws -> URL {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanName.contains("/") else {
            throw FileSystemError.invalidName
        }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(cleanName)
        guard destination != item.url else { return item.url }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileSystemError.itemAlreadyExists(cleanName)
        }
        try fileManager.moveItem(at: item.url, to: destination)
        return destination
    }

    func moveToTrash(_ item: FileItem) throws {
        var resultingURL: NSURL?
        try fileManager.trashItem(at: item.url, resultingItemURL: &resultingURL)
    }

    private func makeItem(for url: URL, keys: Set<URLResourceKey>) throws -> FileItem {
        let values = try url.resourceValues(forKeys: keys)
        return makeItem(for: url, values: values)
    }

    private func makeItem(for url: URL, values: URLResourceValues) -> FileItem {
        let isDirectory = values.isDirectory ?? false
        return FileItem(
            url: url,
            name: values.name ?? url.lastPathComponent,
            isDirectory: isDirectory,
            isPackage: values.isPackage ?? false,
            isHidden: values.isHidden ?? false,
            size: values.fileSize.map(Int64.init),
            modificationDate: values.contentModificationDate,
            kind: values.localizedTypeDescription ?? "File"
        )
    }
}

enum FileSystemError: LocalizedError {
    case invalidName
    case itemAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The name must not be empty or contain a slash."
        case .itemAlreadyExists(let name):
            return "An item named “\(name)” already exists."
        }
    }
}
