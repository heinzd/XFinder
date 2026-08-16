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
            guard matchesName(name, query: needle) else { continue }
            results.append(makeItem(for: url, values: values))
        }

        return results.sorted {
            $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }
    }

    func requiresExecutionConfirmation(for item: FileItem) -> Bool {
        guard !item.isDirectory, !item.isPackage else { return false }

        let scriptExtensions: Set<String> = [
            "awk", "bash", "command", "csh", "fish", "js", "ksh", "php",
            "pl", "pm", "py", "pyw", "rb", "sh", "swift", "tcl", "tcsh", "zsh"
        ]
        if scriptExtensions.contains(item.url.pathExtension.lowercased()) {
            return true
        }
        if fileManager.isExecutableFile(atPath: item.url.path) {
            return true
        }

        guard let handle = try? FileHandle(forReadingFrom: item.url) else { return false }
        defer { try? handle.close() }
        let prefix = try? handle.read(upToCount: 2)
        return prefix == Data([0x23, 0x21])
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
            guard standardizedURL.path.hasPrefix("/Volumes/") else { return nil }
            let values = try? standardizedURL.resourceValues(forKeys: keys)
            guard values?.isDirectory == true else { return nil }
            guard values?.volumeIsInternal == false else { return nil }
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

    func finderFavoriteURLs() -> [URL] {
        let sharedFileListFolder = URL.homeDirectory
            .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist", isDirectory: true)

        guard let files = try? fileManager.contentsOfDirectory(
            at: sharedFileListFolder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let favoriteFiles = files.filter {
            $0.lastPathComponent.hasPrefix("com.apple.LSSharedFileList.FavoriteItems.sfl")
        }
        var results: [URL] = []

        for file in favoriteFiles {
            guard let data = try? Data(contentsOf: file),
                  let propertyList = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                  ) else { continue }
            collectFileURLs(from: propertyList, into: &results)
        }

        var seen = Set<String>()
        return results.filter { url in
            let standardizedURL = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return false }
            return seen.insert(standardizedURL.path).inserted
        }
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

    func createFile(in directory: URL, kind: NewFileKind, baseName: String) throws -> URL {
        var candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(kind.pathExtension)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory
                .appendingPathComponent("\(baseName) \(suffix)")
                .appendingPathExtension(kind.pathExtension)
            suffix += 1
        }

        switch kind {
        case .text:
            try Data().write(to: candidate, options: .atomic)
        case .richText:
            try Data("{\\rtf1\\ansi\\deff0\\n}".utf8).write(to: candidate, options: .atomic)
        case .word, .excel, .powerpoint:
            guard let templateURL = Bundle.main.url(
                forResource: "Blank",
                withExtension: kind.pathExtension
            ) else {
                throw FileSystemError.missingTemplate(kind.pathExtension)
            }
            try fileManager.copyItem(at: templateURL, to: candidate)
        }
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

    private func matchesName(_ name: String, query: String) -> Bool {
        guard query.contains("*") || query.contains("?") else {
            return name.localizedCaseInsensitiveContains(query)
        }
        return wildcardMatch(name, pattern: query)
    }

    private func wildcardMatch(_ name: String, pattern: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let nameCharacters = Array(name.folding(options: options, locale: .current))
        let patternCharacters = Array(pattern.folding(options: options, locale: .current))
        var previous = [Bool](repeating: false, count: nameCharacters.count + 1)
        previous[0] = true

        for patternCharacter in patternCharacters {
            var current = [Bool](repeating: false, count: nameCharacters.count + 1)
            if patternCharacter == "*" {
                current[0] = previous[0]
            }

            for index in 1..<current.count {
                switch patternCharacter {
                case "*":
                    current[index] = previous[index] || current[index - 1]
                case "?":
                    current[index] = previous[index - 1]
                default:
                    current[index] = previous[index - 1]
                        && patternCharacter == nameCharacters[index - 1]
                }
            }
            previous = current
        }

        return previous[nameCharacters.count]
    }

    private func collectFileURLs(from value: Any, into results: inout [URL]) {
        if let data = value as? Data {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), url.isFileURL {
                results.append(url)
            }
            return
        }

        if let string = value as? String,
           string.hasPrefix("file://"),
           let url = URL(string: string) {
            results.append(url)
            return
        }

        if let array = value as? [Any] {
            for item in array {
                collectFileURLs(from: item, into: &results)
            }
            return
        }

        if let dictionary = value as? [AnyHashable: Any] {
            for item in dictionary.values {
                collectFileURLs(from: item, into: &results)
            }
        }
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
    case missingTemplate(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The name must not be empty or contain a slash."
        case .itemAlreadyExists(let name):
            return "An item named “\(name)” already exists."
        case .missingTemplate(let pathExtension):
            return "The template for .\(pathExtension) files is missing."
        }
    }
}
