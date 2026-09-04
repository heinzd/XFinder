import AppKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: BrowserViewModel
    @ObservedObject private var networkDiscovery = NetworkServerDiscovery.shared

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

                DisclosureGroup {
                    ForEach(networkServers) { server in
                        if server.shares.isEmpty {
                            networkServerButton(server)
                        } else {
                            DisclosureGroup {
                                ForEach(server.shares) { location in
                                    SidebarRow(location: location)
                                }
                                if server.connectionURL != nil {
                                    networkServerButton(server, compact: true)
                                }
                            } label: {
                                Label(server.name, systemImage: "server.rack")
                            }
                        }
                    }
                } label: {
                    Label(model.text("Network"), systemImage: "network")
                }
                .help(model.text("Discovered file servers and mounted network shares"))
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

    @ViewBuilder
    private func networkServerButton(_ server: NetworkSidebarServer, compact: Bool = false) -> some View {
        Button {
            if let url = server.connectionURL {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Label(
                compact ? model.text("Connect to Server…") : server.name,
                systemImage: compact ? "network" : "server.rack"
            )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(server.connectionURL == nil)
        .help(server.connectionURL == nil
              ? model.text("Server discovered; address is still being resolved")
              : model.text("Connect to Server"))
    }

    private struct NetworkSidebarServer: Identifiable {
        let name: String
        let connectionURL: URL?
        let shares: [SidebarLocation]
        var id: String { name.localizedLowercase }
    }

    private var ungroupedLocations: [SidebarLocation] {
        model.locations.filter { $0.networkServer == nil && $0.systemImage != "network" }
    }

    private var networkServers: [NetworkSidebarServer] {
        var names: [String: String] = [:]
        var urls: [String: URL] = [:]
        var shares: [String: [SidebarLocation]] = [:]

        for endpoint in networkDiscovery.servers {
            let key = endpoint.name.localizedLowercase
            names[key] = endpoint.name
            if let url = endpoint.connectionURL { urls[key] = url }
        }
        for location in model.locations where location.systemImage == "network" {
            let serverName = location.networkServer ?? location.title
            let key = serverName.localizedLowercase
            names[key] = names[key] ?? serverName
            shares[key, default: []].append(location)
        }

        return names.map { key, name in
            NetworkSidebarServer(
                name: name,
                connectionURL: urls[key],
                shares: shares[key, default: []].sorted {
                    $0.title.localizedStandardCompare($1.title) == .orderedAscending
                }
            )
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
