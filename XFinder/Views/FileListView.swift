import AppKit
import SwiftUI

struct FileListView: View {
    @EnvironmentObject private var model: BrowserViewModel
    let searchText: String

    var body: some View {
        Table(model.displayedItems(matching: searchText), selection: $model.selectedItemIDs) {
            TableColumn(model.text("Name")) { item in
                HStack(spacing: 4) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 13, height: 13)
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 220, ideal: 380)

            TableColumn(model.text("Date Modified")) { item in
                Text(item.formattedModificationDate)
                    .foregroundStyle(.secondary)
            }
            .width(min: 135, ideal: 170, max: 220)

            TableColumn(model.text("Size")) { item in
                Text(item.formattedSize)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90, max: 120)

            TableColumn(model.text("Kind")) { item in
                Text(item.isDirectory ? model.text("Folder") : item.kind)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 180)

            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                TableColumn(model.text("Location")) { item in
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
