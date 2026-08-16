import SwiftUI

struct PathBarView: View {
    @EnvironmentObject private var model: BrowserViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(components.enumerated()), id: \.offset) { index, component in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button {
                        model.navigate(to: component.url)
                    } label: {
                        Label(component.title, systemImage: component.systemImage)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 34)
        .background(.bar)
    }

    private var components: [PathComponent] {
        let pathComponents = model.currentURL.standardizedFileURL.pathComponents
        var path = ""
        return pathComponents.map { component in
            if component == "/" {
                path = "/"
                return PathComponent(title: "Macintosh HD", systemImage: "internaldrive", url: URL(fileURLWithPath: "/", isDirectory: true))
            }
            path = (path as NSString).appendingPathComponent(component)
            return PathComponent(title: component, systemImage: "folder", url: URL(fileURLWithPath: path, isDirectory: true))
        }
    }
}

private struct PathComponent {
    let title: String
    let systemImage: String
    let url: URL
}

