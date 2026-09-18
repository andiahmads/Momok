import AppKit
import SwiftUI

/// A native preview for supported files selected in the project browser.
struct TerminalFilePreview: View {
    let url: URL
    let onClose: () -> Void

    @AppStorage("momok.filePreviewWidth") private var previewWidth = 480.0
    @State private var resizeStartWidth: Double?
    @State private var refreshID = UUID()

    private let minimumWidth = 320.0
    private let maximumWidth = 900.0

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                Divider()
                preview
            }
            .frame(width: previewWidth)
            .background(Color(nsColor: .windowBackgroundColor))

            resizeHandle
        }
    }

    @ViewBuilder private var preview: some View {
        if url.pathExtension.lowercased() == "md" {
            MarkdownDocumentView(url: url, refreshID: refreshID)
        } else {
            ImageDocumentView(url: url, refreshID: refreshID)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: url.pathExtension.lowercased() == "md" ? "doc.richtext" : "photo")
                .foregroundStyle(.secondary)

            Text(url.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button {
                refreshID = UUID()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("Refresh Preview")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close Preview")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
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
                    if resizeStartWidth == nil { resizeStartWidth = previewWidth }
                    let initialWidth = resizeStartWidth ?? previewWidth
                    previewWidth = min(maximumWidth, max(minimumWidth, initialWidth + value.translation.width))
                }
                .onEnded { _ in resizeStartWidth = nil }
        )
    }
}

private struct ImageDocumentView: View {
    let url: URL
    let refreshID: UUID

    @State private var image: NSImage?
    @State private var error: String?

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(20)
            } else if let error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                    Text("Preview Unavailable")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                ProgressView()
            }
        }
        .task(id: refreshID) { load() }
        .onChange(of: url) { _ in load() }
    }

    private func load() {
        guard let value = NSImage(contentsOf: url) else {
            image = nil
            error = "Momok could not decode this image."
            return
        }

        image = value
        error = nil
    }
}

struct MarkdownContentView: View {
    private let blocks: [MarkdownBlock]
    private let baseURL: URL

    init(source: String, baseURL: URL) {
        blocks = MarkdownParser.parse(source)
        self.baseURL = baseURL
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(blocks) { block in
                MarkdownBlockView(block: block, baseURL: baseURL)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownDocumentView: View {
    let url: URL
    let refreshID: UUID
    @State private var blocks: [MarkdownBlock] = []
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let error {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                    Text("Preview Unavailable")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(blocks) { block in
                        MarkdownBlockView(block: block, baseURL: url.deletingLastPathComponent())
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(28)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task(id: refreshID) { load() }
        .onChange(of: url) { _ in load() }
    }

    private func load() {
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            blocks = MarkdownParser.parse(source)
            error = nil
        } catch {
            blocks = []
            self.error = error.localizedDescription
        }
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case heading(Int, String), paragraph(String), bullet(String), numbered(String)
        case quote(String, String?), code(String, String?), table([String], [[String]]), divider
    }

    let id = UUID()
    let kind: Kind
}

private enum MarkdownParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var result: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var language: String?
        var inCode = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(.init(kind: .paragraph(paragraph.joined(separator: " "))))
            paragraph.removeAll()
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    result.append(.init(kind: .code(code.joined(separator: "\n"), language)))
                    code.removeAll()
                    language = nil
                } else {
                    flushParagraph()
                    let value = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    language = value.isEmpty ? nil : value
                }
                inCode.toggle()
                index += 1
                continue
            }
            if inCode {
                code.append(line)
                index += 1
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }
            if let heading = heading(from: trimmed) {
                flushParagraph()
                result.append(.init(kind: .heading(heading.level, heading.text)))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                result.append(.init(kind: .divider))
            } else if trimmed == ">" || trimmed.hasPrefix("> ") {
                flushParagraph()
                var quoteLines: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine == ">" || quoteLine.hasPrefix("> ") else { break }
                    quoteLines.append(quoteLine == ">" ? "" : String(quoteLine.dropFirst(2)))
                    index += 1
                }
                let first = quoteLines.first ?? ""
                let admonition = first.hasPrefix("[!") && first.hasSuffix("]")
                    ? String(first.dropFirst(2).dropLast()).capitalized
                    : nil
                let body = (admonition == nil ? quoteLines : Array(quoteLines.dropFirst()))
                    .split(separator: "", omittingEmptySubsequences: true)
                    .map { $0.joined(separator: " ") }
                    .joined(separator: "\n\n")
                result.append(.init(kind: .quote(body, admonition)))
                continue
            } else if isTableHeader(lines: lines, at: index) {
                flushParagraph()
                let headers = tableCells(trimmed)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|"), row.hasSuffix("|") else { break }
                    rows.append(tableCells(row))
                    index += 1
                }
                result.append(.init(kind: .table(headers, rows)))
                continue
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                flushParagraph()
                result.append(.init(kind: .bullet(String(trimmed.dropFirst(2)))))
            } else if let item = numberedItem(from: trimmed) {
                flushParagraph()
                result.append(.init(kind: .numbered(item)))
            } else {
                paragraph.append(trimmed)
            }
            index += 1
        }
        flushParagraph()
        if inCode { result.append(.init(kind: .code(code.joined(separator: "\n"), language))) }
        return result
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let count = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(count), line.dropFirst(count).first == " " else { return nil }
        return (count, String(line.dropFirst(count + 1)))
    }

    private static func numberedItem(from line: String) -> String? {
        guard let dot = line.firstIndex(of: "."), dot < line.endIndex else { return nil }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.first == " " else { return nil }
        return String(rest.dropFirst())
    }

    private static func tableCells(_ line: String) -> [String] {
        line.drop(while: { $0 == "|" }).dropLast(line.hasSuffix("|") ? 1 : 0)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableHeader(lines: [String], at index: Int) -> Bool {
        guard index + 1 < lines.count else { return false }
        let header = lines[index].trimmingCharacters(in: .whitespaces)
        let separator = tableCells(lines[index + 1].trimmingCharacters(in: .whitespaces))
        return header.hasPrefix("|") && header.hasSuffix("|") && !separator.isEmpty
            && separator.allSatisfy { cell in
                let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                return value.count >= 3 && value.allSatisfy { $0 == "-" }
            }
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let baseURL: URL

    var body: some View {
        switch block.kind {
        case let .heading(level, source):
            inline(source)
                .font(.system(size: [30, 24, 20, 17, 15, 14][level - 1], weight: .bold))
                .padding(.top, level == 1 ? 4 : 8)
        case let .paragraph(source):
            inline(source).font(.system(size: 14)).lineSpacing(4)
        case let .bullet(source):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").fontWeight(.bold)
                inline(source)
            }.padding(.leading, 8)
        case let .numbered(source):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("•").foregroundStyle(.secondary)
                inline(source)
            }.padding(.leading, 8)
        case let .quote(source, admonition):
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(Color.accentColor).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    if let admonition {
                        Label(admonition, systemImage: admonitionIcon(admonition))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    inline(source).foregroundStyle(.secondary).lineSpacing(4)
                }
            }
            .padding(.vertical, 8)
        case let .code(source, language):
            VStack(alignment: .leading, spacing: 8) {
                if let language { Text(language).font(.caption).foregroundStyle(.secondary) }
                ScrollView(.horizontal) {
                    Text(source).font(.system(size: 13, design: .monospaced)).fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        case let .table(headers, rows):
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow { tableRow(headers, header: true) }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow { tableRow(row, header: false) }
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(nsColor: .separatorColor)))
            }
        case .divider:
            Divider().padding(.vertical, 6)
        }
    }

    private func inline(_ source: String) -> Text {
        let value = (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace),
            baseURL: baseURL)) ?? AttributedString(source)
        return Text(value)
    }

    @ViewBuilder private func tableRow(_ cells: [String], header: Bool) -> some View {
        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
            inline(cell)
                .font(.system(size: 13, weight: header ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(minWidth: 120, alignment: .leading)
                .background(header ? Color(nsColor: .controlBackgroundColor) : Color.clear)
        }
    }

    private func admonitionIcon(_ title: String) -> String {
        switch title.lowercased() {
        case "warning", "caution": return "exclamationmark.triangle.fill"
        case "important": return "exclamationmark.circle.fill"
        case "tip": return "lightbulb.fill"
        default: return "info.circle.fill"
        }
    }
}
