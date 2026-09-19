import AppKit
import SwiftUI

enum TerminalCodeLanguage: String, CaseIterable {
    case c = "C"
    case cpp = "C++"
    case javascript = "JavaScript"
    case typescript = "TypeScript"
    case jsx = "JavaScript React"
    case tsx = "TypeScript React"
    case html = "HTML"
    case svelte = "Svelte"
    case vue = "Vue / Nuxt"
    case go = "Go"
    case rust = "Rust"
    case json = "JSON"
    case yaml = "YAML"
    case php = "PHP"
    case python = "Python"
    case sql = "SQL"

    static func language(for url: URL) -> Self? {
        switch url.pathExtension.lowercased() {
        case "c", "h": return .c
        case "cc", "cpp", "cxx", "hh", "hpp", "hxx": return .cpp
        case "js", "mjs", "cjs": return .javascript
        case "ts", "mts", "cts": return .typescript
        case "jsx": return .jsx
        case "tsx": return .tsx
        case "html", "htm": return .html
        case "svelte": return .svelte
        case "vue": return .vue
        case "go": return .go
        case "rs": return .rust
        case "json", "jsonc": return .json
        case "yaml", "yml": return .yaml
        case "php", "phtml": return .php
        case "py", "pyw": return .python
        case "sql": return .sql
        default: return nil
        }
    }

    static func supports(_ url: URL) -> Bool { language(for: url) != nil }
}

enum TerminalVimMode: String {
    case normal = "NORMAL"
    case insert = "INSERT"
    case visual = "VISUAL"
    case command = "COMMAND"

    var color: Color {
        switch self {
        case .normal: return .blue
        case .insert: return .green
        case .visual: return .purple
        case .command: return .orange
        }
    }
}

@MainActor
final class TerminalCodeEditorModel: ObservableObject {
    struct Buffer: Identifiable {
        let id: UUID
        let url: URL
        let language: TerminalCodeLanguage
        var text: String
        var savedText: String
        var mode: TerminalVimMode
        var commandLine: String
        var cursorLine: Int
        var cursorColumn: Int
        var errorMessage: String?

        var isDirty: Bool { text != savedText }
    }

    @Published private(set) var buffers: [Buffer] = []
    @Published private(set) var selectedBufferID: UUID?
    @Published private(set) var url: URL?
    @Published private(set) var language: TerminalCodeLanguage?
    @Published private(set) var text = ""
    @Published private(set) var isDirty = false
    @Published private(set) var mode = TerminalVimMode.normal
    @Published private(set) var commandLine = ""
    @Published private(set) var cursorLine = 1
    @Published private(set) var cursorColumn = 1
    @Published private(set) var errorMessage: String?

    private var savedText = ""

    var isOpen: Bool { !buffers.isEmpty }

    @discardableResult
    func open(_ newURL: URL) -> Bool {
        persistSelectedBuffer()

        let normalizedURL = newURL.standardizedFileURL
        if let existing = buffers.first(where: { $0.url.standardizedFileURL == normalizedURL }) {
            selectBuffer(existing.id)
            return true
        }

        do {
            let source = try String(contentsOf: newURL, encoding: .utf8)
            guard let language = TerminalCodeLanguage.language(for: newURL) else { return false }
            let buffer = Buffer(
                id: UUID(),
                url: normalizedURL,
                language: language,
                text: source,
                savedText: source,
                mode: .normal,
                commandLine: "",
                cursorLine: 1,
                cursorColumn: 1,
                errorMessage: nil
            )
            buffers.append(buffer)
            apply(buffer)
            return true
        } catch {
            showError("Could Not Open File", detail: error.localizedDescription)
            return false
        }
    }

    func updateText(_ value: String) {
        text = value
        isDirty = value != savedText
        persistSelectedBuffer()
    }

    func updateMode(_ value: TerminalVimMode, commandLine: String) {
        mode = value
        self.commandLine = commandLine
        persistSelectedBuffer()
    }

    func updateCursor(line: Int, column: Int) {
        cursorLine = line
        cursorColumn = column
        persistSelectedBuffer()
    }

    @discardableResult
    func save() -> Bool {
        guard let url else { return false }

        do {
            guard let data = text.data(using: .utf8) else {
                throw CocoaError(.fileWriteInapplicableStringEncoding)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            savedText = text
            isDirty = false
            errorMessage = nil
            persistSelectedBuffer()
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError("Could Not Save File", detail: error.localizedDescription)
            return false
        }
    }

    func reload() {
        guard let url else { return }
        guard !isDirty || confirm(
            title: "Discard Unsaved Changes?",
            message: "Reloading will replace your unsaved edits.",
            confirmTitle: "Reload"
        ) else { return }

        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            text = source
            savedText = source
            isDirty = false
            mode = .normal
            commandLine = ""
            errorMessage = nil
            persistSelectedBuffer()
        } catch {
            showError("Could Not Reload File", detail: error.localizedDescription)
        }
    }

    func selectBuffer(_ id: UUID) {
        guard id != selectedBufferID,
              let buffer = buffers.first(where: { $0.id == id }) else { return }
        persistSelectedBuffer()
        apply(buffer)
    }

    @discardableResult
    func closeBuffer(_ id: UUID, force: Bool = false) -> Bool {
        persistSelectedBuffer()
        guard let index = buffers.firstIndex(where: { $0.id == id }) else { return true }
        let previouslySelectedID = selectedBufferID

        if buffers[index].isDirty, !force {
            selectBuffer(id)
            guard confirmDiscardIfNeeded() else { return false }
        }

        buffers.remove(at: index)
        if buffers.isEmpty {
            resetCurrentState()
        } else if let previouslySelectedID,
                  previouslySelectedID != id,
                  let previous = buffers.first(where: { $0.id == previouslySelectedID }) {
            apply(previous)
        } else {
            apply(buffers[min(index, buffers.count - 1)])
        }
        return true
    }

    func requestClose() -> Bool {
        persistSelectedBuffer()
        let dirtyBufferIDs = buffers.filter(\.isDirty).map(\.id)
        for id in dirtyBufferIDs {
            selectBuffer(id)
            guard confirmDiscardIfNeeded() else { return false }
        }
        closeWithoutSaving()
        return true
    }

    func closeWithoutSaving() {
        buffers.removeAll()
        resetCurrentState()
    }

    private func resetCurrentState() {
        selectedBufferID = nil
        url = nil
        language = nil
        text = ""
        savedText = ""
        isDirty = false
        mode = .normal
        commandLine = ""
        cursorLine = 1
        cursorColumn = 1
        errorMessage = nil
    }

    private func apply(_ buffer: Buffer) {
        selectedBufferID = buffer.id
        url = buffer.url
        language = buffer.language
        text = buffer.text
        savedText = buffer.savedText
        isDirty = buffer.isDirty
        mode = buffer.mode
        commandLine = buffer.commandLine
        cursorLine = buffer.cursorLine
        cursorColumn = buffer.cursorColumn
        errorMessage = buffer.errorMessage
    }

    private func persistSelectedBuffer() {
        guard let selectedBufferID,
              let index = buffers.firstIndex(where: { $0.id == selectedBufferID }) else { return }
        buffers[index].text = text
        buffers[index].savedText = savedText
        buffers[index].mode = mode
        buffers[index].commandLine = commandLine
        buffers[index].cursorLine = cursorLine
        buffers[index].cursorColumn = cursorColumn
        buffers[index].errorMessage = errorMessage
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }

        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard")

        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }

    private func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .critical
        alert.runModal()
    }
}

struct TerminalCodeEditor: View {
    @ObservedObject var model: TerminalCodeEditorModel
    let onClose: () -> Void

    @AppStorage("momok.codeEditorWidth") private var editorWidth = 720.0
    @State private var resizeStartWidth: Double?

    private let minimumWidth = 420.0
    private let maximumWidth = 1_400.0

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                tabsHeader
                Divider()
                editor
                Divider()
                statusBar
            }
            .frame(width: editorWidth)
            .background(Color(nsColor: .textBackgroundColor))

            resizeHandle
        }
        .frame(width: editorWidth + 7)
        .clipped()
    }

    private var tabsHeader: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(model.buffers) { buffer in
                        bufferTab(buffer)
                    }
                }
                .padding(.horizontal, 6)
            }

            Divider()
                .frame(height: 22)

            HStack(spacing: 12) {
                Button {
                    model.save()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(!model.isDirty)
                .help("Save (⌘S or :w)")

                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload from Disk")

                Button {
                    if model.requestClose() {
                        onClose()
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .help("Close Editor")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        }
        .frame(height: 38)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func bufferTab(_ buffer: TerminalCodeEditorModel.Buffer) -> some View {
        let isSelected = buffer.id == model.selectedBufferID
        return HStack(spacing: 7) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            Text(buffer.url.lastPathComponent)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)

            if buffer.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                    .help("Unsaved changes")
            }

            Button {
                if model.closeBuffer(buffer.id), !model.isOpen {
                    onClose()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close \(buffer.url.lastPathComponent)")
        }
        .padding(.leading, 9)
        .padding(.trailing, 5)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.09) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            model.selectBuffer(buffer.id)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .foregroundStyle(.secondary)

            Text(model.url?.lastPathComponent ?? "Editor")
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            if model.isDirty {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
            }

            Spacer(minLength: 8)

            Button {
                model.save()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .buttonStyle(.plain)
            .disabled(!model.isDirty)
            .help("Save (⌘S or :w)")

            Button {
                model.reload()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Reload from Disk")

            Button {
                if model.requestClose() { onClose() }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close Editor (:q)")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    @ViewBuilder
    private var editor: some View {
        if let language = model.language {
            TerminalCodeTextView(
                text: model.text,
                language: language,
                onTextChange: model.updateText,
                onModeChange: model.updateMode,
                onCursorChange: model.updateCursor,
                onCommand: handleCommand
            )
            .id(model.selectedBufferID)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.badge.ellipsis")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Unsupported File")
                    .font(.headline)
                Text("This file type is not supported by the native editor.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 0) {
            Text(model.mode.rawValue)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(model.mode.color)

            if model.mode == .command {
                Text(model.commandLine)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
            } else {
                Text(model.language?.rawValue ?? "Plain Text")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            }

            Spacer()

            if let errorMessage = model.errorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(errorMessage)
                    .padding(.trailing, 8)
            }

            Text("\(model.cursorLine):\(model.cursorColumn)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
        }
        .frame(height: 24)
        .background(Color(nsColor: .controlBackgroundColor))
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
                    if resizeStartWidth == nil { resizeStartWidth = editorWidth }
                    let initialWidth = resizeStartWidth ?? editorWidth
                    editorWidth = min(
                        maximumWidth,
                        max(minimumWidth, initialWidth + value.translation.width)
                    )
                }
                .onEnded { _ in resizeStartWidth = nil }
        )
    }

    private func handleCommand(_ command: TerminalCodeTextView.Command) {
        switch command {
        case .write:
            model.save()
        case .quit:
            closeSelectedBuffer()
        case .writeQuit:
            if model.save() {
                closeSelectedBuffer()
            }
        case .forceQuit:
            guard let id = model.selectedBufferID else { return }
            model.closeBuffer(id, force: true)
            if !model.isOpen { onClose() }
        }
    }

    private func closeSelectedBuffer() {
        guard let id = model.selectedBufferID else { return }
        if model.closeBuffer(id), !model.isOpen {
            onClose()
        }
    }
}

private struct TerminalCodeTextView: NSViewRepresentable {
    enum Command {
        case write
        case quit
        case writeQuit
        case forceQuit
    }

    let text: String
    let language: TerminalCodeLanguage
    let onTextChange: (String) -> Void
    let onModeChange: (TerminalVimMode, String) -> Void
    let onCursorChange: (Int, Int) -> Void
    let onCommand: (Command) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = VimTextView()
        textView.delegate = context.coordinator
        textView.vimDelegate = context.coordinator
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.verticalRulerView = CodeLineNumberRulerView(
            textView: textView,
            scrollView: scrollView
        )

        context.coordinator.textView = textView
        context.coordinator.language = language
        context.coordinator.highlight()
        context.coordinator.reportCursor()

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.language = language
        guard let textView = scrollView.documentView as? VimTextView else { return }

        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            textView.setSelectedRange(NSRange(
                location: min(selection.location, text.utf16.count),
                length: 0
            ))
            context.coordinator.highlight()
            context.coordinator.reportCursor()
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, VimTextViewDelegate {
        var parent: TerminalCodeTextView
        weak var textView: VimTextView?
        var language: TerminalCodeLanguage

        init(parent: TerminalCodeTextView) {
            self.parent = parent
            language = parent.language
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.onTextChange(textView.string)
            highlight()
            reportCursor()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            reportCursor()
        }

        func vimTextView(
            _ textView: VimTextView,
            changedMode mode: TerminalVimMode,
            commandLine: String
        ) {
            parent.onModeChange(mode, commandLine)
            reportCursor()
        }

        func vimTextView(_ textView: VimTextView, perform command: Command) {
            parent.onCommand(command)
        }

        func reportCursor() {
            guard let textView else { return }
            let location = min(textView.selectedRange().location, textView.string.utf16.count)
            let nsText = textView.string as NSString
            let prefix = nsText.substring(to: location)
            let line = prefix.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let lineStart = (prefix as NSString).range(of: "\n", options: .backwards).location
            let column = lineStart == NSNotFound ? location + 1 : location - lineStart
            parent.onCursorChange(line, column)
        }

        func highlight() {
            guard let textView,
                  let layoutManager = textView.layoutManager else { return }
            CodeSyntaxHighlighter.highlight(
                textView.string,
                language: language,
                layoutManager: layoutManager
            )
            (textView.enclosingScrollView?.verticalRulerView as? CodeLineNumberRulerView)?
                .needsDisplay = true
        }
    }
}

private protocol VimTextViewDelegate: AnyObject {
    func vimTextView(
        _ textView: VimTextView,
        changedMode mode: TerminalVimMode,
        commandLine: String
    )
    func vimTextView(
        _ textView: VimTextView,
        perform command: TerminalCodeTextView.Command
    )
}

private final class VimTextView: NSTextView {
    weak var vimDelegate: VimTextViewDelegate?

    private(set) var mode = TerminalVimMode.normal
    private var pendingKey: Character?
    private var commandLine = ""
    private var yankBuffer = ""

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.characters ?? ""

        if modifiers == .command, characters.lowercased() == "s" {
            vimDelegate?.vimTextView(self, perform: .write)
            return
        }

        if event.keyCode == 53 {
            setMode(.normal)
            setSelectedRange(NSRange(location: selectedRange().location, length: 0))
            return
        }

        switch mode {
        case .insert:
            super.keyDown(with: event)
        case .normal:
            handleNormal(event, characters: characters, modifiers: modifiers)
        case .visual:
            handleVisual(event, characters: characters)
        case .command:
            handleCommand(event, characters: characters)
        }
    }

    private func handleNormal(
        _ event: NSEvent,
        characters: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        if modifiers == .control, characters.lowercased() == "r" {
            undoManager?.redo()
            return
        }

        guard let character = characters.first else { return }

        if pendingKey == "g" {
            pendingKey = nil
            if character == "g" { moveToBeginningOfDocument(nil) }
            return
        }
        if pendingKey == "d" {
            pendingKey = nil
            if character == "d" { deleteCurrentLine() }
            return
        }
        if pendingKey == "y" {
            pendingKey = nil
            if character == "y" { yankCurrentLine() }
            return
        }

        switch character {
        case "h": moveLeft(nil)
        case "j": moveDown(nil)
        case "k": moveUp(nil)
        case "l": moveRight(nil)
        case "w": moveWordForward(nil)
        case "b": moveWordBackward(nil)
        case "e": moveWordForward(nil)
        case "0": moveToBeginningOfLine(nil)
        case "$": moveToEndOfLine(nil)
        case "g": pendingKey = "g"
        case "G": moveToEndOfDocument(nil)
        case "i": setMode(.insert)
        case "a":
            moveRight(nil)
            setMode(.insert)
        case "A":
            moveToEndOfLine(nil)
            setMode(.insert)
        case "I":
            moveToBeginningOfLine(nil)
            setMode(.insert)
        case "o": openLineBelow()
        case "O": openLineAbove()
        case "x": deleteForward(nil)
        case "d": pendingKey = "d"
        case "y": pendingKey = "y"
        case "p": pasteYankedLine()
        case "u": undoManager?.undo()
        case "v": setMode(.visual)
        case ":":
            commandLine = ":"
            setMode(.command)
        default: break
        }
    }

    private func handleVisual(_ event: NSEvent, characters: String) {
        guard let character = characters.first else { return }
        switch character {
        case "h": moveLeftAndModifySelection(nil)
        case "j": moveDownAndModifySelection(nil)
        case "k": moveUpAndModifySelection(nil)
        case "l": moveRightAndModifySelection(nil)
        case "w": moveWordForwardAndModifySelection(nil)
        case "b": moveWordBackwardAndModifySelection(nil)
        case "0": moveToBeginningOfLineAndModifySelection(nil)
        case "$": moveToEndOfLineAndModifySelection(nil)
        case "y":
            yankBuffer = selectedText()
            setSelectedRange(NSRange(location: selectedRange().location, length: 0))
            setMode(.normal)
        case "d":
            yankBuffer = selectedText()
            delete(nil)
            setMode(.normal)
        case "c":
            yankBuffer = selectedText()
            delete(nil)
            setMode(.insert)
        default: break
        }
    }

    private func handleCommand(_ event: NSEvent, characters: String) {
        if event.keyCode == 36 || event.keyCode == 76 {
            executeCommand()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if commandLine.count > 1 {
                commandLine.removeLast()
                notifyModeChange()
            } else {
                setMode(.normal)
            }
            return
        }

        guard !characters.isEmpty,
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.control) else { return }
        commandLine.append(contentsOf: characters)
        notifyModeChange()
    }

    private func executeCommand() {
        let command = commandLine.dropFirst().trimmingCharacters(in: .whitespaces)
        switch command {
        case "w": vimDelegate?.vimTextView(self, perform: .write)
        case "q": vimDelegate?.vimTextView(self, perform: .quit)
        case "wq", "x": vimDelegate?.vimTextView(self, perform: .writeQuit)
        case "q!": vimDelegate?.vimTextView(self, perform: .forceQuit)
        default: NSSound.beep()
        }
        commandLine = ""
        setMode(.normal)
    }

    private func setMode(_ newMode: TerminalVimMode) {
        mode = newMode
        pendingKey = nil
        if newMode != .command { commandLine = "" }
        notifyModeChange()
    }

    private func notifyModeChange() {
        vimDelegate?.vimTextView(self, changedMode: mode, commandLine: commandLine)
    }

    private func currentLineRange(includeNewline: Bool = true) -> NSRange {
        let nsText = string as NSString
        guard nsText.length > 0 else { return NSRange(location: 0, length: 0) }
        let location = min(selectedRange().location, max(0, nsText.length - 1))
        var range = nsText.lineRange(for: NSRange(location: location, length: 0))
        if !includeNewline,
           range.length > 0,
           NSMaxRange(range) <= nsText.length,
           nsText.substring(with: NSRange(location: NSMaxRange(range) - 1, length: 1)) == "\n" {
            range.length -= 1
        }
        return range
    }

    private func selectedText() -> String {
        let range = selectedRange()
        guard range.length > 0 else { return "" }
        return (string as NSString).substring(with: range)
    }

    private func yankCurrentLine() {
        let range = currentLineRange()
        yankBuffer = (string as NSString).substring(with: range)
        setSelectedRange(NSRange(location: range.location, length: 0))
    }

    private func deleteCurrentLine() {
        let range = currentLineRange()
        yankBuffer = (string as NSString).substring(with: range)
        setSelectedRange(range)
        delete(nil)
    }

    private func pasteYankedLine() {
        guard !yankBuffer.isEmpty else { return }
        let range = currentLineRange()
        let location = NSMaxRange(range)
        setSelectedRange(NSRange(location: location, length: 0))
        insertText(yankBuffer, replacementRange: selectedRange())
    }

    private func openLineBelow() {
        moveToEndOfLine(nil)
        insertText("\n", replacementRange: selectedRange())
        setMode(.insert)
    }

    private func openLineAbove() {
        moveToBeginningOfLine(nil)
        insertText("\n", replacementRange: selectedRange())
        moveUp(nil)
        setMode(.insert)
    }
}

private final class CodeLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 46
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(redraw),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(redraw),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func redraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let visibleRect = textView.enclosingScrollView?.contentView.bounds ?? textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(
            forGlyphRange: glyphRange,
            actualGlyphRange: nil
        )
        let nsText = textView.string as NSString
        var lineNumber = 1
        if characterRange.location > 0 {
            lineNumber += nsText.substring(to: characterRange.location)
                .reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        guard nsText.length > 0 else { return }

        var index = characterRange.location
        let limit = min(nsText.length, NSMaxRange(characterRange) + 1)

        while index <= limit {
            let lineRange = nsText.lineRange(for: NSRange(location: index, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(
                at: min(index, nsText.length - 1)
            )
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let point = convert(
                NSPoint(x: 0, y: lineRect.minY + textView.textContainerInset.height),
                from: textView
            )
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - 8, y: point.y),
                withAttributes: attributes
            )

            lineNumber += 1
            let next = NSMaxRange(lineRange)
            if next <= index || next >= nsText.length { break }
            index = next
        }
    }
}

private enum CodeSyntaxHighlighter {
    private struct Rule {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options

        init(
            _ pattern: String,
            color: NSColor,
            options: NSRegularExpression.Options = []
        ) {
            self.pattern = pattern
            self.color = color
            self.options = options
        }
    }

    static func highlight(
        _ source: String,
        language: TerminalCodeLanguage,
        layoutManager: NSLayoutManager
    ) {
        let range = NSRange(location: 0, length: (source as NSString).length)
        guard range.length > 0 else { return }
        guard let textStorage = layoutManager.textStorage else { return }

        textStorage.beginEditing()
        defer { textStorage.endEditing() }
        textStorage.setAttributes(
            [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ],
            range: range
        )

        for rule in rules(for: language) {
            guard let expression = try? NSRegularExpression(
                pattern: rule.pattern,
                options: rule.options
            ) else { continue }
            expression.enumerateMatches(in: source, range: range) { match, _, _ in
                guard let match else { return }
                textStorage.addAttribute(
                    .foregroundColor,
                    value: rule.color,
                    range: match.range
                )
            }
        }
    }

    private static func rules(for language: TerminalCodeLanguage) -> [Rule] {
        var result: [Rule] = [
            Rule(#"\b(?:true|false|null|nil|None)\b"#, color: .systemOrange),
            Rule(#"\b(?:0x[\dA-Fa-f]+|\d+(?:\.\d+)?)\b"#, color: .systemOrange),
        ]

        let keywords = keywords(for: language)
        if !keywords.isEmpty {
            result.append(Rule(
                #"\b(?:"# + keywords.joined(separator: "|") + #")\b"#,
                color: .systemPink,
                options: language == .sql ? [.caseInsensitive] : []
            ))
        }

        let types = types(for: language)
        if !types.isEmpty {
            result.append(Rule(
                #"\b(?:"# + types.joined(separator: "|") + #")\b"#,
                color: .systemBlue,
                options: language == .sql ? [.caseInsensitive] : []
            ))
        }

        if language == .c || language == .cpp {
            result.append(Rule(
                #"^\s*#\s*\w+.*$"#,
                color: .systemPurple,
                options: [.anchorsMatchLines]
            ))
        }
        if language == .php {
            result.append(Rule(#"<\?(?:php)?|\?>"#, color: .systemPurple))
        }

        let hasMarkup = [.html, .svelte, .vue, .jsx, .tsx].contains(language)
        if hasMarkup {
            result.append(Rule(#"</?[A-Za-z][\w:.-]*\b|/?>"#, color: .systemPink))
            result.append(Rule(#"[\w@:#][\w@:.-]*(?=\s*=)"#, color: .systemBlue))
            result.append(Rule(#"<!DOCTYPE\b[^>]*>"#, color: .systemPurple, options: [.caseInsensitive]))
        }
        if language == .svelte {
            result.append(Rule(#"\{[#:/@](?:if|else|each|await|then|catch|key|snippet|render|html|debug|const)\b"#, color: .systemPurple))
        }
        if [.javascript, .typescript, .jsx, .tsx, .vue, .svelte].contains(language) {
            result.append(Rule(#"`(?:\\.|[^`\\])*`"#, color: .systemGreen))
        }
        result.append(Rule(#"\"(?:\\.|[^\"\\])*\""#, color: .systemGreen))
        if language != .json {
            result.append(Rule(#"'(?:\\.|[^'\\])*'"#, color: .systemGreen))
        }

        switch language {
        case .python:
            result.append(Rule(#"(?m)#.*$"#, color: .secondaryLabelColor))
            result.append(Rule(
                #"\"\"\"[\s\S]*?\"\"\"|'''[\s\S]*?'''"#,
                color: .secondaryLabelColor
            ))
        case .yaml:
            result.append(Rule(#"(?m)#.*$"#, color: .secondaryLabelColor))
            result.append(Rule(#"(?m)^\s*[\w.-]+(?=\s*:)"#, color: .systemBlue))
        case .json:
            result.append(Rule(#"\"(?:\\.|[^\"\\])*\"(?=\s*:)"#, color: .systemBlue))
        case .sql:
            result.append(Rule(#"--.*$"#, color: .secondaryLabelColor, options: [.anchorsMatchLines]))
            result.append(Rule(#"/\*[\s\S]*?\*/"#, color: .secondaryLabelColor))
        case .html:
            break
        default:
            result.append(Rule(#"//.*$"#, color: .secondaryLabelColor, options: [.anchorsMatchLines]))
            result.append(Rule(#"/\*[\s\S]*?\*/"#, color: .secondaryLabelColor))
        }
        if hasMarkup {
            result.append(Rule(#"<!--[\s\S]*?-->"#, color: .secondaryLabelColor))
        }
        return result
    }

    private static func keywords(for language: TerminalCodeLanguage) -> [String] {
        switch language {
        case .c:
            return ["auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for", "goto", "if", "register", "return", "sizeof", "static", "struct", "switch", "typedef", "union", "volatile", "while"]
        case .cpp:
            return ["alignas", "break", "case", "catch", "class", "concept", "const", "constexpr", "continue", "default", "delete", "do", "else", "enum", "explicit", "export", "for", "friend", "if", "namespace", "new", "noexcept", "operator", "private", "protected", "public", "requires", "return", "static", "struct", "switch", "template", "this", "throw", "try", "using", "virtual", "while"]
        case .javascript, .typescript, .jsx, .tsx, .vue, .svelte:
            return ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "finally", "for", "from", "function", "if", "import", "in", "instanceof", "let", "new", "of", "return", "static", "super", "switch", "throw", "try", "typeof", "var", "void", "while", "with", "yield"]
        case .go:
            return ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"]
        case .rust:
            return ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"]
        case .php:
            return ["abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "endfor", "endif", "endswitch", "endwhile", "extends", "final", "finally", "fn", "for", "foreach", "function", "global", "if", "implements", "include", "instanceof", "interface", "match", "namespace", "new", "private", "protected", "public", "require", "return", "static", "switch", "throw", "trait", "try", "use", "while", "yield"]
        case .python:
            return ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"]
        case .sql:
            return ["add", "all", "alter", "and", "as", "asc", "begin", "between", "by", "case", "check", "column", "commit", "constraint", "create", "database", "default", "delete", "desc", "distinct", "drop", "else", "end", "except", "exists", "foreign", "from", "full", "group", "having", "if", "in", "index", "inner", "insert", "intersect", "into", "is", "join", "key", "left", "like", "limit", "not", "null", "offset", "on", "or", "order", "outer", "primary", "references", "returning", "right", "rollback", "select", "set", "table", "then", "transaction", "trigger", "truncate", "union", "unique", "update", "using", "values", "view", "when", "where", "with"]
        case .json, .yaml, .html:
            return []
        }
    }

    private static func types(for language: TerminalCodeLanguage) -> [String] {
        switch language {
        case .c, .cpp:
            return ["bool", "char", "double", "float", "int", "long", "short", "signed", "size_t", "unsigned", "void", "wchar_t"]
        case .javascript, .jsx:
            return ["Array", "BigInt", "Boolean", "Date", "Error", "Map", "Number", "Object", "Promise", "RegExp", "Set", "String", "Symbol"]
        case .typescript, .tsx, .vue, .svelte:
            return ["any", "bigint", "boolean", "interface", "never", "number", "object", "string", "symbol", "type", "undefined", "unknown"]
        case .go:
            return ["bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8", "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64", "uintptr"]
        case .rust:
            return ["bool", "char", "f32", "f64", "i8", "i16", "i32", "i64", "i128", "isize", "str", "u8", "u16", "u32", "u64", "u128", "usize"]
        case .php:
            return ["bool", "float", "int", "iterable", "mixed", "object", "string", "void"]
        case .python:
            return ["bool", "bytes", "dict", "float", "int", "list", "set", "str", "tuple"]
        case .sql:
            return ["bigint", "binary", "bit", "blob", "boolean", "char", "date", "datetime", "decimal", "double", "enum", "float", "int", "integer", "interval", "json", "jsonb", "numeric", "real", "serial", "smallint", "text", "time", "timestamp", "tinyint", "uuid", "varchar"]
        case .json, .yaml, .html:
            return []
        }
    }
}
