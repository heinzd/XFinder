import AppKit
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
    }
}

private struct XFinderCommands: Commands {
    @FocusedObject private var focusedModel: BrowserViewModel?

    var body: some Commands {
        CommandGroup(after: .newItem) {
            if let model = focusedModel {
                Button(model.text("New Folder")) {
                    model.createFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button(model.text("Rename…")) {
                    model.beginRename()
                }
                .disabled(model.selectedItem == nil)

                Button(model.text("Quick Look")) {
                    model.previewSelection()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!model.canPreviewSelection)

                Button(model.text("Move to Trash")) {
                    model.moveSelectionToTrash()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selectedItems.isEmpty)
            }
        }

        CommandMenu(focusedModel?.text("View") ?? "View") {
            if let model = focusedModel {
                Toggle(model.text("Show hidden files"), isOn: Binding(
                    get: { model.showHiddenFiles },
                    set: { model.showHiddenFiles = $0 }
                ))
                    .keyboardShortcut(".", modifiers: [.command, .shift])

                Button(model.text("Reload")) {
                    model.reload()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        CommandMenu(focusedModel?.text("Go") ?? "Go") {
            if let model = focusedModel {
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
        }

        CommandGroup(after: .appInfo) {
            if let model = focusedModel {
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
            .focusedSceneObject(model)
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
private final class DockedPair: NSObject {
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
        NotificationCenter.default.removeObserver(self)
        onDetach()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
