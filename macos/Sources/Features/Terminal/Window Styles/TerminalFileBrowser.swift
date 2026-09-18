import AppKit
import SwiftUI

/// A file explorer rooted at the working directory of the focused terminal surface.
struct TerminalFileBrowser: View {
    let rootURL: URL?
    let pullRequestsVisible: Bool
    let issuesVisible: Bool
    let showFiles: () -> Void
    let showPullRequests: () -> Void
    let showIssues: () -> Void
    let openFile: (URL) -> Void

    @StateObject private var model = TerminalFileBrowserModel()
    @StateObject private var branchModel = TerminalGitBranchModel()
    @AppStorage("ghostty.fileBrowserWidth") private var browserWidth = 280.0
    @AppStorage("ghostty.fileBrowserVisible") private var isVisible = true
    @State private var resizeStartWidth: Double?
    @State private var searchText = ""
    @State private var searchVisible = false
    @State private var branchPickerVisible = false

    private let minimumWidth = 200.0
    private let maximumWidth = 520.0

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header

                if searchVisible {
                    searchField
                }

                Divider()

                content
            }
            .frame(width: browserWidth)
            .background(Color(nsColor: .windowBackgroundColor))

            resizeHandle
        }
        .onAppear {
            model.setRoot(rootURL)
            branchModel.setRoot(rootURL)
        }
        .onChange(of: rootURL) {
            model.setRoot($0)
            branchModel.setRoot($0)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: showFiles) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(
                        pullRequestsVisible || issuesVisible ? Color.secondary : Color.primary)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(
                                pullRequestsVisible || issuesVisible
                                    ? Color.clear
                                    : Color.primary.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
            .help("Files")

            Button(action: showPullRequests) {
                PullRequestSidebarIcon()
                    .foregroundStyle(pullRequestsVisible ? Color.primary : Color.secondary)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(pullRequestsVisible ? Color.primary.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Pull Requests")

            Button(action: showIssues) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(issuesVisible ? Color.primary : Color.secondary)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(issuesVisible ? Color.primary.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help("Issues")

            Button {
                branchPickerVisible.toggle()
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(branchPickerVisible ? Color.primary : Color.secondary)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(branchPickerVisible ? Color.primary.opacity(0.08) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(
                branchModel.currentBranch.isEmpty
                    ? "Branches"
                    : "Branches — \(branchModel.currentBranch)"
            )
            .popover(isPresented: $branchPickerVisible, arrowEdge: .bottom) {
                TerminalGitBranchPicker(model: branchModel) {
                    model.reload()
                }
            }

            Spacer(minLength: 8)

            Button {
                searchVisible.toggle()
                if !searchVisible { searchText = "" }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Search Files")

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh")

            Button {
                isVisible = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close File Browser")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter files...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if let root = model.root {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FileBrowserRootRow(root: root, model: model)

                    if model.isExpanded(root) {
                        ForEach(model.filteredChildren(of: root, matching: searchText)) { entry in
                            FileBrowserRow(
                                entry: entry,
                                depth: 1,
                                model: model,
                                searchText: searchText,
                                openFile: openFile)
                        }
                    }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("No Working Directory")
                    .font(.headline)
                Text("Focus a terminal to browse its files.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var resizeHandle: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)

            Rectangle()
                .fill(Color.clear)
                .frame(width: 7)
                .contentShape(Rectangle())
        }
        .frame(width: 7)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if resizeStartWidth == nil { resizeStartWidth = browserWidth }
                    let initialWidth = resizeStartWidth ?? browserWidth
                    browserWidth = min(maximumWidth, max(minimumWidth, initialWidth + value.translation.width))
                }
                .onEnded { _ in resizeStartWidth = nil }
        )
    }
}

private struct PullRequestSidebarIcon: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 16
            let lineWidth = max(1, 1.35 * scale)

            var path = Path()
            path.move(to: CGPoint(x: 4 * scale, y: 5.5 * scale))
            path.addLine(to: CGPoint(x: 4 * scale, y: 12.5 * scale))
            path.move(to: CGPoint(x: 5.5 * scale, y: 3.5 * scale))
            path.addLine(to: CGPoint(x: 9 * scale, y: 3.5 * scale))
            path.addCurve(
                to: CGPoint(x: 12 * scale, y: 6.5 * scale),
                control1: CGPoint(x: 11 * scale, y: 3.5 * scale),
                control2: CGPoint(x: 12 * scale, y: 4.5 * scale))
            path.addLine(to: CGPoint(x: 12 * scale, y: 10.5 * scale))
            context.stroke(
                path,
                with: .foreground,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            for point in [CGPoint(x: 4, y: 3.5), CGPoint(x: 4, y: 13.5), CGPoint(x: 12, y: 12.5)] {
                let center = CGPoint(x: point.x * scale, y: point.y * scale)
                let radius = 1.55 * scale
                let circle = Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2))
                context.stroke(circle, with: .foreground, lineWidth: lineWidth)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

private struct FileBrowserRootRow: View {
    let root: URL
    @ObservedObject var model: TerminalFileBrowserModel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .rotationEffect(model.isExpanded(root) ? .degrees(90) : .zero)
                .frame(width: 10)
            Image(systemName: model.isExpanded(root) ? "folder.fill" : "folder")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(root.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.primary.opacity(0.07))
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(root) }
        .contextMenu {
            FileBrowserContextMenu(target: root, isDirectory: true, model: model)
        }
    }
}

private struct FileBrowserRow: View {
    let entry: TerminalFileBrowserModel.Entry
    let depth: Int
    @ObservedObject var model: TerminalFileBrowserModel
    let searchText: String
    let openFile: (URL) -> Void

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(model.isExpanded(entry.url) ? .degrees(90) : .zero)
                        .frame(width: 10)
                } else {
                    Color.clear.frame(width: 10, height: 1)
                }

                Image(systemName: entry.isDirectory
                      ? (model.isExpanded(entry.url) ? "folder.fill" : "folder")
                      : entry.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.isDirectory ? Color.secondary : entry.iconColor)
                    .frame(width: 16)

                Text(entry.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .foregroundStyle(entry.isHidden ? .secondary : .primary)

                Spacer(minLength: 8)
            }
            .padding(.leading, CGFloat(depth) * 16 + 8)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(rowBackground)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: activate)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(entry.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { activate() }
            .contextMenu {
                if !entry.isDirectory {
                    Button("Open in Vim Split") { openFile(entry.url) }
                    Button("Open Externally") { NSWorkspace.shared.open(entry.url) }
                    Divider()
                }
                FileBrowserContextMenu(
                    target: entry.url,
                    isDirectory: entry.isDirectory,
                    model: model)
                Divider()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                Divider()
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url.path, forType: .string)
                }
            }

            if entry.isDirectory, model.isExpanded(entry.url) {
                if model.isLoading(entry.url) {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, CGFloat(depth + 1) * 16 + 34)
                        .frame(height: 26)
                } else {
                    ForEach(model.filteredChildren(of: entry.url, matching: searchText)) { child in
                        FileBrowserRow(
                            entry: child,
                            depth: depth + 1,
                            model: model,
                            searchText: searchText,
                            openFile: openFile)
                    }
                }
            }
        }
    }

    private var rowBackground: Color {
        if model.isSelected(entry.url) { return Color.primary.opacity(0.16) }
        if hovering { return Color.primary.opacity(0.07) }
        return .clear
    }

    private func activate() {
        model.select(entry.url)
        if entry.isDirectory {
            model.toggle(entry.url)
        } else {
            openFile(entry.url)
        }
    }
}

private struct FileBrowserContextMenu: View {
    let target: URL
    let isDirectory: Bool
    @ObservedObject var model: TerminalFileBrowserModel

    private var destination: URL {
        isDirectory ? target : target.deletingLastPathComponent()
    }

    var body: some View {
        Button("New File…") { model.createItem(in: destination, directory: false) }
        Button("New Folder…") { model.createItem(in: destination, directory: true) }
        Divider()
        Button("Copy") { model.copy(target) }
        Button("Paste") { model.paste(into: destination) }
            .disabled(!model.canPaste)
    }
}

@MainActor
private final class TerminalFileBrowserModel: ObservableObject {
    struct Entry: Identifiable, Hashable, Sendable {
        var id: URL { url }

        let url: URL
        let name: String
        let isDirectory: Bool
        let isHidden: Bool

        var iconName: String {
            switch url.pathExtension.lowercased() {
            case "swift": return "swift"
            case "zig", "json", "yaml", "yml", "toml": return "curlybraces"
            case "sql": return "tablecells"
            case "md", "txt": return "doc.text"
            case "png", "jpg", "jpeg", "gif", "webp", "svg": return "photo"
            case "js", "ts", "tsx", "jsx": return "j.square"
            default: return "doc"
            }
        }

        var iconColor: Color {
            switch url.pathExtension.lowercased() {
            case "swift": return .orange
            case "js", "jsx": return .yellow
            case "ts", "tsx": return .blue
            case "json", "yaml", "yml", "toml": return .yellow
            case "sql": return .cyan
            default: return .secondary
            }
        }
    }

    @Published private(set) var root: URL?
    @Published private var children: [URL: [Entry]] = [:]
    @Published private var expanded: Set<URL> = []
    @Published private var loading: Set<URL> = []
    @Published private var selected: URL?

    func setRoot(_ url: URL?) {
        // Moving focus to sidebar controls or a newly-created terminal split can
        // temporarily clear the focused PWD. Keep showing the last valid root
        // instead of flashing an empty state and discarding expansion state.
        guard let normalized = url?.standardizedFileURL else { return }
        guard normalized != root else { return }
        root = normalized
        children.removeAll()
        expanded = [normalized]
        loading.removeAll()
        selected = nil
        load(normalized)
    }

    func reload() {
        guard let root else { return }
        let directories = [root] + Array(expanded)
        children.removeAll()
        loading.removeAll()
        directories.forEach { load($0) }
    }

    func isExpanded(_ url: URL) -> Bool { expanded.contains(url) }
    func isLoading(_ url: URL) -> Bool { loading.contains(url) }
    func isSelected(_ url: URL) -> Bool { selected == url }
    func select(_ url: URL) { selected = url }

    var canPaste: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
        ])
    }

    func createItem(in directory: URL, directory isDirectory: Bool) {
        let alert = NSAlert()
        alert.messageText = isDirectory ? "New Folder" : "New File"
        alert.informativeText = "Enter a name for the new \(isDirectory ? "folder" : "file")."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = isDirectory ? "Folder name" : "File name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidItemName(name) else {
            showError("Invalid Name", detail: "Names cannot be empty, '.', '..', or contain '/'.")
            return
        }

        let url = directory.appendingPathComponent(name, isDirectory: isDirectory)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            showError("Item Already Exists", detail: "An item named “\(name)” already exists in this folder.")
            return
        }

        do {
            if isDirectory {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                guard FileManager.default.createFile(atPath: url.path, contents: Data()) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            expanded.insert(directory)
            load(directory, force: true)
            selected = url
        } catch {
            showError("Could Not Create Item", detail: error.localizedDescription)
        }
    }

    func copy(_ url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    func paste(into directory: URL) {
        guard let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        else { return }

        do {
            for source in urls {
                let destination = availableDestination(for: source, in: directory)
                try FileManager.default.copyItem(at: source, to: destination)
                selected = destination
            }
            expanded.insert(directory)
            load(directory, force: true)
        } catch {
            showError("Could Not Paste Item", detail: error.localizedDescription)
        }
    }

    func toggle(_ url: URL) {
        if expanded.remove(url) == nil {
            expanded.insert(url)
            if children[url] == nil { load(url) }
        }
    }

    func filteredChildren(of url: URL, matching query: String) -> [Entry] {
        let entries = children[url] ?? []
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func load(_ url: URL, force: Bool = false) {
        if force {
            children[url] = nil
            loading.remove(url)
        }
        guard !loading.contains(url) else { return }
        loading.insert(url)

        Task {
            let entries = await Task.detached(priority: .userInitiated) {
                let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .nameKey]
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: Array(keys),
                    options: [])) ?? []

                return urls.compactMap { child -> Entry? in
                    guard let values = try? child.resourceValues(forKeys: keys) else { return nil }
                    return Entry(
                        url: child,
                        name: values.name ?? child.lastPathComponent,
                        isDirectory: values.isDirectory ?? false,
                        isHidden: values.isHidden ?? false)
                }
                .sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
            }.value

            children[url] = entries
            loading.remove(url)
        }
    }

    private func isValidItemName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    private func availableDestination(for source: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        let extensionName = source.pathExtension
        let baseName = source.deletingPathExtension().lastPathComponent
        var copyNumber = 1
        repeat {
            let suffix = copyNumber == 1 ? " copy" : " copy \(copyNumber)"
            let name = extensionName.isEmpty
                ? baseName + suffix
                : baseName + suffix + "." + extensionName
            destination = directory.appendingPathComponent(name)
            copyNumber += 1
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension TerminalController {
    /// Opens a file in Vim in a new split to the right of the current split tree.
    @MainActor
    func openFileInVimSplit(_ url: URL) {
        guard let editorExecutable = Self.editorExecutable else {
            showEditorUnavailable(for: url)
            return
        }

        if case let .neovim(neovimURL) = editorExecutable,
           let editorSurface = fileBrowserEditorSurface,
           surfaceTree.contains(editorSurface),
           let socket = fileBrowserEditorSocket {
            let process = Process()
            process.executableURL = neovimURL
            process.arguments = ["--server", socket, "--remote-tab", url.path]
            do {
                try process.run()
            } catch {
                showEditorUnavailable(for: url)
                return
            }
            focusSurface(editorSurface)
            return
        }

        guard let anchor = surfaceTree.root?.rightmostLeaf() else { return }

        var config = Ghostty.SurfaceConfiguration()
        config.workingDirectory = url.deletingLastPathComponent().path

        switch editorExecutable {
        case let .neovim(neovimURL):
            let socket = "/tmp/ghostty-file-editor-\(UUID().uuidString).sock"
            let tablineScript = socket + ".lua"
            try? Self.neovimTablineScript.write(
                toFile: tablineScript,
                atomically: true,
                encoding: .utf8)
            let tablineCommand = "luafile \(tablineScript)"
            config.command = "\(neovimURL.path.shellQuoted) --listen \(socket.shellQuoted) -c \(tablineCommand.shellQuoted) -- \(url.lastPathComponent.shellQuoted)"

            fileBrowserEditorSurface = newSplit(at: anchor, direction: .right, baseConfig: config)
            fileBrowserEditorSocket = socket

        case let .vim(vimURL):
            config.command = "\(vimURL.path.shellQuoted) -- \(url.lastPathComponent.shellQuoted)"
            fileBrowserEditorSurface = newSplit(at: anchor, direction: .right, baseConfig: config)
            fileBrowserEditorSocket = nil
        }
    }

    /// Removes the legacy Vim/Neovim split when the native editor takes over.
    @MainActor
    func closeFileBrowserEditorSplit() {
        if let editorSurface = fileBrowserEditorSurface,
           surfaceTree.contains(editorSurface) {
            closeSurface(editorSurface, withConfirmation: false)
        }

        if let socket = fileBrowserEditorSocket {
            try? FileManager.default.removeItem(atPath: socket)
            try? FileManager.default.removeItem(atPath: socket + ".lua")
        }

        fileBrowserEditorSurface = nil
        fileBrowserEditorSocket = nil
    }

    private enum EditorExecutable {
        case neovim(URL)
        case vim(URL)
    }

    private static var editorExecutable: EditorExecutable? {
        if let url = executableURL(named: "nvim", additionalDirectories: [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
        ]) { return .neovim(url) }

        if let url = executableURL(named: "vim", additionalDirectories: [
            "/usr/bin", "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
        ]) { return .vim(url) }

        return nil
    }

    private static func executableURL(named name: String, additionalDirectories: [String]) -> URL? {
        let environmentDirectories = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let userDirectories = [
            "\(home)/.local/bin",
            "\(home)/.nix-profile/bin",
            "/run/current-system/sw/bin",
        ]

        for directory in environmentDirectories + additionalDirectories + userDirectories {
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    @MainActor
    private func showEditorUnavailable(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "No Terminal Editor Found"
        alert.informativeText = "Momok could not find Neovim or Vim. Install Neovim with Homebrew (`brew install neovim`), or open this file with its default macOS application."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open in Default App")
        alert.addButton(withTitle: "Cancel")

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            NSWorkspace.shared.open(url)
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private static let neovimTablineScript = #"""
    vim.o.showtabline = 2
    vim.o.mouse = "a"

    vim.api.nvim_set_hl(0, "GhosttyEditorIconJS", { fg = "#f7df1e", bold = true })
    vim.api.nvim_set_hl(0, "GhosttyEditorIconTS", { fg = "#4daafc", bold = true })
    vim.api.nvim_set_hl(0, "GhosttyEditorIconSQL", { fg = "#22d3ee", bold = true })

    _G.GhosttyEditorCloseTab = function(tab, _, button, _)
      if button ~= "l" then return end
      if vim.fn.tabpagenr("$") <= 1 then
        vim.cmd("quit")
      else
        vim.cmd("tabclose " .. tab)
      end
    end

    vim.cmd([[
      function! GhosttyEditorCloseTab(minwid, clicks, button, mods) abort
        call v:lua.GhosttyEditorCloseTab(a:minwid, a:clicks, a:button, a:mods)
      endfunction
    ]])

    _G.GhosttyEditorTabLine = function()
      local result = ""
      local current = vim.fn.tabpagenr()
      local count = vim.fn.tabpagenr("$")

      for tab = 1, count do
        local buffers = vim.fn.tabpagebuflist(tab)
        local window = vim.fn.tabpagewinnr(tab)
        local buffer = buffers[window]
        local path = vim.fn.bufname(buffer)
        local name = vim.fn.fnamemodify(path, ":t")
        if name == "" then name = "Untitled" end
        name = name:gsub("%%", "%%%%")

        local extension = vim.fn.fnamemodify(path, ":e"):lower()
        local icon = "▣"
        local iconHighlight = "TabLine"
        if extension == "js" or extension == "jsx" then
          icon = "JS"
          iconHighlight = "GhosttyEditorIconJS"
        elseif extension == "ts" or extension == "tsx" then
          icon = "TS"
          iconHighlight = "GhosttyEditorIconTS"
        elseif extension == "sql" then
          icon = "SQL"
          iconHighlight = "GhosttyEditorIconSQL"
        end

        local modified = vim.bo[buffer].modified and " ●" or ""
        local tabHighlight = tab == current and "TabLineSel" or "TabLine"
        result = result
          .. "%#" .. tabHighlight .. "#%" .. tab .. "T "
          .. "%#" .. iconHighlight .. "#" .. icon
          .. "%#" .. tabHighlight .. "# " .. name .. modified .. " "
          .. "%T%" .. tab .. "@GhosttyEditorCloseTab@ × %X"
      end

      return result .. "%#TabLineFill#%T"
    end

    vim.o.tabline = "%!v:lua.GhosttyEditorTabLine()"
    """#
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
