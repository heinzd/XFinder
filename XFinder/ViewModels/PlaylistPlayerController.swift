import AppKit
import AVFoundation
import AVKit
import Combine
import Foundation

@MainActor
final class PlaylistPlayerController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PlaylistPlayerController()

    @Published private(set) var items: [FileItem] = []
    @Published private(set) var selectedID: URL?
    @Published private(set) var automaticScrollRequest: URL?
    @Published private(set) var isPlaybackActive = false
    @Published private(set) var rootURL: URL?
    @Published private(set) var rootURLs: [URL] = []
    @Published private(set) var language: AppLanguage = .english
    @Published private(set) var playlistArtwork: [URL: NSImage] = [:]
    @Published private(set) var isRandom: Bool {
        didSet { UserDefaults.standard.set(isRandom, forKey: Self.randomOrderKey) }
    }
    @Published private(set) var isEndless: Bool {
        didSet { UserDefaults.standard.set(isEndless, forKey: Self.endlessPlaybackKey) }
    }

    private let player = AVPlayer()
    private let playerView = AVPlayerView()
    private let trackLabel = NSTextField(wrappingLabelWithString: "")
    private let artworkView = NSImageView()
    private let artistLabel = NSTextField(labelWithString: "")
    private let albumLabel = NSTextField(labelWithString: "")
    private var metadataTask: Task<Void, Never>?
    private var playlistArtworkTask: Task<Void, Never>?
    private var panel: NSPanel?
    private var playerContentView: NSView?
    private weak var playlistPlayerHost: NSView?
    private weak var playlistWindow: NSWindow?
    private var displayedArtworkData: Data?
    private var playOrder: [URL] = []
    private var currentIndex = 0
    private var isPlayingPlaylist = false
    private var endObserver: NSObjectProtocol?
    private var playbackObservation: NSKeyValueObservation?
    private var activePlaybackID: UUID?
    private static let randomOrderKey = "playlistUsesRandomOrder"
    private static let endlessPlaybackKey = "playlistUsesEndlessPlayback"

    private override init() {
        isRandom = UserDefaults.standard.bool(forKey: Self.randomOrderKey)
        isEndless = UserDefaults.standard.bool(forKey: Self.endlessPlaybackKey)
        super.init()
        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            // Read the current state on the main actor; do not transfer KVO values.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaybackActive = self.player.timeControlStatus != .paused
            }
        }
        playerView.player = player
        playerView.controlsStyle = .default
        playerView.showsFullScreenToggleButton = false
        playerView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        artworkView.imageScaling = .scaleProportionallyUpOrDown
        artworkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        artworkView.setContentHuggingPriority(.defaultLow, for: .vertical)
        artworkView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        trackLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        artistLabel.textColor = .secondaryLabelColor
        albumLabel.textColor = .secondaryLabelColor
        for label in [trackLabel, artistLabel, albumLabel] {
            label.lineBreakMode = .byTruncatingMiddle
            label.alignment = .center
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.required, for: .vertical)
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        trackLabel.usesSingleLineMode = false
        trackLabel.maximumNumberOfLines = 3
        trackLabel.lineBreakMode = .byWordWrapping
    }

    func setPlaylist(_ items: [FileItem], roots: [URL], language: AppLanguage) {
        stopPlayback()
        panel?.orderOut(nil)
        self.items = items
        rootURLs = roots.map(\.standardizedFileURL)
        rootURL = rootURLs.count == 1 ? rootURLs[0] : nil
        self.language = language
        resetPlaylistPresentation()
        loadPlaylistArtwork(for: items)
        let urls = items.map(\.id)
        playOrder = isRandom ? urls.shuffled() : urls
        currentIndex = 0
    }

    func text(_ english: String, _ german: String) -> String {
        language == .german ? german : english
    }

    func album(for item: FileItem) -> String {
        let parent = item.url.deletingLastPathComponent().standardizedFileURL
        guard let root = rootURLs.first(where: { root in
            parent == root || parent.path.hasPrefix(root.path.hasSuffix("/") ? root.path : root.path + "/")
        }) else { return parent.lastPathComponent }
        if parent == root { return root.lastPathComponent }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return parent.path.hasPrefix(prefix) ? String(parent.path.dropFirst(prefix.count)) : parent.path
    }

    var sourceDescription: String {
        rootURLs.map(\.lastPathComponent).joined(separator: ", ")
    }

    var canGoBack: Bool { !items.isEmpty && (selectedID == nil || currentIndex > 0) }
    var canGoForward: Bool { !items.isEmpty && (selectedID == nil || currentIndex + 1 < playOrder.count) }
    var canStopPlaylist: Bool { isPlayingPlaylist && isPlaybackActive }

    func togglePlayStop() {
        if canStopPlaylist {
            haltPlayback()
        } else if let id = selectedID ?? playOrder.first {
            play(id, scrollSelectionIntoView: true)
        }
    }

    func play(
        _ id: URL,
        revealPlayer: Bool = true,
        scrollSelectionIntoView: Bool = false
    ) {
        guard let index = playOrder.firstIndex(of: id) else { return }
        currentIndex = index
        isPlayingPlaylist = true
        selectedID = id
        if scrollSelectionIntoView {
            // Clear first so repeating a one-track playlist creates a new change.
            automaticScrollRequest = nil
            automaticScrollRequest = id
        }
        showPlayer(id, language: language, revealPlayer: revealPlayer)
    }

    func first() {
        if let item = items.first { play(item.id, scrollSelectionIntoView: true) }
    }

    func last() {
        if let item = items.last { play(item.id, scrollSelectionIntoView: true) }
    }

    func previous() {
        guard canGoBack else { return }
        play(
            playOrder[selectedID == nil ? 0 : currentIndex - 1],
            scrollSelectionIntoView: true
        )
    }

    func next() {
        guard canGoForward else { return }
        play(
            playOrder[selectedID == nil ? 0 : currentIndex + 1],
            scrollSelectionIntoView: true
        )
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

    func toggleEndless() {
        isEndless.toggle()
    }

    func playSingle(_ url: URL, language: AppLanguage) {
        isPlayingPlaylist = false
        selectedID = nil
        attachPlayerToPanel()
        showPlayer(url, language: language)
    }

    func updateSingleIfVisible(_ url: URL, language: AppLanguage) {
        guard panel?.isVisible == true, !isPlayingPlaylist else { return }
        playSingle(url, language: language)
    }

    private func showPlayer(_ url: URL, language: AppLanguage, revealPlayer: Bool = true) {
        buildPanelIfNeeded()
        if isPlayingPlaylist {
            attachPlayerToPlaylistIfPossible()
            panel?.orderOut(nil)
        } else {
            attachPlayerToPanel()
        }
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
                if self.canGoForward {
                    self.play(
                        self.playOrder[self.currentIndex + 1],
                        revealPlayer: false,
                        scrollSelectionIntoView: true
                    )
                } else if self.isEndless, let first = self.playOrder.first {
                    self.play(first, revealPlayer: false, scrollSelectionIntoView: true)
                }
            }
        }
        metadataTask = Task { @MainActor [weak self] in
            let metadata = await AudioMetadataReader.track(at: url)
            guard !Task.isCancelled, let self,
                  self.activePlaybackID == playbackID else { return }
            // Keep the previous presentation until the complete next snapshot is ready.
            let artworkChanged = self.displayedArtworkData != metadata.artworkData || self.artworkView.image == nil
            let cover = artworkChanged ? metadata.artworkData.flatMap { NSImage(data: $0) } : nil
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0
                context.allowsImplicitAnimation = false
                self.panel?.title = url.lastPathComponent
                self.trackLabel.stringValue = metadata.title
                self.trackLabel.toolTip = url.path
                self.artistLabel.stringValue = metadata.artist ?? ""
                self.albumLabel.stringValue = metadata.album ?? ""
                if artworkChanged {
                    self.displayedArtworkData = metadata.artworkData
                    self.artworkView.contentTintColor = cover == nil ? .secondaryLabelColor : nil
                    self.artworkView.image = cover ?? NSImage(
                        systemSymbolName: "music.note",
                        accessibilityDescription: language == .german ? "Kein Cover" : "No artwork"
                    )
                }
                self.playerContentView?.layoutSubtreeIfNeeded()
            }, completionHandler: nil)
            if revealPlayer && !self.isPlayingPlaylist {
                self.panel?.orderFront(nil)
            }
        }
        player.play()
        isPlaybackActive = true
    }

    private func buildPanelIfNeeded() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.contentMinSize = NSSize(width: 200, height: 280)
        let content = NSVisualEffectView()
        content.material = .underWindowBackground
        content.blendingMode = .behindWindow
        content.state = .active
        panel.contentView = content
        playerContentView = content
        let stack = NSStackView(views: [artworkView, trackLabel, artistLabel, albumLabel, playerView])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            artworkView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            artworkView.heightAnchor.constraint(greaterThanOrEqualToConstant: 64),
            trackLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            trackLabel.heightAnchor.constraint(equalToConstant: 66),
            artistLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            artistLabel.heightAnchor.constraint(equalToConstant: 17),
            albumLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            albumLabel.heightAnchor.constraint(equalToConstant: 17),
            playerView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            playerView.heightAnchor.constraint(equalToConstant: 52)
        ])
        panel.center()
        self.panel = panel
    }

    func attachPlaylistPlayer(to host: NSView) {
        playlistPlayerHost = host
        buildPanelIfNeeded()
        attachPlayerToPlaylistIfPossible()
        panel?.orderOut(nil)
    }

    func observePlaylistWindow(_ window: NSWindow) {
        guard playlistWindow !== window else { return }
        if let playlistWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: playlistWindow
            )
        }
        playlistWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playlistWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func playlistWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === playlistWindow else { return }
        closePlaylist()
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.willCloseNotification,
            object: window
        )
        playlistWindow = nil
    }

    func detachPlaylistPlayer(from host: NSView) {
        guard playlistPlayerHost === host else { return }
        playlistPlayerHost = nil
        playerContentView?.removeFromSuperview()
    }

    private func attachPlayerToPlaylistIfPossible() {
        guard isPlayingPlaylist || !items.isEmpty,
              let host = playlistPlayerHost,
              let content = playerContentView else { return }
        if content.superview === host { return }
        if panel?.contentView === content { panel?.contentView = NSView() }
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
    }

    private func attachPlayerToPanel() {
        buildPanelIfNeeded()
        guard let panel, let content = playerContentView,
              panel.contentView !== content else { return }
        content.removeFromSuperview()
        content.translatesAutoresizingMaskIntoConstraints = true
        panel.contentView = content
    }

    private func resetPlaylistPresentation() {
        buildPanelIfNeeded()
        displayedArtworkData = nil
        artworkView.contentTintColor = .secondaryLabelColor
        artworkView.image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: language == .german ? "Kein Titel ausgewählt" : "No track selected"
        )
        trackLabel.stringValue = language == .german ? "Titel auswählen" : "Select a track"
        trackLabel.toolTip = nil
        artistLabel.stringValue = ""
        albumLabel.stringValue = ""
        attachPlayerToPlaylistIfPossible()
    }

    private func loadPlaylistArtwork(for items: [FileItem]) {
        playlistArtworkTask?.cancel()
        playlistArtwork = [:]
        playlistArtworkTask = Task { @MainActor [weak self] in
            for item in items {
                guard !Task.isCancelled else { return }
                let track = await AudioMetadataReader.track(at: item.url)
                if let data = track.artworkData,
                   !Task.isCancelled,
                   let image = NSImage(data: data) {
                    self?.playlistArtwork[item.id] = image
                }
            }
        }
    }

    private func removeEndObserver() {
        metadataTask?.cancel()
        metadataTask = nil
        activePlaybackID = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func haltPlayback() {
        removeEndObserver()
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaybackActive = false
    }

    private func stopPlayback() {
        haltPlayback()
        isPlayingPlaylist = false
        selectedID = nil
    }

    func closePlaylist() {
        playlistArtworkTask?.cancel()
        playlistArtworkTask = nil
        if isPlayingPlaylist {
            stopPlayback()
            playerContentView?.removeFromSuperview()
            panel?.orderOut(nil)
        } else if playerContentView?.superview === playlistPlayerHost {
            // Remove only the embedded idle presentation. A single file that is
            // playing in its own panel must survive closing the playlist window.
            playerContentView?.removeFromSuperview()
        }
        items = []
        playOrder = []
        rootURL = nil
        rootURLs = []
        playlistArtwork = [:]
        selectedID = nil
        automaticScrollRequest = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopPlayback()
    }
}
