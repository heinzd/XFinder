import AppKit
import Combine
import SwiftUI

@MainActor
private final class XFinderAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
@MainActor
struct XFinderApp: App {
    @NSApplicationDelegateAdaptor(XFinderAppDelegate.self) private var appDelegate
    @AppStorage("appLanguage") private var helpWindowLanguage = AppLanguage.english.rawValue

    var body: some Scene {
        WindowGroup("XFinder", id: "browser", for: DockedBrowserRequest.self) { $request in
            BrowserWindowRoot(request: request)
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            XFinderCommands()
        }

        Window("Playlist", id: "playlist") {
            PlaylistView()
                .frame(minWidth: 620, minHeight: 360)
        }
        .defaultSize(width: 840, height: 560)

        Window(Text(helpWindowLanguage == AppLanguage.german.rawValue ? "XFinder-Hilfe" : "XFinder Help"), id: "help") {
            XFinderHelpView()
        }
        .defaultSize(width: 900, height: 680)
    }
}

/// Menus follow the key NSWindow, independently of SwiftUI's focused-view chain.
private struct XFinderCommands: Commands {
    @ObservedObject private var context = BrowserCommandContext.shared
    @Environment(\.openWindow) private var openWindow
    @AppStorage("appLanguage") private var helpLanguage = AppLanguage.english.rawValue

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(helpLanguage == AppLanguage.german.rawValue ? "XFinder-Hilfe" : "XFinder Help") {
                openWindow(id: "help")
            }
        }
        if let model = context.activeModel {
            BrowserFileCommands(model: model)
        }
    }
}

private struct BrowserFileCommands: Commands {
    @ObservedObject var model: BrowserViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(model.text("New Folder")) { model.createFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(model.text("Rename…")) { model.beginRename() }
                .disabled(model.selectedItem == nil)
            // Space is handled by the file table so text fields retain normal typing.
            Button(model.text("Quick Look")) { model.previewSelection() }
                .disabled(!model.canPreviewSelection)
            Button(model.text("Move to Trash")) { model.moveSelectionToTrash() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedItems.isEmpty)
        }

        CommandMenu(model.text("View")) {
            Toggle(model.text("Show hidden files"), isOn: $model.showHiddenFiles)
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button(model.text("Reload")) { model.reload() }
                .keyboardShortcut("r", modifiers: .command)
        }

        CommandMenu(model.text("Go")) {
            Button(model.text("Back")) { model.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!model.canGoBack)
            Button(model.text("Forward")) { model.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!model.canGoForward)
            Button(model.text("Enclosing Folder")) { model.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(model.currentURL.path == "/")
            Button(model.text("Home")) { model.navigate(to: .homeDirectory) }
                .keyboardShortcut("h", modifiers: [.command, .shift])
            Divider()
            Button(model.text("Open Current Folder in Finder")) {
                model.revealCurrentFolderInFinder()
            }
        }

        CommandGroup(replacing: .appSettings) {
            Button(model.text("Settings") + "…") { model.isShowingSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .appInfo) {
            Button(model.text("Show XFinder App in Finder")) {
                model.revealApplicationInFinder()
            }
            Button(model.text("Configure Full Disk Access…")) {
                model.openFullDiskAccessSettings()
            }
        }
    }
}

/// Weak window registrations; only the active model is retained for menu observation.
/// Help, playlist, player, and sheets have no file-operation target.
@MainActor
final class BrowserCommandContext: NSObject, ObservableObject {
    static let shared = BrowserCommandContext()
    @Published private(set) var activeModel: BrowserViewModel?

    private struct Entry {
        weak var window: NSWindow?
        weak var model: BrowserViewModel?
    }
    private var entries: [ObjectIdentifier: Entry] = [:]

    private override init() {
        super.init()
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
            NotificationCenter.default.addObserver(
                self, selector: #selector(focusChanged(_:)), name: name, object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowClosed(_:)), name: NSWindow.willCloseNotification, object: nil
        )
    }

    func register(_ window: NSWindow, model: BrowserViewModel) {
        entries[ObjectIdentifier(window)] = Entry(window: window, model: model)
        refresh()
    }

    private func refresh() {
        entries = entries.filter { $0.value.window != nil && $0.value.model != nil }
        let model: BrowserViewModel?
        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            model = entries[ObjectIdentifier(window)]?.model
        } else {
            model = nil
        }
        if activeModel !== model { activeModel = model }
    }

    @objc private func focusChanged(_ notification: Notification) {
        // Let AppKit finish assigning keyWindow before resolving the command target.
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }

    @objc private func windowClosed(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            entries.removeValue(forKey: ObjectIdentifier(window))
        }
        refresh()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

struct DockedBrowserRequest: Codable, Hashable {
    var id = UUID()
    let startPath: String
}

private struct BrowserWindowRoot: View {
    @StateObject private var model: BrowserViewModel
    let request: DockedBrowserRequest?

    init(request: DockedBrowserRequest?) {
        self.request = request
        _model = StateObject(wrappedValue: BrowserViewModel(
            startURL: request.map { URL(fileURLWithPath: $0.startPath, isDirectory: true) }
                ?? .homeDirectory
        ))
    }

    var body: some View {
        ContentView(dockingRequestID: request?.id)
            .environmentObject(model)
            .frame(minWidth: 480, minHeight: 400)
    }
}

@MainActor
final class BrowserWindowHandle: ObservableObject {
    weak var window: NSWindow?
}

struct BrowserWindowReader: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: WindowView, context: Context) {
        nsView.onResolve = onResolve
    }

    final class WindowView: NSView {
        var onResolve: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Wait until SwiftUI has installed the window and its size constraints.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                self.onResolve?(window)
            }
        }
    }
}

/// Keeps ordinary SwiftUI windows side by side without sharing browser state.
@MainActor
final class BrowserWindowDocking {
    static let shared = BrowserWindowDocking()
    private var pending: [UUID: BrowserWindowHandle] = [:]
    private var pairs: [UUID: DockedPair] = [:]

    func partner(of window: NSWindow) -> NSWindow? {
        pairs.values.compactMap { $0.partner(of: window) }.first
    }

    func prepare(_ request: DockedBrowserRequest, beside window: NSWindow) -> Bool {
        guard !pending.values.contains(where: { $0.window === window }) else { return false }
        let handle = BrowserWindowHandle()
        handle.window = window
        pending[request.id] = handle
        return true
    }

    func attach(_ window: NSWindow, requestID: UUID?) {
        guard let requestID,
              let source = pending.removeValue(forKey: requestID)?.window,
              source !== window, source.isVisible,
              let screen = source.screen else { return }
        let area = screen.visibleFrame
        let width = floor(area.width / 2)
        let height = min(max(source.frame.height, 440), area.height)
        let y = min(max(source.frame.minY, area.minY), area.maxY - height)
        source.setFrame(NSRect(x: area.minX, y: y, width: width, height: height), display: true)
        window.setFrame(NSRect(x: source.frame.maxX, y: y,
                               width: area.width - width, height: height), display: true)
        let pair = DockedPair(left: source, right: window) { [weak self] in
            self?.pairs.removeValue(forKey: requestID)
        }
        pairs[requestID] = pair
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class DockedPair: NSObject {
    private weak var left: NSWindow?
    private weak var right: NSWindow?
    private var adjusting = false
    private let onDetach: () -> Void

    init(left: NSWindow, right: NSWindow, onDetach: @escaping () -> Void) {
        self.left = left
        self.right = right
        self.onDetach = onDetach
        super.init()
        for window in [left, right] {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(frameChanged(_:)), name: name, object: window
                )
            }
            for name in [NSWindow.willCloseNotification, NSWindow.willEnterFullScreenNotification] {
                NotificationCenter.default.addObserver(
                    self, selector: #selector(detach(_:)), name: name, object: window
                )
            }
        }
    }

    func partner(of window: NSWindow) -> NSWindow? {
        if window === left { return right }
        if window === right { return left }
        return nil
    }

    @objc private func frameChanged(_ notification: Notification) {
        guard !adjusting, let left, let right,
              let moved = notification.object as? NSWindow else { return }
        adjusting = true
        defer { adjusting = false }
        if moved === left {
            let frame = NSRect(x: left.frame.maxX, y: left.frame.minY,
                               width: right.frame.width, height: left.frame.height)
            if right.frame != frame { right.setFrame(frame, display: true) }
        } else if moved === right {
            let frame = NSRect(x: right.frame.minX - left.frame.width, y: right.frame.minY,
                               width: left.frame.width, height: right.frame.height)
            if left.frame != frame { left.setFrame(frame, display: true) }
        }
    }

    @objc private func detach(_ notification: Notification) {
        invalidate()
        onDetach()
    }

    func invalidate() {
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

/// Offline manual, generated from the same Markdown published on GitHub.
private struct XFinderHelpView: View {
    @AppStorage("appLanguage") private var language = AppLanguage.english.rawValue

    private var isGerman: Bool { language == AppLanguage.german.rawValue }

    private func text(_ english: String, _ german: String) -> String {
        isGerman ? german : english
    }

    @State private var query = ""
    @State private var selectedID: Int? = 0

    private struct Topic: Identifiable, Sendable {
        let id: Int
        let title: String
        let body: String
    }

    private var topics: [Topic] {
        (isGerman ? XFinderUserGuide.german : XFinderUserGuide.english)
        .components(separatedBy: "\n## ")
        .enumerated()
        .map { index, section in
            let lines = section.components(separatedBy: "\n")
            return Topic(
                id: index,
                title: index == 0 ? text("About this guide", "Über diese Hilfe") : (lines.first ?? ""),
                body: lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private var filteredTopics: [Topic] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return topics.filter {
            term.isEmpty || $0.title.localizedStandardContains(term) || $0.body.localizedStandardContains(term)
        }
    }

    private var currentTopic: Topic? {
        filteredTopics.first(where: { $0.id == selectedID }) ?? filteredTopics.first
    }

    private var topicSelection: Binding<Int?> {
        Binding(get: { currentTopic?.id }, set: { selectedID = $0 })
    }

    var body: some View {
        NavigationSplitView {
            List(filteredTopics, selection: topicSelection) { topic in
                Text(topic.title)
                    .tag(topic.id)
                    .padding(.vertical, 3)
            }
            .navigationTitle(text("Contents", "Inhalt"))
            .navigationSplitViewColumnWidth(min: 190, ideal: 245, max: 320)
        } detail: {
            if let topic = currentTopic {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(topic.title)
                            .font(.title2.weight(.semibold))
                        ForEach(Array(topic.body.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
                            Text(verbatim: paragraph)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .textSelection(.enabled)
                    .padding(28)
                    .frame(maxWidth: 800, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(topic.id)
            } else {
                ContentUnavailableView(text("No results", "Keine Treffer"), systemImage: "magnifyingglass",
                                       description: Text(text("Try a different search term.", "Versuche einen anderen Suchbegriff.")))
            }
        }
        .searchable(text: $query, prompt: text("Search help", "Hilfe durchsuchen"))
        .onChange(of: language) { _, _ in
            // @AppStorage can change while another SwiftUI view is still processing
            // the language Picker. Publish this local state change on the next pass.
            DispatchQueue.main.async {
                query = ""
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .toolbar {
            ToolbarItem {
                Link(destination: URL(string: "https://github.com/heinzd/XFinder/blob/main/docs/" + (isGerman ? "Bedienung.md" : "UserGuide.md"))!) {
                    Label(text("Open on GitHub", "Auf GitHub öffnen"), systemImage: "arrow.up.right.square")
                }
                .help(text("Open the current guide on GitHub", "Aktuelle Anleitung auf GitHub öffnen"))
            }
        }
    }
}

// BEGIN GENERATED USER GUIDE
private enum XFinderUserGuide {
    static let english = #"""
# XFinder – User Guide

This guide describes XFinder 0.4. Help follows the language selected in XFinder Settings, including when the help window is already open. Open it offline through Help > XFinder Help or the question-mark toolbar button. The contents appear on the left; the search field searches both headings and chapter text.

## Getting started and navigation

XFinder displays favorites and locations on the left and the current folder's files on the right. Double-click a folder to open it. The path bar shows the current location; click a folder component to navigate up the hierarchy.

The toolbar arrows go back, forward, and to the enclosing folder. Reload refreshes the view. The Finder and Terminal buttons open the current folder in the respective application.

Open Settings using the gear button or ⌘,. You can switch between English and German; the choice is saved. View > Show hidden files also displays files that are normally hidden.

## Selection and table sorting

Click an item to select it. Command-click adds or removes individual items. Shift-click selects a contiguous range. The status bar shows the number of selected items.

Click a column heading to sort by Name, Date Modified, Size, or Kind. Click again to reverse the direction. Search results can also be sorted by Location. Dates use leading zeros, for example 06.08.2026, 09:05.

Open the context menu with a right-click or Control-click. Selection actions apply to the items selected for that menu.

## Working with files and folders

New Folder creates a folder in the current directory. Rename… changes the name of a single selected item. Move to Trash moves the selected items to the macOS Trash.

To group several items, select the files and folders, open the context menu, and choose New Folder with Selection. XFinder creates a folder, moves the selection into it, and opens the rename dialog for that folder. This moves the items rather than copying them. Missing items are checked first; duplicate and nested selection paths are handled so they are not moved twice.

New File in the context menu offers text, rich text, and Office documents for Word, Excel, and PowerPoint. An additional LibreOffice/OpenOffice menu provides ODT, ODS, and ODP when at least one of these applications is installed. Otherwise, that submenu is hidden.

## Drag and drop and copy rules

Drag a file from the table to a Finder folder or to another application, such as Preview. The receiving application decides how to handle it. Dragging files from Finder onto the XFinder table copies them into the current folder. Dropping onto a displayed subfolder copies them into that subfolder.

Files dragged between two different XFinder windows are also copied. The originals remain in place. Open different folders in the two windows for this operation.

Drops within the same XFinder window are blocked. Dropping back into the source folder is also rejected, even when the source and destination are displayed in different windows or applications. This prevents an unnecessary renamed copy in the same folder.

If a different file already has the same name at the destination, XFinder chooses an available name such as “File copy” or “File copy 2”. Existing destination files are not overwritten. Problems accepting files are reported in an error message.

## Two docked file windows

Dock Second Window in the toolbar opens the current folder in a second window and arranges both windows side by side. Navigation, search, and selection are independent in each window; menu commands apply to the active file window.

Moving either window moves the pair together. Resizing aligns their heights and adjacent edges. Clicking the button again activates the existing partner. Closing either window or entering full screen releases the pair.

To copy files, navigate to the source folder on one side and the destination on the other, then drag the files across. The rules in “Drag and drop and copy rules” also apply to this window pair.

## Searching for files

The Search field searches file names in the current folder and recursively in its subfolders. It searches names, not the contents of documents.

Without wildcards, part of a name is enough. Use * for any number of characters and ? for exactly one character. Examples: *.pdf for PDF files, test.* for files named test with any extension, and report-?.pdf for names such as report-1.pdf.

The additional Location column shows the folder containing each result. Clear the search text to return to the normal folder view. Large directory trees can take time; an activity indicator is shown while searching.

## Images, PDFs, and Quick Look

Select one or more files in the file table and press Space or click the eye button for Quick Look. The action is also available in the context menu. With several files selected, you can navigate through them in the preview window.

Double-clicking an image opens the image viewer. While it is open, clicking another image updates the preview, including from the other file window. Use the preview action for PDFs and other formats supported by macOS as well.

Other files open in their default applications. Recognized scripts require confirmation first: XFinder checks known script extensions and the #! shebang at the start of a file. The Unix executable bit alone does not trigger a prompt; an ordinary MP3 file needs no such confirmation.

## Playing a single MP3

Double-click an MP3 file to open the audio player and start playback. While the single-file player is open, clicking another MP3 switches to that track. Single files and the playlist use the same player.

The player displays embedded artwork, title, artist, and album. A music symbol appears when artwork is missing; the file name is used when there is no title. Titles can occupy up to three lines. When changing tracks, the previous presentation remains until the new metadata can be displayed together.

The player window can be moved and resized. It uses normal window ordering, so other applications can cover it. Native playback controls offer play/pause and additional controls depending on the available width.

Known limitation: At narrow window widths, the native controls hide the timeline. Widen the player to seek within a track. A separate, permanently visible timeline is not included in this version.

## Creating a playlist from a folder

Select exactly one folder and click the playlist toolbar button with the music-list symbol. XFinder collects MP3 files from that folder and its subfolders. If no single navigable folder is selected, the current folder is used instead.

The playlist opens in its own table window with Name, Album / Folder, and Size columns. It is temporary and read-only. Clicking a track starts it; opening the list alone does not start playback. The player docks beside the playlist, matches its height, and moves with it. Playing a single file from the file list detaches the player.

Folders form album groups. Files are collected breadth-first: tracks directly in the root folder first, then tracks in its immediate subfolders, then the next level. Tracks within each folder use natural file-name order, such as Track 2 before Track 10. Album / Folder shows the folder path, not the MP3 album metadata field.

Hidden files follow the file view's setting. Directory symlinks and packages are not traversed. Unreadable subfolders are skipped, so missing access permissions can result in an incomplete playlist.

## Controlling the playlist

The toolbar offers these actions from left to right:

- Beginning: Plays the first track in the visible list.
- Previous: Plays the preceding track in the current playback order.
- Play/Stop: Stops playback or starts the selected track. After Stop, Play restarts the track from the beginning. With no selection, playback starts at the first track in the playback order.
- Next: Plays the next track in the current playback order.
- End: Plays the last track in the visible list.
- Random/In Order: Switches between random and sequential playback. This setting persists after restarting the app.

The visible list keeps its album groups even in random mode. Switching modes retains the current track. Beginning and End still refer to the visible list; Previous and Next follow the playback order.

At the end of a file, the next track starts automatically. Playback ends after the last track in the playback order. Automatic track changes do not bring the player to the front. Closing the playlist discards the temporary list and stops its playback. Clicking the playlist button again rebuilds the list from the chosen folder.

## Favorites, locations, and permissions

The sidebar distinguishes standard favorites, imported Finder favorites, and custom XFinder favorites. Add selected folders permanently using Add to Favorites in the context menu.

Locations include iCloud Drive, Trash, AirDrop, external drives, and network volumes. Internal and virtual system volumes are excluded.

Connected iPhones are detected through Apple's media-device interface. Unlock the device and confirm that it trusts this Mac. Clicking it opens Image Capture; the iPhone is not mounted as a freely accessible file system.

macOS may restrict access to protected folders. XFinder > Configure Full Disk Access… opens System Settings. Show XFinder App in Finder helps locate the application actually running, including when launched from Xcode. Restart XFinder after changing access permissions. Importing Finder favorites may also require this access.

## Keyboard shortcuts and troubleshooting

- ⌘⇧N: New folder.
- Space: Preview the selection while the file table has keyboard focus.
- ⌘⌫: Move the selection to Trash.
- ⌘⇧.: Show or hide hidden files.
- ⌘R: Reload the folder view.
- ⌘[: Go back.
- ⌘]: Go forward.
- ⌘↑: Open the enclosing folder.
- ⌘⇧H: Open the home folder.
- ⌘,: Open Settings.

Command-key shortcuts apply to the active XFinder file window. Click that window first; help, playlist, player, and dialog windows do not target a file window in the background. Space previews files only when the file table has keyboard focus and remains a space during text entry. Use ⌘⌫ to move files to Trash; plain Delete does not delete files. Menu items display the Command-key shortcuts.

If a drop is rejected, first check whether source and destination are the same folder or the drag began in the same XFinder window. For an empty playlist, check the folder selection, MP3 extensions, and access permissions. If the MP3 timeline is missing, widen the player.

Update an existing Git checkout with git pull. Then open XFinder.xcodeproj and run the app in Xcode with ⌘R. Requirements: macOS 15 or later and Xcode 26 or later. Xcode's ⌘R Run command is separate from the Reload command with the same shortcut inside the running app.
"""#

    static let german = #"""
# XFinder – Bedienungsanleitung

Diese Anleitung beschreibt die Bedienung von XFinder 0.4. Die Hilfe folgt der in den XFinder-Einstellungen gewählten Sprache, auch bei bereits geöffnetem Hilfefenster. Bei englischer App-Sprache wird die vollständige englische Anleitung angezeigt. Die Hilfe ist auch ohne Internet in der App verfügbar: über „Hilfe > XFinder-Hilfe“ oder den Fragezeichen-Button in der Fensterleiste. Links steht das Inhaltsverzeichnis, das Suchfeld durchsucht Überschriften und Inhalte.

## Einstieg und Navigation

XFinder zeigt links Favoriten und Orte, rechts die Dateien des geöffneten Ordners. Ein Doppelklick auf einen Ordner öffnet ihn. Die Pfadleiste zeigt den aktuellen Pfad; über ihre Ordnerbestandteile kannst du nach oben navigieren.

Die Pfeile in der Fensterleiste führen zurück, vorwärts und in den übergeordneten Ordner. „Aktualisieren“ lädt die Ansicht erneut. Die Finder- und Terminal-Buttons öffnen den aktuellen Ordner in der jeweiligen App.

Die Einstellungen erreichst du über das Zahnrad oder ⌘,. Dort kannst du zwischen Deutsch und Englisch wechseln. Die Sprachwahl bleibt gespeichert. Über „Ansicht > Versteckte Dateien anzeigen“ blendest du auch normalerweise ausgeblendete Dateien ein.

## Auswahl und Tabellensortierung

Ein Klick wählt einen Eintrag aus. Mit ⌘-Klick fügst du einzelne Einträge hinzu oder entfernst sie aus der Auswahl. Mit Umschalt-Klick wählst du einen zusammenhängenden Bereich. Die Statusleiste zeigt die Anzahl ausgewählter Objekte.

Klicke auf eine Spaltenüberschrift, um nach Name, Änderungsdatum, Größe oder Art zu sortieren. Ein weiterer Klick kehrt die Richtung um. Bei Suchergebnissen lässt sich auch nach dem Ablageort sortieren. Die Datumsanzeige verwendet führende Nullen, beispielsweise 06.08.2026, 09:05.

Das Kontextmenü öffnest du mit Rechtsklick beziehungsweise Control-Klick. Aktionen für eine Auswahl beziehen sich auf die dort markierten Einträge.

## Dateien und Ordner bearbeiten

„Neuer Ordner“ erstellt einen Ordner im aktuellen Verzeichnis. „Umbenennen …“ ändert den Namen eines einzelnen ausgewählten Eintrags. „In den Papierkorb“ verschiebt die ausgewählten Objekte in den macOS-Papierkorb.

Um mehrere Objekte zusammenzufassen: Markiere die Dateien und Ordner, öffne das Kontextmenü und wähle „Neuer Ordner mit Auswahl“. XFinder erstellt einen Ordner, verschiebt die Auswahl hinein und öffnet den Umbenennen-Dialog für diesen Ordner. Dies ist eine Verschiebeaktion, keine Kopie. Fehlende Einträge werden vorab geprüft; doppelte und ineinander verschachtelte Auswahlpfade werden bereinigt.

Unter „Neue Datei“ im Kontextmenü stehen Text, Rich Text und Office-Dokumente für Word, Excel und PowerPoint zur Verfügung. Ein zusätzliches LibreOffice-/OpenOffice-Menü bietet ODT, ODS und ODP, wenn mindestens eine dieser Apps installiert ist. Ohne Installation bleibt dieses Untermenü verborgen.

## Drag & Drop und Kopierregeln

Ziehe eine Datei aus der Tabelle in einen Finder-Ordner oder auf eine andere App, beispielsweise Vorschau. Das Zielprogramm entscheidet, wie es die Datei übernimmt. Aus Finder kannst du Dateien auf die XFinder-Tabelle ziehen: Sie werden in den aktuell geöffneten Ordner kopiert. Ein Drop auf einen angezeigten Unterordner kopiert sie dort hinein.

Zwischen zwei unterschiedlichen XFinder-Fenstern werden Dateien ebenfalls kopiert. Die Quelle bleibt erhalten. Öffne dafür unterschiedliche Ordner in den beiden Fenstern.

Innerhalb desselben XFinder-Fensters sind Drops gesperrt. Ein Drop zurück in den Quellordner wird auch dann abgelehnt, wenn Quelle und Ziel in unterschiedlichen Fenstern oder Apps angezeigt werden. Dadurch entsteht keine unnötige umbenannte Kopie im selben Ordner.

Bei Namenskonflikten mit anderen Dateien im Ziel verwendet XFinder einen freien Namen wie „Datei copy“ oder „Datei copy 2“. Vorhandene Zieldateien werden nicht überschrieben. Eine Fehlermeldung weist auf Probleme bei der Dateiübernahme hin.

## Zwei angedockte Dateifenster

„Zweites Fenster andocken“ in der Fensterleiste öffnet den aktuellen Ordner in einem zweiten Fenster. Beide werden nebeneinander angeordnet. Navigation, Suche und Auswahl sind pro Fenster unabhängig; Menübefehle beziehen sich auf das aktive Dateifenster.

Beim Verschieben bewegen sich die Fenster gemeinsam. Größenänderungen gleichen ihre Höhe und angrenzenden Kanten an. Ein erneuter Klick auf den Button aktiviert das bestehende Partnerfenster. Schließen oder Vollbildmodus löst die Kopplung.

Für einen Kopiervorgang navigierst du links zum Quellordner und rechts zum Zielordner und ziehst die Datei hinüber. Die Regeln aus „Drag & Drop und Kopierregeln“ gelten auch für dieses Fensterpaar.

## Dateien suchen

Das Feld „Suchen“ beziehungsweise „Search“ durchsucht Dateinamen im aktuellen Ordner und rekursiv in dessen Unterordnern. Es handelt sich um eine Namenssuche, nicht um eine Suche innerhalb von Dokumentinhalten.

Ohne Platzhalter genügt ein Teil des Namens. Mit * ersetzt du beliebig viele Zeichen, mit ? genau ein Zeichen. Beispiele: *.pdf für PDF-Dateien, test.* für Dateien mit dem Namen test und beliebiger Erweiterung sowie report-?.pdf für Namen wie report-1.pdf.

Die zusätzliche Spalte „Ort“ zeigt den Ordner des Treffers. Lösche den Suchtext, um zur normalen Ordneransicht zurückzukehren. Große Verzeichnisbäume können Zeit benötigen; während der Suche erscheint eine Fortschrittsanzeige.

## Bilder, PDF und Quick Look

Wähle in der Dateitabelle eine oder mehrere Dateien aus und drücke die Leertaste oder klicke auf den Augen-Button für Quick Look. Die Aktion steht auch als Vorschau im Kontextmenü. Bei mehreren Dateien kannst du im Vorschaufenster durch die Auswahl navigieren.

Ein Doppelklick auf ein Bild öffnet den Bildviewer. Solange er geöffnet ist, aktualisiert ein Klick auf ein anderes Bild die Vorschau, auch aus dem anderen Dateifenster. Für PDFs und andere von macOS unterstützte Formate verwende ebenfalls die Vorschauaktion.

Andere Dateien werden mit ihrer Standardanwendung geöffnet. Erkannte Skripte erfordern vorher eine Bestätigung: XFinder prüft bekannte Skript-Endungen sowie den Shebang #! am Dateianfang. Das Unix-Ausführungsbit allein löst keine Abfrage aus; eine gewöhnliche MP3-Datei benötigt keine solche Bestätigung.

## MP3-Einzelplayer

Ein Doppelklick auf eine MP3-Datei öffnet den Audio-Player und startet die Wiedergabe. Solange der Einzelplayer geöffnet ist, wechselt ein Klick auf eine andere MP3 zum neuen Titel. Einzeldateien und Playlist verwenden denselben Player.

Der Player zeigt eingebettetes Cover, Titel, Interpret und Album. Fehlt ein Cover, erscheint ein Musiksymbol; fehlt der Titel, wird der Dateiname verwendet. Der Titel kann bis zu drei Zeilen belegen. Beim Titelwechsel bleibt die bisherige Darstellung stehen, bis die neuen Metadaten gemeinsam angezeigt werden können.

Das Playerfenster lässt sich verschieben und in der Größe ändern. Es liegt auf normaler Fensterebene und kann von anderen Apps überdeckt werden. Die native Wiedergabesteuerung bietet Abspielen/Pause und abhängig von der verfügbaren Breite weitere Bedienelemente.

Bekannte Einschränkung: Bei schmalem Playerfenster blendet die native Steuerung die Zeitleiste aus. Verbreitere das Fenster, um innerhalb des Titels zu springen. Eine eigene, dauerhaft sichtbare Zeitleiste ist in diesem Stand noch nicht enthalten.

## Playlist aus einem Ordner

Markiere genau einen Ordner und klicke auf den Playlist-Button mit dem Notenlisten-Symbol. XFinder sammelt die MP3-Dateien dieses Ordners und seiner Unterordner. Ist kein einzelner navigierbarer Ordner ausgewählt, dient der aktuell geöffnete Ordner als Quelle.

Die Playlist erscheint als eigenes Tabellenfenster mit Name, Album/Ordner und Größe. Sie ist temporär und nicht bearbeitbar. Ein Klick auf einen Titel startet ihn; das Öffnen der Liste allein startet noch keine Wiedergabe. Der Player dockt seitlich an die Playlist an, übernimmt ihre Höhe und bewegt sich mit ihr. Einzelwiedergabe aus der Dateiliste löst diese Kopplung.

Ordner bilden Albumblöcke. XFinder sammelt nach dem Prinzip der Breitensuche: zuerst Titel direkt im Ausgangsordner, dann die Titel seiner unmittelbaren Unterordner, danach die nächste Ebene. Innerhalb eines Ordners gilt die natürliche Dateinamensortierung, etwa Titel 2 vor Titel 10. Die Spalte „Album / Ordner“ bezeichnet den Dateipfad, nicht das Albumfeld der MP3-Metadaten.

Versteckte Dateien folgen der Einstellung der Dateiansicht. Verzeichnisverknüpfungen und Pakete werden beim Abstieg ausgelassen. Nicht lesbare Unterordner werden übersprungen; deshalb kann die Liste bei fehlenden Zugriffsrechten unvollständig sein.

## Playlist steuern

Die Fensterleiste enthält von links nach rechts die folgenden Aktionen:

- Anfang: Spielt den ersten Titel der sichtbaren Liste.
- Zurück: Spielt den vorherigen Titel der aktuellen Abspielreihenfolge.
- Abspielen/Stopp: Stoppt die Wiedergabe oder startet den ausgewählten Titel. Nach Stopp beginnt Abspielen wieder am Titelanfang. Ohne Auswahl beginnt die Wiedergabe mit dem ersten Titel der Abspielreihenfolge.
- Vor: Spielt den nächsten Titel der aktuellen Abspielreihenfolge.
- Ende: Spielt den letzten Titel der sichtbaren Liste.
- Zufall/Reihenfolge: Wechselt zwischen zufälliger und serieller Wiedergabe. Die Einstellung bleibt nach einem Neustart gespeichert.

Die sichtbare Liste behält ihre Albumblöcke auch im Zufallsmodus. Beim Umschalten bleibt der laufende Titel erhalten. Anfang und Ende beziehen sich weiterhin auf die sichtbare Liste; Vor und Zurück folgen der Abspielreihenfolge.

Am Dateiende startet automatisch der nächste Titel. Nach dem letzten Titel der Abspielreihenfolge endet die Wiedergabe. Automatische Titelwechsel holen den Player nicht nach vorn. Das Schließen der Playlist verwirft die temporäre Liste und stoppt ihre Wiedergabe. Ein erneuter Klick auf den Playlist-Button erstellt die Liste neu aus dem gewählten Ordner.

## Favoriten, Orte und Zugriffsrechte

Die Seitenleiste unterscheidet Standardfavoriten, importierte Finder-Favoriten und eigene XFinder-Favoriten. Ausgewählte Ordner kannst du über „Zu Favoriten hinzufügen“ im Kontextmenü dauerhaft aufnehmen.

Unter „Orte“ erscheinen unter anderem iCloud Drive, Papierkorb, AirDrop sowie externe Laufwerke und Netzwerkvolumes. Interne und virtuelle Systemvolumes werden ausgeblendet.

Angeschlossene iPhones werden über Apples Mediengeräteschnittstelle erkannt. Entsperre das Gerät und bestätige das Vertrauen zu diesem Mac. Ein Klick öffnet „Digitale Bilder“; das iPhone wird nicht als frei zugängliches Dateisystem eingebunden.

macOS kann den Zugriff auf geschützte Ordner beschränken. Über „XFinder > Vollzugriff auf Festplatte konfigurieren …“ öffnest du die Systemeinstellungen. „XFinder-App im Finder anzeigen“ hilft, die tatsächlich gestartete App zu finden, auch bei einem Start aus Xcode. Starte XFinder nach einer Änderung der Zugriffsrechte neu. Auch das Importieren von Finder-Favoriten kann diesen Zugriff benötigen.

## Tastenkürzel und Hilfe bei Problemen

- ⌘⇧N: Neuer Ordner.
- Leertaste: Vorschau der Auswahl, wenn die Dateitabelle den Tastaturfokus hat.
- ⌘⌫: Auswahl in den Papierkorb verschieben.
- ⌘⇧.: Versteckte Dateien ein- oder ausblenden.
- ⌘R: Ordneransicht aktualisieren.
- ⌘[: Zurück navigieren.
- ⌘]: Vorwärts navigieren.
- ⌘↑: Übergeordneten Ordner öffnen.
- ⌘⇧H: Benutzerordner öffnen.
- ⌘,: Einstellungen öffnen.

Die Kürzel mit ⌘ gelten für das aktive XFinder-Dateifenster. Klicke dieses Fenster zuerst an; Hilfe, Playlist, Player und Dialogfenster steuern kein Dateifenster im Hintergrund. Die Leertaste öffnet die Vorschau nur bei Tastaturfokus in der Dateitabelle und bleibt bei Texteingaben ein Leerzeichen. Zum Verschieben in den Papierkorb dient ⌘⌫; die einfache Löschtaste löscht keine Dateien. Menüeinträge zeigen die Kürzel mit ⌘ an.

Bei einem abgelehnten Drop prüfe zuerst, ob Quelle und Ziel derselbe Ordner sind oder der Drag im selben XFinder-Fenster begonnen wurde. Bei einer leeren Playlist prüfe die Ordnerauswahl, MP3-Dateiendungen und Zugriffsrechte. Fehlt die MP3-Zeitleiste, verbreitere den Player.

Für einen bestehenden Git-Checkout lädst du Aktualisierungen mit git pull. Öffne anschließend XFinder.xcodeproj und starte die App in Xcode mit ⌘R. Voraussetzungen: macOS 15 oder neuer, Xcode 26 oder neuer. Der Xcode-Startbefehl ⌘R ist vom gleichlautenden Aktualisieren-Befehl innerhalb der laufenden App zu unterscheiden.
"""#
}
// END GENERATED USER GUIDE
