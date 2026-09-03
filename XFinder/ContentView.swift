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
            SettingsSheet()
                .environmentObject(model)
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

            Button(action: model.playCurrentFolderPlaylist) {
                Image(systemName: "music.note.list")
            }
            .disabled(model.isBuildingPlaylist)
            .help(model.language == .german
                ? "Temporäre MP3-Wiedergabeliste abspielen"
                : "Play Temporary MP3 Playlist")

            Button {
                model.isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help(model.text("Settings"))
        }

        ToolbarItem(placement: .automatic) {
            if model.isSearching || model.isBuildingPlaylist {
                ProgressView()
                    .controlSize(.small)
            }
        }
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

private struct SettingsSheet: View {
    @EnvironmentObject private var model: BrowserViewModel
    @Environment(\.dismiss) private var dismiss

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
                        Picker("", selection: $model.language) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
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
