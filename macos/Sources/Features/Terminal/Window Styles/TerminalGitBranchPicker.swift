import Foundation
import SwiftUI

struct TerminalGitBranchPicker: View {
    @ObservedObject var model: TerminalGitBranchModel
    let onCheckout: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredBranches: [TerminalGitBranchModel.Branch] {
        guard !searchText.isEmpty else { return model.branches }
        return model.branches.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            Divider()
            content
        }
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Branches")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                Task { await model.fetchAll() }
            } label: {
                if model.isFetching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Fetch All", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .disabled(!model.isRepository || model.isBusy)
            .help("Run git fetch --all")
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search refs...", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView("Loading branches...")
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 120)
        } else if !model.isRepository {
            branchMessage(
                icon: "arrow.triangle.branch",
                title: "Branches Unavailable",
                message: "Open a folder inside a Git repository."
            )
        } else {
            VStack(spacing: 0) {
                if let errorMessage = model.errorMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    Divider()
                }

                if filteredBranches.isEmpty {
                    branchMessage(
                        icon: "magnifyingglass",
                        title: "No Branches Found",
                        message: "Try a different search."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredBranches) { branch in
                                branchRow(branch)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 330)
                }
            }
        }
    }

    private func branchRow(_ branch: TerminalGitBranchModel.Branch) -> some View {
        let isCurrent = branch.kind == .local && branch.name == model.currentBranch

        return Button {
            guard !isCurrent else { return }
            Task {
                if await model.checkout(branch) {
                    onCheckout()
                    dismiss()
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                    .frame(width: 14)

                Text(branch.name)
                    .font(.system(size: 12))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if branch.kind == .remote {
                    Text("remote")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                if isCurrent {
                    Text("current")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                } else if model.checkingOutBranchID == branch.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isCurrent ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy || isCurrent)
    }

    private func branchMessage(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding(16)
    }
}

@MainActor
final class TerminalGitBranchModel: ObservableObject {
    struct Branch: Identifiable, Hashable, Sendable {
        enum Kind: Hashable, Sendable {
            case local
            case remote
        }

        let id: String
        let name: String
        let kind: Kind

        var localName: String {
            guard kind == .remote, let slash = name.firstIndex(of: "/") else { return name }
            return String(name[name.index(after: slash)...])
        }
    }

    @Published private(set) var branches: [Branch] = []
    @Published private(set) var currentBranch = ""
    @Published private(set) var isRepository = false
    @Published private(set) var isLoading = false
    @Published private(set) var isFetching = false
    @Published private(set) var checkingOutBranchID: String?
    @Published private(set) var errorMessage: String?

    var isBusy: Bool { isFetching || checkingOutBranchID != nil }

    private var sourceRoot: URL?
    private var repositoryRoot: URL?
    private var revision = 0

    func setRoot(_ rootURL: URL?) {
        let normalizedRoot = rootURL?.standardizedFileURL
        guard normalizedRoot != sourceRoot else { return }

        sourceRoot = normalizedRoot
        repositoryRoot = nil
        branches = []
        currentBranch = ""
        isRepository = false
        isFetching = false
        checkingOutBranchID = nil
        errorMessage = nil
        revision += 1

        guard let normalizedRoot else {
            isLoading = false
            return
        }

        isLoading = true
        let requestRevision = revision

        Task { [weak self] in
            let result = await Self.loadSnapshot(from: normalizedRoot)
            guard let self, requestRevision == revision else { return }
            isLoading = false
            apply(result)
        }
    }

    func fetchAll() async {
        guard let repositoryRoot, !isBusy else { return }

        isFetching = true
        errorMessage = nil
        let requestRevision = revision
        let result = await Self.fetchAndReload(from: repositoryRoot)
        guard requestRevision == revision else { return }
        isFetching = false
        switch result {
        case .success:
            apply(result)
        case .failure(let message):
            errorMessage = message
        }
    }

    func checkout(_ branch: Branch) async -> Bool {
        guard let repositoryRoot, !isBusy else { return false }

        checkingOutBranchID = branch.id
        errorMessage = nil
        let requestRevision = revision
        let localBranches = Set(
            branches.lazy.filter { $0.kind == .local }.map(\.name)
        )
        let result = await Self.checkoutAndReload(
            branch,
            localBranches: localBranches,
            from: repositoryRoot
        )
        guard requestRevision == revision else { return false }
        checkingOutBranchID = nil

        switch result {
        case .success(let snapshot):
            apply(.success(snapshot))
            return true
        case .failure(let message):
            errorMessage = message
            return false
        }
    }

    private func apply(_ result: SnapshotResult) {
        switch result {
        case .success(let snapshot):
            repositoryRoot = snapshot.repositoryRoot
            branches = snapshot.branches
            currentBranch = snapshot.currentBranch
            isRepository = true
            errorMessage = nil
        case .failure(let message):
            repositoryRoot = nil
            branches = []
            currentBranch = ""
            isRepository = false
            errorMessage = message
        }
    }

    private struct Snapshot: Sendable {
        let repositoryRoot: URL
        let branches: [Branch]
        let currentBranch: String
    }

    private enum SnapshotResult: Sendable {
        case success(Snapshot)
        case failure(String)
    }

    private nonisolated static func loadSnapshot(from rootURL: URL) async -> SnapshotResult {
        await Task.detached(priority: .userInitiated) {
            do {
                return .success(try snapshot(from: rootURL))
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    private nonisolated static func fetchAndReload(from repositoryRoot: URL) async -> SnapshotResult {
        await Task.detached(priority: .userInitiated) {
            do {
                _ = try runGit(["fetch", "--all"], from: repositoryRoot)
                return .success(try snapshot(from: repositoryRoot))
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    private nonisolated static func checkoutAndReload(
        _ branch: Branch,
        localBranches: Set<String>,
        from repositoryRoot: URL
    ) async -> SnapshotResult {
        await Task.detached(priority: .userInitiated) {
            do {
                let arguments: [String]
                if branch.kind == .local || localBranches.contains(branch.localName) {
                    arguments = ["switch", branch.kind == .local ? branch.name : branch.localName]
                } else {
                    arguments = ["switch", "--track", branch.name]
                }

                _ = try runGit(arguments, from: repositoryRoot)
                return .success(try snapshot(from: repositoryRoot))
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    private nonisolated static func snapshot(from rootURL: URL) throws -> Snapshot {
        let repositoryPath = try runGit(
            ["rev-parse", "--show-toplevel"],
            from: rootURL
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repositoryPath.isEmpty else { throw GitBranchError.notRepository }

        let repositoryRoot = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        let currentBranch = (try? runGit(
            ["symbolic-ref", "--quiet", "--short", "HEAD"],
            from: repositoryRoot
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refs = try runGit(
            [
                "for-each-ref",
                "--format=%(refname)%09%(refname:short)%09%(symref)",
                "refs/heads",
                "refs/remotes",
            ],
            from: repositoryRoot
        )

        let branches = refs.split(separator: "\n").compactMap { line -> Branch? in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 3 else { return nil }

            let fullName = String(fields[0])
            let shortName = String(fields[1])
            let symbolicTarget = String(fields[2])
            guard symbolicTarget.isEmpty, !shortName.hasSuffix("/HEAD") else { return nil }

            let kind: Branch.Kind = fullName.hasPrefix("refs/heads/") ? .local : .remote
            return Branch(id: fullName, name: shortName, kind: kind)
        }.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .local }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return Snapshot(
            repositoryRoot: repositoryRoot,
            branches: branches,
            currentBranch: currentBranch
        )
    }

    private nonisolated static func runGit(
        _ arguments: [String],
        from directory: URL
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = output

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitBranchError.commandFailed(
                message.isEmpty ? "The Git command failed." : message
            )
        }
        return text
    }
}

private enum GitBranchError: LocalizedError {
    case notRepository
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notRepository:
            return "The selected folder is not inside a Git repository."
        case .commandFailed(let message):
            return message
        }
    }
}
