import Combine
import Foundation

struct NetworkServerEndpoint: Identifiable, Hashable, Sendable {
    let name: String
    let connectionURL: URL?

    var id: String { name.localizedLowercase }
}

/// Discovers file servers Finder shows below its Network node, including servers
/// that currently have no mounted share.
@MainActor
final class NetworkServerDiscovery: NSObject, ObservableObject,
                                    @preconcurrency NetServiceBrowserDelegate,
                                    @preconcurrency NetServiceDelegate {
    static let shared = NetworkServerDiscovery()

    @Published private(set) var servers: [NetworkServerEndpoint] = []

    private let browsers = [NetServiceBrowser(), NetServiceBrowser()]
    private var services: [ObjectIdentifier: NetService] = [:]

    private override init() {
        super.init()
        for browser in browsers { browser.delegate = self }
        browsers[0].searchForServices(ofType: "_smb._tcp.", inDomain: "local.")
        browsers[1].searchForServices(ofType: "_afpovertcp._tcp.", inDomain: "local.")
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        services[ObjectIdentifier(service)] = service
        service.delegate = self
        service.resolve(withTimeout: 5)
        if !moreComing { rebuildServers() }
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        services.removeValue(forKey: ObjectIdentifier(service))
        if !moreComing { rebuildServers() }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        rebuildServers()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Keep the discovered name visible. A later mount notification will add
        // shares even when hostname resolution was temporarily unavailable.
        rebuildServers()
    }

    private func rebuildServers() {
        var byName: [String: NetworkServerEndpoint] = [:]
        for service in services.values {
            let name = service.name
            guard !name.isEmpty else { continue }
            let host = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let scheme = service.type.lowercased().contains("smb") ? "smb" : "afp"
            let connectionURL = host.flatMap { host in
                var components = URLComponents()
                components.scheme = scheme
                components.host = host
                return components.url
            }
            let key = name.localizedLowercase
            let existing = byName[key]
            byName[key] = NetworkServerEndpoint(
                name: name,
                connectionURL: existing?.connectionURL ?? connectionURL
            )
        }
        servers = byName.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

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

    /// Breadth-first traversal: direct songs first, then each folder's songs
    /// together, with sibling folders and filenames in natural order.
    func mp3PlaylistItems(in root: URL, showHiddenFiles: Bool) throws -> [FileItem] {
        var pending = [root.standardizedFileURL]
        var nextDirectory = 0
        var result: [FileItem] = []
        let keys = itemResourceKeys.union([.isSymbolicLinkKey])
        let options: FileManager.DirectoryEnumerationOptions = showHiddenFiles ? [] : [.skipsHiddenFiles]

        while nextDirectory < pending.count {
            try Task.checkCancellation()
            let directory = pending[nextDirectory]
            nextDirectory += 1
            let children: [URL]
            do {
                children = try fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: options
                ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            } catch {
                if directory == root.standardizedFileURL { throw error }
                continue
            }
            for url in children {
                try Task.checkCancellation()
                guard let values = try? url.resourceValues(forKeys: keys) else { continue }
                if !showHiddenFiles, values.isHidden == true { continue }
                if values.isDirectory == true {
                    // Avoid packages and symlink cycles or paths outside the chosen tree.
                    if values.isPackage != true, values.isSymbolicLink != true {
                        pending.append(url)
                    }
                } else if url.pathExtension.caseInsensitiveCompare("mp3") == .orderedSame {
                    result.append(makeItem(for: url, values: values))
                }
            }
        }
        return result
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
            .volumeURLForRemountingKey,
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
            // The remount URL is the authoritative network-volume signal and also
            // carries the SMB/AFP/NFS server name. Some providers report conflicting
            // volumeIsLocal/volumeIsInternal values for the mounted path.
            let remountURL = values?.volumeURLForRemounting
            let isNetworkVolume = remountURL != nil || values?.volumeIsLocal == false
            guard isNetworkVolume || values?.volumeIsInternal != true else { return nil }
            let systemImage: String
            if isNetworkVolume {
                systemImage = "network"
            } else if values?.volumeIsRemovable == true || values?.volumeIsEjectable == true {
                systemImage = "externaldrive"
            } else {
                systemImage = "externaldrive"
            }
            return SidebarLocation(
                title: values?.volumeLocalizedName ?? standardizedURL.lastPathComponent,
                systemImage: systemImage,
                url: standardizedURL,
                networkServer: isNetworkVolume ? networkServerName(from: remountURL) : nil
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func networkServerName(from remountURL: URL?) -> String? {
        guard var host = remountURL?.host, !host.isEmpty else { return nil }
        // Bonjour SMB hosts commonly look like DiskStation._smb._tcp.local.
        if let serviceMarker = host.range(of: "._") {
            host = String(host[..<serviceMarker.lowerBound])
        } else if host.lowercased().hasSuffix(".local") {
            host.removeLast(".local".count)
        }
        return host.removingPercentEncoding ?? host
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
        case .openDocumentText, .openDocumentSpreadsheet, .openDocumentPresentation:
            guard let encodedTemplate = Self.openDocumentTemplates[kind],
                  let templateData = Data(base64Encoded: encodedTemplate) else {
                throw FileSystemError.missingTemplate(kind.pathExtension)
            }
            try templateData.write(to: candidate, options: .atomic)
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

    func copyItems(_ sourceURLs: [URL], to directory: URL) throws -> [URL] {
        let destinationDirectory = directory.standardizedFileURL
        var copiedURLs: [URL] = []

        for sourceURL in sourceURLs {
            let source = sourceURL.standardizedFileURL
            let sourceDirectory = source.deletingLastPathComponent().resolvingSymlinksInPath()
            if sourceDirectory == destinationDirectory.resolvingSymlinksInPath() {
                continue
            }
            let sourcePrefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
            guard destinationDirectory.path != source.path,
                  !destinationDirectory.path.hasPrefix(sourcePrefix) else {
                throw FileSystemError.cannotCopyIntoItself(source.lastPathComponent)
            }

            let destination = availableCopyURL(for: source, in: destinationDirectory)
            try fileManager.copyItem(at: source, to: destination)
            copiedURLs.append(destination)
        }

        return copiedURLs
    }

    func moveItems(_ sourceURLs: [URL], to directory: URL) throws -> [URL] {
        let destinationDirectory = directory.standardizedFileURL
        let sources = topLevelUniqueURLs(sourceURLs)

        for source in sources where !fileManager.fileExists(atPath: source.path) {
            throw FileSystemError.itemNoLongerExists(source.lastPathComponent)
        }

        var movedURLs: [URL] = []
        for source in sources {
            let destination = availableCopyURL(for: source, in: destinationDirectory)
            try fileManager.moveItem(at: source, to: destination)
            movedURLs.append(destination)
        }
        return movedURLs
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

    private func availableCopyURL(for source: URL, in directory: URL) -> URL {
        let initialDestination = directory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: initialDestination.path) else {
            return initialDestination
        }

        let values = try? source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let preservesExtension = values?.isDirectory != true || values?.isPackage == true
        let pathExtension = preservesExtension ? source.pathExtension : ""
        let baseName = pathExtension.isEmpty
            ? source.lastPathComponent
            : source.deletingPathExtension().lastPathComponent
        var copyNumber = 1

        while true {
            let suffix = copyNumber == 1 ? " copy" : " copy \(copyNumber)"
            var candidate = directory.appendingPathComponent(baseName + suffix)
            if !pathExtension.isEmpty {
                candidate.appendPathExtension(pathExtension)
            }
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            copyNumber += 1
        }
    }

    private func topLevelUniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        let uniqueURLs = urls
            .map(\.standardizedFileURL)
            .filter { seen.insert($0).inserted }

        return uniqueURLs.filter { candidate in
            !uniqueURLs.contains { possibleParent in
                guard possibleParent != candidate else { return false }
                let parentPrefix = possibleParent.path.hasSuffix("/")
                    ? possibleParent.path
                    : possibleParent.path + "/"
                return candidate.path.hasPrefix(parentPrefix)
            }
        }
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

    private static let openDocumentTemplates: [NewFileKind: String] = [
        .openDocumentText: "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",
        .openDocumentSpreadsheet: "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",
        .openDocumentPresentation: "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"
    ]
}

enum FileSystemError: LocalizedError {
    case invalidName
    case itemAlreadyExists(String)
    case missingTemplate(String)
    case cannotCopyIntoItself(String)
    case itemNoLongerExists(String)

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "The name must not be empty or contain a slash."
        case .itemAlreadyExists(let name):
            return "An item named “\(name)” already exists."
        case .missingTemplate(let pathExtension):
            return "The template for .\(pathExtension) files is missing."
        case .cannotCopyIntoItself(let name):
            return "“\(name)” cannot be copied into itself."
        case .itemNoLongerExists(let name):
            return "“\(name)” no longer exists. Reload the folder and try again."
        }
    }
}
