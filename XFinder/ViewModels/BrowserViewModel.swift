import AppKit
import AVFoundation
import AVKit
import Foundation
import UniformTypeIdentifiers
@preconcurrency import ImageCaptureCore
@preconcurrency import QuickLookUI

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
        let rawName = device.name as String?
        let detectedName = rawName?.trimmingCharacters(in: .whitespacesAndNewlines)
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
private final class QuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookController()
    private var previewURLs: [URL] = []

    func show(_ urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        previewURLs = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    func updateIfVisible(_ urls: [URL]) {
        guard !urls.isEmpty, QLPreviewPanel.sharedPreviewPanelExists(),
              let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        previewURLs = urls
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        // Preserve keyboard/mouse focus in the file table while browsing images or MP3 files.
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(
        _ panel: QLPreviewPanel!,
        previewItemAt index: Int
    ) -> (any QLPreviewItem)! {
        guard previewURLs.indices.contains(index) else { return nil }
        return previewURLs[index] as NSURL
    }
}

private struct AudioFileMetadata: Sendable {
    var artwork: Data?
    var title: String?
    var artist: String?
    var album: String?
}

@MainActor
final class PlaylistPlayerController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PlaylistPlayerController()

    @Published private(set) var items: [FileItem] = []
    @Published private(set) var selectedID: URL?
    @Published private(set) var rootURL: URL?
    @Published private(set) var language: AppLanguage = .english
    @Published private(set) var isRandom: Bool {
        didSet { UserDefaults.standard.set(isRandom, forKey: Self.randomOrderKey) }
    }

    private let player = AVPlayer()
    private let playerView = AVPlayerView()
    private let trackLabel = NSTextField(labelWithString: "")
    private let artworkView = NSImageView()
    private let artistLabel = NSTextField(labelWithString: "")
    private let albumLabel = NSTextField(labelWithString: "")
    private var metadataTask: Task<Void, Never>?
    private var panel: NSPanel?
    private var playOrder: [URL] = []
    private var currentIndex = 0
    private var isPlayingPlaylist = false
    private var endObserver: NSObjectProtocol?
    private var activePlaybackID: UUID?
    private static let randomOrderKey = "playlistUsesRandomOrder"

    private override init() {
        isRandom = UserDefaults.standard.bool(forKey: Self.randomOrderKey)
        super.init()
        playerView.player = player
        playerView.controlsStyle = .default
        playerView.showsFullScreenToggleButton = false
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.setContentHuggingPriority(.defaultLow, for: .vertical)
        artworkView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        trackLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        artistLabel.textColor = .secondaryLabelColor
        albumLabel.textColor = .secondaryLabelColor
        for label in [trackLabel, artistLabel, albumLabel] {
            label.lineBreakMode = .byTruncatingMiddle
            label.alignment = .center
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
    }

    func setPlaylist(_ items: [FileItem], root: URL, language: AppLanguage) {
        stopPlayback()
        panel?.orderOut(nil)
        self.items = items
        rootURL = root
        self.language = language
        let urls = items.map(\.id)
        playOrder = isRandom ? urls.shuffled() : urls
        currentIndex = 0
    }

    func text(_ english: String, _ german: String) -> String {
        language == .german ? german : english
    }

    func album(for item: FileItem) -> String {
        let parent = item.url.deletingLastPathComponent().standardizedFileURL
        guard let root = rootURL?.standardizedFileURL else { return parent.lastPathComponent }
        if parent == root { return root.lastPathComponent }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return parent.path.hasPrefix(prefix) ? String(parent.path.dropFirst(prefix.count)) : parent.path
    }

    var canGoBack: Bool { !items.isEmpty && (selectedID == nil || currentIndex > 0) }
    var canGoForward: Bool { !items.isEmpty && (selectedID == nil || currentIndex + 1 < playOrder.count) }

    func play(_ id: URL) {
        guard let index = playOrder.firstIndex(of: id) else { return }
        currentIndex = index
        isPlayingPlaylist = true
        selectedID = id
        showPlayer(id, language: language)
    }

    func first() { if let item = items.first { play(item.id) } }
    func last() { if let item = items.last { play(item.id) } }
    func previous() {
        guard canGoBack else { return }
        play(playOrder[selectedID == nil ? 0 : currentIndex - 1])
    }
    func next() {
        guard canGoForward else { return }
        play(playOrder[selectedID == nil ? 0 : currentIndex + 1])
    }

    func toggleOrder() {
        let current = selectedID
        isRandom.toggle()
        let urls = items.map(\.id)
        if isRandom, let current {
            playOrder = [current] + urls.filter { $0 != current }.shuffled()
        } else {
            playOrder = isRandom ? urls.shuffled() : urls
        }
        currentIndex = current.flatMap { playOrder.firstIndex(of: $0) } ?? 0
    }

    func playSingle(_ url: URL, language: AppLanguage) {
        isPlayingPlaylist = false
        selectedID = nil
        showPlayer(url, language: language)
    }

    func updateSingleIfVisible(_ url: URL, language: AppLanguage) {
        guard panel?.isVisible == true, !isPlayingPlaylist else { return }
        playSingle(url, language: language)
    }

    private func showPlayer(_ url: URL, language: AppLanguage) {
        buildPanelIfNeeded()
        panel?.title = url.lastPathComponent
        removeEndObserver()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        let playbackID = UUID()
        activePlaybackID = playbackID
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            // Only the Sendable playback ID crosses into the main actor.
            Task { @MainActor [weak self] in
                guard let self, self.isPlayingPlaylist,
                      self.activePlaybackID == playbackID else { return }
                self.next()
            }
        }
        trackLabel.stringValue = url.lastPathComponent
        trackLabel.toolTip = url.path
        artistLabel.stringValue = ""
        albumLabel.stringValue = ""
        artworkView.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: language == .german ? "Kein Cover" : "No artwork"
        )
        artworkView.contentTintColor = .secondaryLabelColor
        metadataTask = Task { [weak self] in
            let metadata = await Self.readAudioMetadata(from: url)
            guard !Task.isCancelled, let self,
                  self.activePlaybackID == playbackID else { return }
            self.trackLabel.stringValue = metadata.title ?? url.lastPathComponent
            self.artistLabel.stringValue = metadata.artist ?? ""
            self.albumLabel.stringValue = metadata.album ?? ""
            if let data = metadata.artwork, let cover = NSImage(data: data) {
                self.artworkView.contentTintColor = nil
                self.artworkView.image = cover
            }
        }
        // Keep focus in the table so arrows and subsequent clicks select tracks.
        panel?.orderFront(nil)
        player.play()
    }

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentMinSize = NSSize(width: 340, height: 400)
        let content = NSVisualEffectView()
        content.material = .underWindowBackground
        content.blendingMode = .behindWindow
        content.state = .active
        panel.contentView = content
        let stack = NSStackView(views: [artworkView, trackLabel, artistLabel, albumLabel, playerView])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            artworkView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            artworkView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            trackLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            artistLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            albumLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            playerView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            playerView.heightAnchor.constraint(equalToConstant: 52)
        ])
        panel.center()
        self.panel = panel
    }

    private func removeEndObserver() {
        metadataTask?.cancel()
        metadataTask = nil
        activePlaybackID = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private nonisolated static func readAudioMetadata(from url: URL) async -> AudioFileMetadata {
        let asset = AVURLAsset(url: url)
        guard let entries = try? await asset.load(.commonMetadata) else { return AudioFileMetadata() }
        var result = AudioFileMetadata()
        for entry in entries {
            guard !Task.isCancelled else { return result }
            guard let key = entry.commonKey else { continue }
            switch key {
            case .commonKeyArtwork:
                if result.artwork == nil { result.artwork = try? await entry.load(.dataValue) }
            case .commonKeyTitle:
                if result.title == nil { result.title = try? await entry.load(.stringValue) }
            case .commonKeyArtist:
                if result.artist == nil { result.artist = try? await entry.load(.stringValue) }
            case .commonKeyAlbumName:
                if result.album == nil { result.album = try? await entry.load(.stringValue) }
            default:
                break
            }
        }
        return result
    }

    private func stopPlayback() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeEndObserver()
        isPlayingPlaylist = false
        selectedID = nil
    }

    func closePlaylist() {
        if isPlayingPlaylist {
            stopPlayback()
            panel?.orderOut(nil)
        }
        items = []
        playOrder = []
        rootURL = nil
        selectedID = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopPlayback()
    }
}

@MainActor
final class BrowserViewModel: ObservableObject {
    static let internalDragTypeIdentifier = "com.heinzd.xfinder.internal-file-drag"
    private let dragSourceID = UUID().uuidString

    @Published private(set) var currentURL: URL
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var volumes: [SidebarLocation] = []
    @Published private(set) var finderFavoriteURLs: [URL] = []
    @Published private(set) var searchResults: [FileItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isBuildingPlaylist = false
    @Published private(set) var activeSearchQuery = ""
    @Published private(set) var customFavoriteURLs: [URL] = []
    @Published private(set) var openDocumentSuiteNames: [String] = []
    @Published private var connectedDevices: [ConnectedMediaDevice] = []
    @Published var selectedItemIDs: Set<FileItem.ID> = [] {
        didSet {
            guard selectedItemIDs != oldValue, let item = selectedItem else { return }
            if isMP3(item) {
                PlaylistPlayerController.shared.updateSingleIfVisible(item.url, language: language)
            } else if usesMediaPreview(item) {
                quickLookController.updateIfVisible([item.url])
            }
        }
    }
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
    private let quickLookController = QuickLookController.shared
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
                    systemImage: "antenna.radiowaves.left.and.right",
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
    var canPreviewSelection: Bool { selectedItems.contains { !$0.isDirectory } }

    var standardNewFileKinds: [NewFileKind] {
        NewFileKind.allCases.filter { !$0.isOpenDocument }
    }

    var openDocumentNewFileKinds: [NewFileKind] {
        guard !openDocumentSuiteNames.isEmpty else { return [] }
        return NewFileKind.allCases.filter(\.isOpenDocument)
    }

    var openDocumentMenuTitle: String {
        openDocumentSuiteNames.joined(separator: " / ")
    }

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
            openDocumentSuiteNames = Self.installedOpenDocumentSuites()
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
        } else if isMP3(item) {
            PlaylistPlayerController.shared.playSingle(item.url, language: language)
        } else if usesMediaPreview(item) {
            quickLookController.show([item.url])
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func usesMediaPreview(_ item: FileItem) -> Bool {
        guard !item.isDirectory else { return false }
        if let type = UTType(filenameExtension: item.url.pathExtension),
           (type.conforms(to: .image) || type.conforms(to: .mp3)) { return true }
        let values = try? item.url.resourceValues(forKeys: [.contentTypeKey])
        guard let type = values?.contentType else { return false }
        return type.conforms(to: .image) || type.conforms(to: .mp3)
    }

    private func isMP3(_ item: FileItem) -> Bool {
        guard !item.isDirectory else { return false }
        if UTType(filenameExtension: item.url.pathExtension)?.conforms(to: .mp3) == true { return true }
        let values = try? item.url.resourceValues(forKeys: [.contentTypeKey])
        return values?.contentType?.conforms(to: .mp3) == true
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

    func createFolder(with selection: Set<FileItem.ID>) {
        let itemsToMove = selection.compactMap { item(withID: $0) }
        guard !itemsToMove.isEmpty else { return }

        do {
            let newURL = try fileSystem.createFolder(
                in: currentURL,
                baseName: text("New Folder With Items")
            )
            _ = try fileSystem.moveItems(itemsToMove.map(\.url), to: newURL)
            reload()
            selectedItemIDs = [newURL.standardizedFileURL]
            renameTarget = selectedItem
        } catch {
            reload()
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

    @discardableResult
    func copyDroppedItems(_ urls: [URL], to destination: URL) -> Bool {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !fileURLs.contains(where: {
            $0.deletingLastPathComponent()
                .standardizedFileURL
                .resolvingSymlinksInPath() == target
        }) else {
            errorMessage = language == .german
                ? "Die Auswahl befindet sich bereits im Zielordner. Es wurde nichts kopiert."
                : "The selection is already in the destination folder. Nothing was copied."
            return false
        }

        Task {
            do {
                let copiedURLs = try await Task.detached(priority: .userInitiated) {
                    try FileSystemService().copyItems(fileURLs, to: target)
                }.value
                reload()
                if target == currentURL.standardizedFileURL.resolvingSymlinksInPath() {
                    selectedItemIDs = Set(copiedURLs.map(\.standardizedFileURL))
                }
            } catch {
                present(error)
            }
        }
        return true
    }

    func dragProvider(for item: FileItem) -> NSItemProvider {
        // Export the original file URL, never a promised copy of its contents.
        let provider = NSItemProvider(object: item.url as NSURL)
        let sourceData = Data(dragSourceID.utf8)
        provider.registerDataRepresentation(
            forTypeIdentifier: Self.internalDragTypeIdentifier,
            visibility: .ownProcess
        ) { completion in
            completion(sourceData, nil)
            return nil
        }
        return provider
    }

    @discardableResult
    func copyExternalDroppedItems(
        _ providers: [NSItemProvider],
        to destination: URL
    ) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else {
            errorMessage = language == .german
                ? "Der Drop enthält keine lesbaren Datei-URLs."
                : "The drop contains no readable file URLs."
            return false
        }

        Task {
            // Validate the whole drop before copying any files. A marker belongs
            // to one browser window, not to every window in this process.
            for provider in providers where provider.hasItemConformingToTypeIdentifier(
                Self.internalDragTypeIdentifier
            ) {
                guard let sourceID = await droppedSourceID(from: provider) else {
                    errorMessage = language == .german
                        ? "Das Quellfenster des Drops konnte nicht ermittelt werden."
                        : "The source window of the drop could not be identified."
                    return
                }
                guard sourceID != dragSourceID else { return }
            }

            var urls: [URL] = []
            for provider in fileProviders {
                guard let url = await droppedURL(from: provider) else {
                    errorMessage = language == .german
                        ? "Die Datei-URL konnte nicht aus dem Drop gelesen werden."
                        : "The file URL could not be read from the drop."
                    return
                }
                urls.append(url)
            }
            _ = copyDroppedItems(urls, to: destination)
        }
        return true
    }

    private func droppedSourceID(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(
                forTypeIdentifier: Self.internalDragTypeIdentifier
            ) { data, _ in
                let sourceID = data.flatMap { String(data: $0, encoding: .utf8) }
                // Unknown or unreadable internal markers fail closed.
                guard let sourceID, UUID(uuidString: sourceID) != nil else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sourceID)
            }
        }
    }

    private func droppedURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { object, _ in
                let url: URL?
                if let value = object as? URL {
                    url = value
                } else if let value = object as? Data {
                    url = URL(dataRepresentation: value, relativeTo: nil)
                } else if let value = object as? String {
                    url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    url = nil
                }
                continuation.resume(returning: url?.isFileURL == true ? url : nil)
            }
        }
    }

    func revealSelectionInFinder() {
        let urls = selectedItems.map(\.url)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func previewSelection() {
        if let item = selectedItem, isMP3(item) {
            PlaylistPlayerController.shared.playSingle(item.url, language: language)
            return
        }
        let urls = selectedItems
            .filter { !$0.isDirectory }
            .map(\.url)
        quickLookController.show(urls)
    }

    func preview(_ selection: Set<FileItem.ID>) {
        selectedItemIDs = selection
        previewSelection()
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

    func playCurrentFolderPlaylist(openPlaylist: @escaping () -> Void) {
        guard !isBuildingPlaylist else { return }
        let root = selectedItem.flatMap { $0.canNavigateInto ? $0.url : nil } ?? currentURL
        let includesHiddenFiles = showHiddenFiles
        isBuildingPlaylist = true
        Task {
            defer { isBuildingPlaylist = false }
            do {
                let playlistItems = try await Task.detached(priority: .userInitiated) {
                    try FileSystemService().mp3PlaylistItems(
                        in: root,
                        showHiddenFiles: includesHiddenFiles
                    )
                }.value
                guard !playlistItems.isEmpty else {
                    errorMessage = language == .german
                        ? "In diesem Ordner und seinen Unterordnern wurden keine MP3-Dateien gefunden."
                        : "No MP3 files were found in this folder or its subfolders."
                    return
                }
                PlaylistPlayerController.shared.setPlaylist(playlistItems, root: root, language: language)
                openPlaylist()
            } catch is CancellationError {
                return
            } catch {
                present(error)
            }
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

    private static func installedOpenDocumentSuites() -> [String] {
        let fileManager = FileManager.default
        let homeApplications = URL.homeDirectory
            .appendingPathComponent("Applications", isDirectory: true)

        func isInstalled(bundleIdentifier: String, applicationName: String) -> Bool {
            if NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) != nil {
                return true
            }
            return [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeApplications
            ].contains { applicationsURL in
                fileManager.fileExists(
                    atPath: applicationsURL
                        .appendingPathComponent(applicationName, isDirectory: true)
                        .path
                )
            }
        }

        var suites: [String] = []
        if isInstalled(
            bundleIdentifier: "org.libreoffice.script",
            applicationName: "LibreOffice.app"
        ) {
            suites.append("LibreOffice")
        }
        if isInstalled(
            bundleIdentifier: "org.openoffice.script",
            applicationName: "OpenOffice.app"
        ) {
            suites.append("OpenOffice")
        }
        return suites
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

    func newFolderWithSelectionTitle(_ count: Int) -> String {
        if language == .german {
            let object = count == 1 ? "Objekt" : "Objekte"
            return "Neuer Ordner mit Auswahl (\(count) \(object))"
        }
        let item = count == 1 ? "Item" : "Items"
        return "New Folder with Selection (\(count) \(item))"
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
            case .cannotCopyIntoItself(let name):
                errorMessage = "„\(name)“ kann nicht in sich selbst kopiert werden."
            case .itemNoLongerExists(let name):
                errorMessage = "„\(name)“ ist nicht mehr vorhanden. Bitte den Ordner neu laden und erneut versuchen."
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
        "New Folder With Items": "Neuer Ordner mit Objekten",
        "New File": "Neue Datei",
        "Text Document (.txt)": "Textdokument (.txt)",
        "Rich Text Document (.rtf)": "Rich-Text-Dokument (.rtf)",
        "Word Document (.docx)": "Word-Dokument (.docx)",
        "Excel Workbook (.xlsx)": "Excel-Arbeitsmappe (.xlsx)",
        "PowerPoint Presentation (.pptx)": "PowerPoint-Präsentation (.pptx)",
        "OpenDocument Text (.odt)": "OpenDocument-Text (.odt)",
        "OpenDocument Spreadsheet (.ods)": "OpenDocument-Tabelle (.ods)",
        "OpenDocument Presentation (.odp)": "OpenDocument-Präsentation (.odp)",
        "New Text Document": "Neues Textdokument",
        "New Rich Text Document": "Neues Rich-Text-Dokument",
        "New Word Document": "Neues Word-Dokument",
        "New Excel Workbook": "Neue Excel-Arbeitsmappe",
        "New PowerPoint Presentation": "Neue PowerPoint-Präsentation",
        "New OpenDocument Text": "Neuer OpenDocument-Text",
        "New OpenDocument Spreadsheet": "Neue OpenDocument-Tabelle",
        "New OpenDocument Presentation": "Neue OpenDocument-Präsentation",
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
        "Quick Look": "Vorschau",
        "Show in Finder": "Im Finder zeigen",
        "In Finder": "Im Finder",
        "Open the current folder in the original Finder": "Aktuellen Ordner im originalen Finder öffnen",
        "Search This Folder": "In diesem Ordner suchen",
        "Search": "Suchen",
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
