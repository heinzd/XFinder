import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: BrowserViewModel
    @State private var searchText = ""
    @StateObject private var windowHandle = BrowserWindowHandle()
    let dockingRequestID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            VStack(spacing: 0) {
                PathBarView()
                Divider()
                FileListView(searchText: searchText)
                Divider()
                StatusBar(searchText: searchText)
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .background(BrowserWindowReader { window in
            windowHandle.window = window
            BrowserCommandContext.shared.register(window, model: model)
            BrowserWindowDocking.shared.attach(window, requestID: dockingRequestID)
        })
        .navigationTitle(model.currentURL.lastPathComponentOrRoot)
        .toolbar {
            BrowserToolbar(windowHandle: windowHandle)
        }
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: Text(model.text("Search"))
        )
        .alert("XFinder", isPresented: errorPresented) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? model.text("Unknown error"))
        }
        .alert(model.text("Run Script?"), isPresented: executionConfirmationPresented) {
            Button(model.text("Cancel"), role: .cancel) {
                model.cancelPendingExecution()
            }
            Button(model.text("Run"), role: .destructive) {
                model.confirmPendingExecution()
            }
        } message: {
            if let item = model.pendingExecutionItem {
                Text(model.executionConfirmationMessage(for: item))
            }
        }
        .sheet(item: $model.renameTarget) { item in
            RenameSheet(item: item)
                .environmentObject(model)
        }
        .sheet(isPresented: $model.isShowingSettings) {
            SettingsSheet(model: model)
        }
        .onChange(of: searchText) { _, query in
            model.searchRecursively(matching: query)
        }
        .onChange(of: model.currentURL) { _, _ in
            model.searchRecursively(matching: searchText)
        }
        .onChange(of: model.showHiddenFiles) { _, _ in
            model.searchRecursively(matching: searchText)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            model.reloadVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            model.reloadVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            model.reloadVolumes()
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }

    private var executionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { model.pendingExecutionItem != nil },
            set: { if !$0 { model.cancelPendingExecution() } }
        )
    }
}

private struct BrowserToolbar: ToolbarContent {
    @EnvironmentObject private var model: BrowserViewModel
    @Environment(\.openWindow) private var openWindow
    let windowHandle: BrowserWindowHandle

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: model.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .help(model.text("Back"))

            Button(action: model.goForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help(model.text("Forward"))

            Button(action: model.goUp) {
                Image(systemName: "arrow.up")
            }
            .disabled(model.currentURL.path == "/")
            .help(model.text("Enclosing Folder"))
        }

        ToolbarItemGroup(placement: .automatic) {
            Button {
                guard let window = windowHandle.window else { return }
                if window.styleMask.contains(.fullScreen) {
                    model.errorMessage = model.language == .german
                        ? "Bitte zuerst den Vollbildmodus verlassen."
                        : "Please leave full screen before docking a second window."
                    return
                }
                if let partner = BrowserWindowDocking.shared.partner(of: window) {
                    partner.makeKeyAndOrderFront(nil)
                    return
                }
                let request = DockedBrowserRequest(startPath: model.currentURL.path)
                guard BrowserWindowDocking.shared.prepare(request, beside: window) else { return }
                openWindow(id: "browser", value: request)
            } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .help(model.language == .german ? "Zweites Fenster andocken" : "Dock Second Window")

            Button(action: model.createFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .help(model.text("New Folder"))

            Button(action: model.reload) {
                Image(systemName: "arrow.clockwise")
            }
            .help(model.text("Reload"))

            Button(action: model.previewSelection) {
                Image(systemName: "eye")
            }
            .disabled(!model.canPreviewSelection)
            .help(model.text("Quick Look"))

            Button(action: model.revealCurrentFolderInFinder) {
                Image(systemName: "arrow.up.forward.app")
            }
            .help(model.text("Open the current folder in the original Finder"))

            Button(action: model.openCurrentFolderInTerminal) {
                Image(systemName: "terminal")
            }
            .help(model.text("Open Current Folder in Terminal"))

            Button {
                model.playCurrentFolderPlaylist {
                    openWindow(id: "playlist")
                }
            } label: {
                Image(systemName: "music.note.list")
            }
            .disabled(model.isBuildingPlaylist)
            .help(model.language == .german
                ? "MP3-Playlist aus ausgewähltem oder aktuellem Ordner"
                : "MP3 Playlist from Selected or Current Folder")

            Button {
                model.isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help(model.text("Settings"))

            Button {
                openWindow(id: "help")
            } label: {
                Label(model.language == .german ? "XFinder-Hilfe" : "XFinder Help", systemImage: "questionmark.circle")
            }
            .help(model.language == .german ? "XFinder-Hilfe" : "XFinder Help")
        }

        ToolbarItem(placement: .automatic) {
            if model.isSearching || model.isBuildingPlaylist {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

struct PlaylistView: View {
    @ObservedObject private var player = PlaylistPlayerController.shared

    private var selection: Binding<FileItem.ID?> {
        Binding(
            get: { player.selectedID },
            set: { if let id = $0 { player.play(id) } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Table(player.items, selection: selection) {
                TableColumn(player.text("Name", "Name")) { item in
                    HStack(spacing: 4) {
                        Image(systemName: player.selectedID == item.id ? "speaker.wave.2.fill" : "music.note")
                            .frame(width: 16)
                        Text(item.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .width(min: 200, ideal: 330)

                TableColumn(player.text("Album / Folder", "Album / Ordner")) { item in
                    Text(player.album(for: item))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .width(min: 130, ideal: 230)

                TableColumn(player.text("Size", "Größe")) { item in
                    Text(item.formattedSize)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 90, max: 120)
            }
            .font(.body)
            .controlSize(.mini)
            .environment(\.defaultMinListRowHeight, 14)
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            Divider()
            HStack {
                Text("\(player.items.count) " + player.text("tracks", "Titel"))
                Spacer()
                Text(player.rootURL?.path ?? "")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 26)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .navigationTitle(player.text("Playlist", "Wiedergabeliste"))
        .background(BrowserWindowReader { window in
            player.setPlaylistWindow(window)
        })
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button(action: player.first) {
                    Label(player.text("Beginning", "Anfang"), systemImage: "backward.end.fill")
                }
                .help(player.text("First track", "Erster Titel"))
                .disabled(player.items.isEmpty)

                Button(action: player.previous) {
                    Label(player.text("Previous", "Zurück"), systemImage: "backward.fill")
                }
                .help(player.text("Previous track", "Vorheriger Titel"))
                .disabled(!player.canGoBack)

                Button(action: player.togglePlayStop) {
                    Label(
                        player.canStopPlaylist ? player.text("Stop", "Stopp") : player.text("Play", "Abspielen"),
                        systemImage: player.canStopPlaylist ? "stop.fill" : "play.fill"
                    )
                }
                .help(player.canStopPlaylist ? player.text("Stop playback", "Wiedergabe stoppen") : player.text("Play selected track", "Ausgewählten Titel abspielen"))
                .disabled(player.items.isEmpty)

                Button(action: player.next) {
                    Label(player.text("Next", "Vor"), systemImage: "forward.fill")
                }
                .help(player.text("Next track", "Nächster Titel"))
                .disabled(!player.canGoForward)

                Button(action: player.last) {
                    Label(player.text("End", "Ende"), systemImage: "forward.end.fill")
                }
                .help(player.text("Last track", "Letzter Titel"))
                .disabled(player.items.isEmpty)

                Button(action: player.toggleOrder) {
                    Label(
                        player.isRandom ? player.text("Random", "Zufall") : player.text("In Order", "Reihenfolge"),
                        systemImage: player.isRandom ? "shuffle" : "list.number"
                    )
                }
                .help(player.isRandom
                    ? player.text("Random playback — switch to in order", "Zufällige Wiedergabe – auf Reihenfolge umschalten")
                    : player.text("Playback in order — switch to random", "Wiedergabe in Reihenfolge – auf Zufall umschalten"))
            }
        }
        .onDisappear { player.closePlaylist() }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var model: BrowserViewModel
    let searchText: String

    var body: some View {
        HStack {
            Text(statusText)
            Spacer()
            if model.selectedItems.count > 1 {
                Text(model.selectionCountText(model.selectedItems.count))
            } else if let selected = model.selectedItem {
                Text(selected.url.path)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
    }

    private var statusText: String {
        if searchText.isEmpty {
            return model.itemCountText(model.items.count)
        }
        if model.isSearching {
            return model.text("Searching subfolders…")
        }
        return model.resultCountText(model.displayedItems(matching: searchText).count)
    }
}

private struct RenameSheet: View {
    @EnvironmentObject private var model: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    let item: FileItem
    @State private var name: String

    init(item: FileItem) {
        self.item = item
        _name = State(initialValue: item.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(model.renameTitle(for: item.name))
                .font(.headline)

            TextField(model.text("Name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(rename)

            HStack {
                Spacer()
                Button(model.text("Cancel"), role: .cancel) {
                    model.renameTarget = nil
                    dismiss()
                }
                Button(model.text("Rename"), action: rename)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func rename() {
        model.rename(item, to: name)
        dismiss()
    }
}

@MainActor
private struct SettingsSheet: View {
    @ObservedObject private var model: BrowserViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage: AppLanguage

    init(model: BrowserViewModel) {
        self.model = model
        _selectedLanguage = State(initialValue: model.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(model.text("Settings"))
                    .font(.title2.bold())
            }

            GroupBox(model.text("General")) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 14) {
                    GridRow {
                        Text(model.text("Language"))
                        Picker("", selection: $selectedLanguage) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                        .onChange(of: selectedLanguage) { _, newLanguage in
                            // Let the segmented control finish its view update before
                            // publishing the language through BrowserViewModel.
                            DispatchQueue.main.async {
                                model.language = newLanguage
                            }
                        }
                    }

                    GridRow {
                        Text(model.text("Files"))
                        Toggle(model.text("Show hidden files"), isOn: $model.showHiddenFiles)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(model.text("Custom Favorites")) {
                VStack(alignment: .leading, spacing: 8) {
                    if model.customFavorites.isEmpty {
                        Text(model.text("No custom favorites yet."))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.customFavorites) { favorite in
                            HStack {
                                Label(favorite.title, systemImage: favorite.systemImage)
                                Spacer()
                                Button {
                                    model.removeFavorite(favorite)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .help(model.text("Remove from Favorites"))
                            }
                        }
                    }

                    Button {
                        model.addCurrentFolderToFavorites()
                    } label: {
                        Label(model.text("Add Current Folder to Favorites"), systemImage: "plus")
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(model.text("Security")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.text("Full Disk Access prevents repeated permission requests for protected folders."))
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(model.text("Show XFinder App in Finder")) {
                            model.revealApplicationInFinder()
                        }
                        Button(model.text("Configure Full Disk Access…")) {
                            model.openFullDiskAccessSettings()
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(model.text("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}

private extension URL {
    var lastPathComponentOrRoot: String {
        path == "/" ? "Macintosh HD" : lastPathComponent
    }
}
