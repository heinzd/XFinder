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

            if !model.customFavorites.isEmpty {
                Section(model.text("Custom Favorites")) {
                    ForEach(model.customFavorites) { location in
                        SidebarRow(location: location)
                    }
                }
            }

            Section(model.text("Locations")) {
                ForEach(ungroupedLocations) { location in
                    SidebarRow(location: location)
                }

                ForEach(networkServers, id: \.name) { server in
                    DisclosureGroup {
                        ForEach(server.shares) { location in
                            SidebarRow(location: location)
                        }
                    } label: {
                        Label(server.name, systemImage: "network")
                    }
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

    private var ungroupedLocations: [SidebarLocation] {
        model.locations.filter { $0.networkServer == nil }
    }

    private var networkServers: [(name: String, shares: [SidebarLocation])] {
        Dictionary(grouping: model.locations.compactMap { location in
            location.networkServer.map { ($0, location) }
        }, by: { $0.0 })
        .map { name, entries in
            (name: name, shares: entries.map(\.1).sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            })
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
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
