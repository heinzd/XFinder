import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: BrowserViewModel

    var body: some View {
        List {
            Section(model.text("Favorites")) {
                ForEach(model.favorites) { location in
                    SidebarRow(location: location)
                }
            }

            Section(model.text("Locations")) {
                ForEach(model.locations) { location in
                    SidebarRow(location: location)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    model.addCurrentFolderToFavorites()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(model.text("Add Current Folder to Favorites"))

                Button {
                    model.showHiddenFiles.toggle()
                } label: {
                    Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
                }
                .buttonStyle(.borderless)
                .help(model.showHiddenFiles ? model.text("Hide hidden files") : model.text("Show hidden files"))

                Spacer()
            }
            .padding(10)
        }
    }
}

private struct SidebarRow: View {
    @EnvironmentObject private var model: BrowserViewModel
    let location: SidebarLocation

    var body: some View {
        Button {
            model.open(location)
        } label: {
            Label(location.title, systemImage: location.systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isCurrentLocation
                ? Color.accentColor.opacity(0.18)
                : Color.clear
        )
        .contextMenu {
            if location.isCustom {
                Button(model.text("Remove from Favorites"), role: .destructive) {
                    model.removeFavorite(location)
                }
            }
        }
    }

    private var isCurrentLocation: Bool {
        !location.opensExternally
            && model.currentURL.standardizedFileURL == location.url.standardizedFileURL
    }
}
