import AppKit
import Foundation
@preconcurrency import ImageCaptureCore

private struct ConnectedMediaDevice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String

    var systemImage: String {
        if name.localizedCaseInsensitiveContains("iphone") {
            return "iphone"
        }
        if name.localizedCaseInsensitiveContains("ipad") {
            return "ipad"
        }
        return "camera"
    }
}

@MainActor
private final class ConnectedDeviceMonitor: NSObject, @preconcurrency ICDeviceBrowserDelegate {
    private let browser = ICDeviceBrowser()
    private var devices: [ObjectIdentifier: ConnectedMediaDevice] = [:]
    private let didChange: ([ConnectedMediaDevice]) -> Void

    init(didChange: @escaping ([ConnectedMediaDevice]) -> Void) {
        self.didChange = didChange
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue
                | ICDeviceLocationTypeMask.local.rawValue
        )!
        browser.start()
    }

    func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didAdd device: ICDevice,
        moreComing: Bool
    ) {
        let fallbackID = String(ObjectIdentifier(device).hashValue)
        let identifier = (device.uuidString as String?) ?? fallbackID
        let detectedName = (device.name as String?)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = detectedName.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Connected Device"
        devices[ObjectIdentifier(device)] = ConnectedMediaDevice(id: identifier, name: name)
        publishDevices()
    }

    func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didRemove device: ICDevice,
        moreGoing: Bool
    ) {
        devices.removeValue(forKey: ObjectIdentifier(device))
        publishDevices()
    }

    private func publishDevices() {
        didChange(
            devices.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        )
    }
}

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var volumes: [SidebarLocation] = []
    @Published private(set) var finderFavoriteURLs: [URL] = []
    @Published private(set) var searchResults: [FileItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var activeSearchQuery = ""
    @Published private(set) var customFavoriteURLs: [URL] = []
    @Published private var connectedDevices: [ConnectedMediaDevice] = []
    @Published var selectedItemIDs: Set<FileItem.ID> = []
    @Published var errorMessage: String?
    @Published var renameTarget: FileItem?
    @Published var pendingExecutionItem: FileItem?
    @Published var isShowingSettings = false
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        }
    }
    @Published var showHiddenFiles: Bool {
        didSet {
            UserDefaults.standard.set(showHiddenFiles, forKey: Self.hiddenFilesKey)
            reload()
        }
    }

    private let fileSystem = FileSystemService()
    private var history: [URL]
    private var historyIndex = 0
    private var searchTask: Task<Void, Never>?
    private var deviceMonitor: ConnectedDeviceMonitor?
    private static let hiddenFilesKey = "showHiddenFiles"
    private static let languageKey = "appLanguage"
    private static let customFavoritesKey = "customFavoritePaths"

    init(startURL: URL = .homeDirectory) {
        currentURL = startURL.standardizedFileURL
        history = [startURL.standardizedFileURL]
        language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: Self.languageKey) ?? ""
        ) ?? .english
        showHiddenFiles = UserDefaults.standard.bool(forKey: Self.hiddenFilesKey)
        customFavoriteURLs = UserDefaults.standard
            .stringArray(forKey: Self.customFavoritesKey)?
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL } ?? []
        deviceMonitor = ConnectedDeviceMonitor { [weak self] devices in
            self?.connectedDevices = devices
        }
        reload()
    }

    var favorites: [SidebarLocation] {
        let home = URL.homeDirectory
        var locations = [
            SidebarLocation(title: text("Home"), systemImage: "house", url: home),
            SidebarLocation(title: text("Desktop"), systemImage: "menubar.dock.rectangle", url: home.appendingPathComponent("Desktop", isDirectory: true)),
            SidebarLocation(title: text("Documents"), systemImage: "doc", url: home.appendingPathComponent("Documents", isDirectory: true)),
            SidebarLocation(title: text("Downloads"), systemImage: "arrow.down.circle", url: home.appendingPathComponent("Downloads", isDirectory: true)),
            SidebarLocation(title: text("Pictures"), systemImage: "photo", url: home.appendingPathComponent("Pictures", isDirectory: true)),
            SidebarLocation(title: text("Music"), systemImage: "music.note", url: home.appendingPathComponent("Music", isDirectory: true)),
            SidebarLocation(title: text("Movies"), systemImage: "film", url: home.appendingPathComponent("Movies", isDirectory: true)),
            SidebarLocation(title: text("Applications"), systemImage: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications", isDirectory: true))
        ]

        let standardPaths = Set(locations.map { $0.url.standardizedFileURL.path })
        locations.append(contentsOf: finderFavoriteURLs.compactMap { url in
            let standardizedURL = url.standardizedFileURL
            guard !standardPaths.contains(standardizedURL.path) else { return nil }
            return SidebarLocation(
                title: standardizedURL.path == "/" ? "Macintosh HD" : standardizedURL.lastPathComponent,
                systemImage: "folder",
                url: standardizedURL
            )
        })
        return locations
    }

    var locations: [SidebarLocation] {
        let home = URL.homeDirectory
        var locations: [SidebarLocation] = []

        if let airDropURL = URL(string: "airdrop://") {
            locations.append(
                SidebarLocation(
                    title: "AirDrop",
                    systemImage: "airdrop",
                    url: airDropURL,
                    opensExternally: true
                )
            )
        }

        locations.append(
            SidebarLocation(
                title: text("iCloud Drive"),
                systemImage: "icloud",
                url: home.appendingPathComponent(
                    "Library/Mobile Documents/com~apple~CloudDocs",
                    isDirectory: true
                )
            )
        )

        locations.append(
            SidebarLocation(
                title: text("Trash"),
                systemImage: "trash",
                url: home.appendingPathComponent(".Trash", isDirectory: true)
            )
        )

        locations.append(contentsOf: connectedDevices.compactMap { device in
            guard let url = URL(string: "xfinder-device:/\(device.id)") else { return nil }
            return SidebarLocation(
                title: device.name == "Connected Device" ? text(device.name) : device.name,
                systemImage: device.systemImage,
                url: url,
                opensExternally: true
            )
        })

        locations.append(contentsOf: volumes)

        var seen = Set<URL>()
        return locations.filter { seen.insert($0.id).inserted }
    }

    var customFavorites: [SidebarLocation] {
        customFavoriteURLs.map { url in
            SidebarLocation(
                title: url.path == "/" ? "Macintosh HD" : url.lastPathComponent,
                systemImage: "folder",
                url: url,
                isCustom: true
            )
        }
    }

    var selectedItem: FileItem? {
        guard selectedItemIDs.count == 1, let selectedItemID = selectedItemIDs.first else { return nil }
        return item(withID: selectedItemID)
    }

    var selectedItems: [FileItem] {
        selectedItemIDs.compactMap { item(withID: $0) }
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex + 1 < history.count }

    func displayedItems(matching query: String) -> [FileItem] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return items }
        return searchResults
    }

    func item(withID id: FileItem.ID) -> FileItem? {
        searchResults.first(where: { $0.id == id })
            ?? items.first(where: { $0.id == id })
    }

    func searchRecursively(matching query: String) {
        searchTask?.cancel()
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        activeSearchQuery = cleanQuery
        guard !cleanQuery.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }

        let root = currentURL
        let includesHiddenFiles = showHiddenFiles
        isSearching = true
        searchResults = []

        searchTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                let results = try await withThrowingTaskGroup(
                    of: [FileItem].self,
                    returning: [FileItem].self
                ) { group in
                    group.addTask(priority: .userInitiated) {
                        try FileSystemService().search(
                            in: root,
                            matching: cleanQuery,
                            showHiddenFiles: includesHiddenFiles
                        )
                    }
                    return try await group.next() ?? []
                }

                guard !Task.isCancelled, currentURL == root else { return }
                searchResults = results
                isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                isSearching = false
                present(error)
            }
        }
    }

    func relativeLocation(for item: FileItem) -> String {
        let parent = item.url.deletingLastPathComponent().standardizedFileURL
        if parent == currentURL.standardizedFileURL {
            return text("This Folder")
        }
        let rootPath = currentURL.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        if parent.path.hasPrefix(prefix) {
            return String(parent.path.dropFirst(prefix.count))
        }
        return parent.path
    }

    func addCurrentFolderToFavorites() {
        addFavorite(currentURL)
    }

    func addSelectionToFavorites() {
        guard let item = selectedItem, item.canNavigateInto else { return }
        addFavorite(item.url)
    }

    private func addFavorite(_ favoriteURL: URL) {
        let url = favoriteURL.standardizedFileURL
        guard !favorites.contains(where: { $0.url.standardizedFileURL == url }),
              !customFavoriteURLs.contains(where: { $0.standardizedFileURL == url }) else { return }
        customFavoriteURLs.append(url)
        persistCustomFavorites()
    }

    func removeFavorite(_ location: SidebarLocation) {
        guard location.isCustom else { return }
        customFavoriteURLs.removeAll { $0.standardizedFileURL == location.url.standardizedFileURL }
        persistCustomFavorites()
    }

    func reload() {
        do {
            items = try fileSystem.contents(of: currentURL, showHiddenFiles: showHiddenFiles)
            volumes = fileSystem.mountedVolumes()
            finderFavoriteURLs = fileSystem.finderFavoriteURLs()
            let availableIDs = Set(items.map(\.id))
            if activeSearchQuery.isEmpty {
                selectedItemIDs.formIntersection(availableIDs)
            }
            if !activeSearchQuery.isEmpty {
                searchRecursively(matching: activeSearchQuery)
            }
        } catch {
            items = []
            selectedItemIDs.removeAll()
            present(error)
        }
    }

    func reloadVolumes() {
        volumes = fileSystem.mountedVolumes()
    }

    func navigate(to url: URL) {
        let destination = url.standardizedFileURL
        guard destination != currentURL else { return }
        guard FileManager.default.fileExists(atPath: destination.path) else {
            errorMessage = language == .german
                ? "Der Ordner existiert nicht: \(destination.path)"
                : "The folder does not exist: \(destination.path)"
            return
        }

        if historyIndex + 1 < history.count {
            history.removeSubrange((historyIndex + 1)..<history.count)
        }
        history.append(destination)
        historyIndex = history.count - 1
        currentURL = destination
        resetSearch()
        selectedItemIDs.removeAll()
        reload()
    }

    func open(_ item: FileItem) {
        if item.canNavigateInto {
            navigate(to: item.url)
        } else if fileSystem.requiresExecutionConfirmation(for: item) {
            pendingExecutionItem = item
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func confirmPendingExecution() {
        guard let item = pendingExecutionItem else { return }
        pendingExecutionItem = nil
        NSWorkspace.shared.open(item.url)
    }

    func cancelPendingExecution() {
        pendingExecutionItem = nil
    }

    func executionConfirmationMessage(for item: FileItem) -> String {
        if language == .german {
            return "Soll das Unix-Script „\(item.name)“ wirklich gestartet werden?"
        }
        return "Do you really want to run the Unix script “\(item.name)”?"
    }

    func open(_ location: SidebarLocation) {
        if location.url.scheme == "xfinder-device" {
            openImageCapture()
            return
        }
        if location.opensExternally {
            NSWorkspace.shared.open(location.url)
        } else {
            navigate(to: location.url)
        }
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
        currentURL = history[historyIndex]
        resetSearch()
        selectedItemIDs.removeAll()
        reload()
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentURL = history[historyIndex]
        resetSearch()
        selectedItemIDs.removeAll()
        reload()
    }

    func goUp() {
        guard currentURL.path != "/" else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    func createFolder() {
        do {
            let newURL = try fileSystem.createFolder(
                in: currentURL,
                baseName: text("New Folder")
            )
            reload()
            selectedItemIDs = [newURL]
            renameTarget = selectedItem
        } catch {
            present(error)
        }
    }

    func createFile(_ kind: NewFileKind) {
        do {
            let newURL = try fileSystem.createFile(
                in: currentURL,
                kind: kind,
                baseName: text(kind.baseName)
            )
            reload()
            selectedItemIDs = [newURL]
            renameTarget = selectedItem
        } catch {
            present(error)
        }
    }

    func beginRename() {
        renameTarget = selectedItem
    }

    func rename(_ item: FileItem, to newName: String) {
        renameTarget = nil
        do {
            let newURL = try fileSystem.rename(item, to: newName)
            reload()
            selectedItemIDs = [newURL]
        } catch {
            present(error)
        }
    }

    func moveSelectionToTrash() {
        let itemsToTrash = selectedItems
        guard !itemsToTrash.isEmpty else { return }
        do {
            for item in itemsToTrash {
                try fileSystem.moveToTrash(item)
            }
            selectedItemIDs.removeAll()
            reload()
        } catch {
            present(error)
        }
    }

    func revealSelectionInFinder() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealCurrentFolderInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: currentURL.path)
    }

    func openCurrentFolderInTerminal() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", currentURL.path]
        do {
            try process.run()
        } catch {
            present(error)
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealApplicationInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func openImageCapture() {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Image_Capture"
        ) else {
            errorMessage = language == .german
                ? "Das Programm „Digitale Bilder“ wurde nicht gefunden."
                : "Image Capture could not be found."
            return
        }
        NSWorkspace.shared.open(applicationURL)
    }

    private func resetSearch() {
        searchTask?.cancel()
        activeSearchQuery = ""
        searchResults = []
        isSearching = false
    }

    private func persistCustomFavorites() {
        UserDefaults.standard.set(
            customFavoriteURLs.map(\.path),
            forKey: Self.customFavoritesKey
        )
    }

    func text(_ english: String) -> String {
        guard language == .german else { return english }
        return Self.germanTranslations[english] ?? english
    }

    func itemCountText(_ count: Int) -> String {
        if language == .german {
            return count == 1 ? "1 Objekt" : "\(count) Objekte"
        }
        return count == 1 ? "1 item" : "\(count) items"
    }

    func resultCountText(_ count: Int) -> String {
        if language == .german {
            return count == 1 ? "1 Treffer" : "\(count) Treffer"
        }
        return count == 1 ? "1 result" : "\(count) results"
    }

    func selectionCountText(_ count: Int) -> String {
        language == .german ? "\(count) ausgewählt" : "\(count) selected"
    }

    func renameTitle(for name: String) -> String {
        language == .german ? "„\(name)“ umbenennen" : "Rename “\(name)”"
    }

    private func present(_ error: Error) {
        if let fileError = error as? FileSystemError, language == .german {
            switch fileError {
            case .invalidName:
                errorMessage = "Der Name darf nicht leer sein und keinen Schrägstrich enthalten."
            case .itemAlreadyExists(let name):
                errorMessage = "Ein Objekt namens „\(name)“ ist bereits vorhanden."
            case .missingTemplate(let pathExtension):
                errorMessage = "Die Vorlage für .\(pathExtension)-Dateien fehlt."
            }
            return
        }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static let germanTranslations: [String: String] = [
        "Settings": "Einstellungen",
        "General": "Allgemein",
        "Language": "Sprache",
        "Files": "Dateien",
        "Show hidden files": "Versteckte Dateien anzeigen",
        "Security": "Sicherheit",
        "Full Disk Access prevents repeated permission requests for protected folders.": "Festplattenvollzugriff verhindert wiederholte Zugriffsabfragen für geschützte Ordner.",
        "Show XFinder App in Finder": "XFinder-App im Finder zeigen",
        "Configure Full Disk Access…": "Vollzugriff auf Festplatte konfigurieren …",
        "Done": "Fertig",
        "New Folder": "Neuer Ordner",
        "New File": "Neue Datei",
        "Text Document (.txt)": "Textdokument (.txt)",
        "Rich Text Document (.rtf)": "Rich-Text-Dokument (.rtf)",
        "Word Document (.docx)": "Word-Dokument (.docx)",
        "Excel Workbook (.xlsx)": "Excel-Arbeitsmappe (.xlsx)",
        "PowerPoint Presentation (.pptx)": "PowerPoint-Präsentation (.pptx)",
        "New Text Document": "Neues Textdokument",
        "New Rich Text Document": "Neues Rich-Text-Dokument",
        "New Word Document": "Neues Word-Dokument",
        "New Excel Workbook": "Neue Excel-Arbeitsmappe",
        "New PowerPoint Presentation": "Neue PowerPoint-Präsentation",
        "Rename…": "Umbenennen …",
        "Rename": "Umbenennen",
        "Cancel": "Abbrechen",
        "Move to Trash": "In den Papierkorb",
        "View": "Darstellung",
        "Reload": "Neu laden",
        "Go": "Gehe zu",
        "Back": "Zurück",
        "Forward": "Vor",
        "Enclosing Folder": "Übergeordneter Ordner",
        "Home": "Benutzerordner",
        "Desktop": "Schreibtisch",
        "Documents": "Dokumente",
        "Downloads": "Downloads",
        "Applications": "Programme",
        "Pictures": "Bilder",
        "Music": "Musik",
        "Movies": "Filme",
        "iCloud Drive": "iCloud Drive",
        "Trash": "Papierkorb",
        "Connected Device": "Verbundenes Gerät",
        "Run Script?": "Script starten?",
        "Run": "Starten",
        "Add Current Folder to Favorites": "Aktuellen Ordner zu Favoriten hinzufügen",
        "Remove from Favorites": "Aus Favoriten entfernen",
        "Custom Favorites": "Eigene Favoriten",
        "No custom favorites yet.": "Noch keine eigenen Favoriten.",
        "This Folder": "Dieser Ordner",
        "Location": "Ort",
        "Searching subfolders…": "Unterordner werden durchsucht …",
        "Open Current Folder in Finder": "Aktuellen Ordner im Finder öffnen",
        "Open Current Folder in Terminal": "Aktuellen Ordner im Terminal öffnen",
        "Add to Favorites": "Zu Favoriten hinzufügen",
        "Open": "Öffnen",
        "Show in Finder": "Im Finder zeigen",
        "In Finder": "Im Finder",
        "Open the current folder in the original Finder": "Aktuellen Ordner im originalen Finder öffnen",
        "Search This Folder": "In diesem Ordner suchen",
        "Search or Pattern": "Suchen oder Muster",
        "Favorites": "Favoriten",
        "Locations": "Orte",
        "Hide hidden files": "Versteckte Dateien ausblenden",
        "Name": "Name",
        "Date Modified": "Änderungsdatum",
        "Size": "Größe",
        "Kind": "Art",
        "Folder": "Ordner",
        "Unknown error": "Unbekannter Fehler"
    ]
}
