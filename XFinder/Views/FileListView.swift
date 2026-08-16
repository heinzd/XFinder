import AppKit
import SwiftUI

struct FileListView: View {
    @EnvironmentObject private var model: BrowserViewModel
    @State private var sortOrder = [KeyPathComparator(\FileItem.sortableName)]
    let searchText: String

    var body: some View {
        Table(
            sortedItems,
            selection: $model.selectedItemIDs,
            sortOrder: $sortOrder
        ) {
            TableColumn(model.text("Name"), value: \FileItem.sortableName) { item in
                fileNameCell(for: item)
            }
            .width(min: 220, ideal: 380)

            TableColumn(
                model.text("Date Modified"),
                value: \FileItem.sortableModificationDate
            ) { item in
                Text(item.formattedModificationDate)
                    .foregroundStyle(.secondary)
            }
            .width(min: 135, ideal: 170, max: 220)

            TableColumn(model.text("Size"), value: \FileItem.sortableSize) { item in
                Text(item.formattedSize)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90, max: 120)

            TableColumn(model.text("Kind"), value: \FileItem.sortableKind) { item in
                Text(item.isDirectory ? model.text("Folder") : item.kind)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 180)

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TableColumn(
                    model.text("Location"),
                    value: \FileItem.sortableLocation
                ) { item in
                    Text(model.relativeLocation(for: item))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 220)
            }
        }
        .font(.body)
        .controlSize(.mini)
        .environment(\.defaultMinListRowHeight, 14)
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .dropDestination(for: URL.self) { urls, _ in
            model.copyDroppedItems(urls, to: model.currentURL)
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { selection in
            Menu(model.text("New File")) {
                ForEach(model.standardNewFileKinds) { kind in
                    Button(model.text(kind.title)) {
                        model.createFile(kind)
                    }
                }

                if !model.openDocumentNewFileKinds.isEmpty {
                    Divider()
                    Menu(model.openDocumentMenuTitle) {
                        ForEach(model.openDocumentNewFileKinds) { kind in
                            Button(model.text(kind.title)) {
                                model.createFile(kind)
                            }
                        }
                    }
                }
            }
            Button(model.newFolderWithSelectionTitle(selection.count)) {
                model.createFolder(with: selection)
            }
            .disabled(selection.isEmpty)
            Divider()
            Button(model.text("Open")) {
                openFirst(in: selection)
            }
            Button(model.text("Quick Look")) {
                model.preview(selection)
            }
            .disabled(!canPreview(selection))
            Divider()
            Button(model.text("Rename…")) {
                model.selectedItemIDs = selection
                model.beginRename()
            }
            .disabled(selection.count != 1)
            Button(model.text("Show in Finder")) {
                model.selectedItemIDs = selection
                model.revealSelectionInFinder()
            }
            Button(model.text("Add to Favorites")) {
                model.selectedItemIDs = selection
                model.addSelectionToFavorites()
            }
            .disabled(!canAddToFavorites(selection))
            Divider()
            Button(model.text("Move to Trash"), role: .destructive) {
                model.selectedItemIDs = selection
                model.moveSelectionToTrash()
            }
        } primaryAction: { selection in
            openFirst(in: selection)
        }
        .onDeleteCommand(perform: model.moveSelectionToTrash)
    }

    private var sortedItems: [FileItem] {
        model.displayedItems(matching: searchText).sorted(using: sortOrder)
    }

    @ViewBuilder
    private func fileNameCell(for item: FileItem) -> some View {
        let cell = HStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .draggable(item.url)

        if item.canNavigateInto {
            cell.dropDestination(for: URL.self) { urls, _ in
                model.copyDroppedItems(urls, to: item.url)
            }
        } else {
            cell
        }
    }

    private func openFirst(in selection: Set<FileItem.ID>) {
        guard let id = selection.first,
              let item = model.item(withID: id) else { return }
        model.open(item)
    }

    private func canAddToFavorites(_ selection: Set<FileItem.ID>) -> Bool {
        guard selection.count == 1,
              let id = selection.first,
              let item = model.item(withID: id) else { return false }
        return item.canNavigateInto
    }

    private func canPreview(_ selection: Set<FileItem.ID>) -> Bool {
        selection.contains { id in
            guard let item = model.item(withID: id) else { return false }
            return !item.isDirectory
        }
    }
}
