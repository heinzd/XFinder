import SwiftUI

@main
@MainActor
struct XFinderApp: App {
    @StateObject private var model = BrowserViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1180, height: 720)
        .commands {
            XFinderCommands(model: model)
        }
    }
}

private struct XFinderCommands: Commands {
    @ObservedObject var model: BrowserViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button(model.text("New Folder")) {
                model.createFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button(model.text("Rename…")) {
                model.beginRename()
            }
            .disabled(model.selectedItem == nil)

            Button(model.text("Move to Trash")) {
                model.moveSelectionToTrash()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.selectedItems.isEmpty)
        }

        CommandMenu(model.text("View")) {
            Toggle(model.text("Show hidden files"), isOn: $model.showHiddenFiles)
                .keyboardShortcut(".", modifiers: [.command, .shift])

            Button(model.text("Reload")) {
                model.reload()
            }
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

        CommandGroup(after: .appInfo) {
            Button(model.text("Settings") + "…") {
                model.isShowingSettings = true
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button(model.text("Show XFinder App in Finder")) {
                model.revealApplicationInFinder()
            }

            Button(model.text("Configure Full Disk Access…")) {
                model.openFullDiskAccessSettings()
            }
        }
    }
}
