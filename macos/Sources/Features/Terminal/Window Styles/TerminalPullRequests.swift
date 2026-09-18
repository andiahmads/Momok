import AppKit
import SwiftUI
import UserNotifications

/// A GitHub pull request dashboard backed by the authenticated `gh` CLI session.
struct TerminalPullRequestsView: View {
    let rootURL: URL?
    let onClose: () -> Void
    let onOpenThread: (String) -> Void

    @StateObject private var model = PullRequestWorkspaceModel()

    var body: some View {
        VStack(spacing: 0) {
            if let selection = model.selection {
                PullRequestDetailView(
                    summary: selection,
                    detail: model.detail,
                    diffs: model.diffs,
                    isLoading: model.isLoadingDetail,
                    error: model.detailError,
                    actionMessage: model.actionMessage,
                    canCheckout: selection.repository == model.repository,
                    currentBranch: model.currentBranch,
                    isRunningAction: model.isRunningAction,
                    commentDraft: $model.commentDraft,
                    mentions: model.mentions,
                    isLoadingMentions: model.isLoadingMentions,
                    isRefreshingComments: model.isRefreshingComments,
                    onBack: model.closeDetail,
                    onRefresh: model.refreshDetail,
                    onRefreshComments: model.refreshComments,
                    onPollComments: model.pollComments,
                    onCheckout: model.checkout,
                    onSubmitComment: model.postComment,
                    onOpenThread: onOpenThread,
                    onConvertToDraft: model.convertToDraft,
                    onMerge: model.merge,
                    onClosePullRequest: model.closePullRequest)
            } else {
                PullRequestListView(model: model, onClose: onClose)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: rootURL?.standardizedFileURL.path) {
            await model.load(from: rootURL)
        }
    }
}

private struct PullRequestListView: View {
    @ObservedObject var model: PullRequestWorkspaceModel
    let onClose: () -> Void

    @State private var searchText = ""
    @State private var sort = PullRequestSort.recentlyUpdated
    @State private var filter = PullRequestFilter.all
    @State private var scope = PullRequestScope.all

    private var authored: [PullRequestSummary] {
        displayed(model.authored)
    }

    private var others: [PullRequestSummary] {
        displayed(model.others)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pull Requests")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close Pull Requests")
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Divider()

            VStack(spacing: 12) {
                controls

                Group {
                    if model.isLoadingList {
                        ProgressView("Loading pull requests…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = model.listError {
                        PullRequestEmptyState(
                            icon: "exclamationmark.triangle",
                            title: "Pull Requests Unavailable",
                            message: error,
                            actionTitle: "Try Again",
                            action: model.refreshList)
                    } else if authored.isEmpty, others.isEmpty {
                        PullRequestEmptyState(
                            icon: "arrow.triangle.pull",
                            title: "No Pull Requests",
                            message: "No open pull requests match the current filters.")
                    } else {
                        list
                    }
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 16)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search pull requests, or label:bug", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor))
            )

            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(PullRequestSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Picker("Filters", selection: $filter) {
                    ForEach(PullRequestFilter.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                Picker("Scope", selection: $scope) {
                    ForEach(PullRequestScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Label(scope.title, systemImage: "arrow.triangle.pull")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button(action: model.refreshList) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.bordered)
            .help("Refresh Pull Requests")
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !authored.isEmpty, scope != .others {
                    PullRequestSection(title: "Authored", items: authored, onSelect: model.select)
                }

                if !others.isEmpty, scope != .authored {
                    PullRequestSection(title: "Others", items: others, onSelect: model.select)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func displayed(_ source: [PullRequestSummary]) -> [PullRequestSummary] {
        guard (scope == .all)
            || (scope == .authored && source.first?.isAuthored == true)
            || (scope == .others && source.first?.isAuthored == false)
        else { return [] }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = source.filter { item in
            let matchesQuery = query.isEmpty
                || item.title.localizedCaseInsensitiveContains(query)
                || item.repository.localizedCaseInsensitiveContains(query)
                || item.author.login.localizedCaseInsensitiveContains(query)
                || item.labels.contains { label in
                    label.name.localizedCaseInsensitiveContains(query.replacingOccurrences(of: "label:", with: ""))
                }

            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .needsReview: matchesFilter = item.reviewDecision == "REVIEW_REQUIRED"
            case .changesRequested: matchesFilter = item.reviewDecision == "CHANGES_REQUESTED"
            case .drafts: matchesFilter = item.isDraft
            }
            return matchesQuery && matchesFilter
        }

        return filtered.sorted { lhs, rhs in
            switch sort {
            case .recentlyUpdated: return lhs.updatedDate > rhs.updatedDate
            case .oldestUpdated: return lhs.updatedDate < rhs.updatedDate
            case .mostChanges: return lhs.additions + lhs.deletions > rhs.additions + rhs.deletions
            }
        }
    }
}

private struct PullRequestSection: View {
    let title: String
    let items: [PullRequestSummary]
    let onSelect: (PullRequestSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            ForEach(items) { item in
                PullRequestRow(item: item) { onSelect(item) }
            }
        }
    }
}

private struct PullRequestRow: View {
    let item: PullRequestSummary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.green)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text("#\(item.number)")
                        Text("·")
                        Text(item.repository)
                        Text("·")
                        PullRequestAvatar(login: item.author.login, size: 14)
                        Text(item.author.login)

                        if let label = item.labels.first {
                            PullRequestLabel(label: label)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: 12)

                if item.reviewDecision == "CHANGES_REQUESTED" {
                    Text("Changes requested")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.yellow)
                }

                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 4) {
                        Image(systemName: item.checkState.icon)
                            .foregroundStyle(item.checkState.color)
                        if item.additions > 0 || item.deletions > 0 {
                            Text("+\(item.additions)").foregroundStyle(.green)
                            Text("-\(item.deletions)").foregroundStyle(.red)
                        }
                    }
                    .font(.system(size: 10, design: .monospaced))

                    Text(item.relativeUpdated)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Pull request \(item.number): \(item.title)")
    }
}

private struct PullRequestDetailView: View {
    let summary: PullRequestSummary
    let detail: PullRequestDetail?
    let diffs: [PullRequestFileDiff]
    let isLoading: Bool
    let error: String?
    let actionMessage: String?
    let canCheckout: Bool
    let currentBranch: String
    let isRunningAction: Bool
    @Binding var commentDraft: String
    let mentions: [PullRequestMention]
    let isLoadingMentions: Bool
    let isRefreshingComments: Bool
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onRefreshComments: () -> Void
    let onPollComments: () async -> Void
    let onCheckout: () -> Void
    let onSubmitComment: () -> Void
    let onOpenThread: (String) -> Void
    let onConvertToDraft: () -> Void
    let onMerge: (PullRequestMergeMethod, Bool) -> Void
    let onClosePullRequest: () -> Void

    @State private var tab = PullRequestDetailTab.summary
    @State private var mergeMethod = PullRequestMergeMethod.merge
    @State private var pendingAction: PullRequestPendingAction?
    @State private var actionsPresented = false

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            tabs
            Divider()

            if isLoading {
                ProgressView("Loading pull request…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                PullRequestEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Pull Request",
                    message: error,
                    actionTitle: "Try Again",
                    action: onRefresh)
            } else if let detail {
                detailContent(detail)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: action.isDestructive
                    ? .destructive(Text(action.confirmTitle)) { perform(action) }
                    : .default(Text(action.confirmTitle)) { perform(action) },
                secondaryButton: .cancel())
        }
        .overlay(alignment: .bottom) {
            if let actionMessage {
                Text(actionMessage)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.bottom, 14)
            }
        }
        .task(id: summary.id) {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return
                }
                await onPollComments()
            }
        }
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Back to Pull Requests")

                PullRequestLabelText(icon: "arrow.triangle.pull", text: "#\(summary.number)")

                Spacer()

                Button(action: onCheckout) {
                    if isRunningAction {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(checkoutButtonTitle, systemImage: "arrow.triangle.branch")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(!checkoutAvailable || checkoutBranch == currentBranch || isRunningAction)
                .help(checkoutHelp)

                Button {
                    pendingAction = .enableAutoMerge(mergeMethod)
                } label: {
                    Label("Auto-Merge (\(mergeMethod.title.lowercased()))", systemImage: "arrow.triangle.merge")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDraft)

                Button {
                    actionsPresented.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(.borderless)
                .fixedSize()
                .help("More pull request actions")
                .popover(isPresented: $actionsPresented, arrowEdge: .top) {
                    PullRequestActionsPopover(
                        isDraft: isDraft,
                        mergeMethod: $mergeMethod,
                        onSelect: handleMenuAction)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text(summary.repository)
                    Text("#\(summary.number)")
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .onTapGesture { NSWorkspace.shared.open(summary.url) }

                Text(summary.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(2)

                HStack(spacing: 7) {
                    PullRequestAvatar(login: summary.author.login, size: 18)
                    Text(summary.author.login)
                    Text("· updated \(summary.relativeUpdated)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                PullRequestLabelText(
                    icon: "arrow.triangle.branch",
                    text: detail?.baseRefName ?? summary.baseRefName)
                Image(systemName: "arrow.left")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                PullRequestLabelText(icon: nil, text: detail?.headRefName ?? summary.headRefName)

                Spacer()

                Label("\(summary.fileCount ?? detail?.files.count ?? 0) files", systemImage: "doc.badge.ellipsis")
                Text("+\(detail?.additions ?? summary.additions)").foregroundStyle(.green)
                Text("-\(detail?.deletions ?? summary.deletions)").foregroundStyle(.red)
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func openThread(_ action: PullRequestThreadAction) {
        onOpenThread(action.prompt(for: summary))
    }

    private var isDraft: Bool {
        detail?.isDraft ?? summary.isDraft
    }

    private var checkoutBranch: String {
        detail?.headRefName ?? summary.headRefName
    }

    private var checkoutAvailable: Bool {
        canCheckout && !checkoutBranch.isEmpty
    }

    private var checkoutButtonTitle: String {
        checkoutBranch == currentBranch ? "Checked out" : "Check out"
    }

    private var checkoutHelp: String {
        guard canCheckout else { return "Checkout is only available for this workspace" }
        guard !checkoutBranch.isEmpty else { return "Loading pull request branch…" }
        if checkoutBranch == currentBranch { return "Branch \(checkoutBranch) is active" }
        return "Check out branch \(checkoutBranch)"
    }

    private func handleMenuAction(_ action: PullRequestMenuAction) {
        actionsPresented = false
        switch action {
        case .linkThread:
            openThread(.link)
        case .refresh:
            onRefresh()
        case .askQuestion:
            openThread(.question)
        case .explain:
            openThread(.explain)
        case .fixFindings:
            openThread(.fixFindings)
        case .convertToDraft:
            pendingAction = .convertToDraft
        case .mergeNow:
            pendingAction = .mergeNow(mergeMethod)
        case let .setMergeMethod(method):
            mergeMethod = method
        case .openOnGitHub:
            NSWorkspace.shared.open(summary.url)
        case .copyLink:
            copyToPasteboard(summary.url.absoluteString)
        case .copyNumber:
            copyToPasteboard(String(summary.number))
        case .closePullRequest:
            pendingAction = .closePullRequest
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func perform(_ action: PullRequestPendingAction) {
        switch action {
        case .convertToDraft:
            onConvertToDraft()
        case let .enableAutoMerge(method):
            onMerge(method, true)
        case let .mergeNow(method):
            onMerge(method, false)
        case .closePullRequest:
            onClosePullRequest()
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(PullRequestDetailTab.allCases) { option in
                Button {
                    tab = option
                } label: {
                    Text(option.title)
                        .font(.system(size: 11, weight: option == tab ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(option == tab ? Color.primary.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Label(detailCheckState.description, systemImage: detailCheckState.icon)
                .foregroundStyle(detailCheckState.color)
                .font(.system(size: 10))
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    private var detailCheckState: PullRequestCheckState {
        guard let detail else { return summary.checkState }
        return PullRequestCheckState.aggregate(detail.statusCheckRollup)
    }

    @ViewBuilder private func detailContent(_ detail: PullRequestDetail) -> some View {
        switch tab {
        case .summary:
            PullRequestSummaryView(
                detail: detail,
                commentDraft: $commentDraft,
                mentions: mentions,
                isLoadingMentions: isLoadingMentions,
                isRefreshingComments: isRefreshingComments,
                isSubmittingComment: isRunningAction,
                onRefreshComments: onRefreshComments,
                onSubmitComment: onSubmitComment)
        case .timeline:
            PullRequestTimelineView(
                detail: detail,
                commentDraft: $commentDraft,
                mentions: mentions,
                isLoadingMentions: isLoadingMentions,
                isRefreshingComments: isRefreshingComments,
                isSubmittingComment: isRunningAction,
                onRefreshComments: onRefreshComments,
                onSubmitComment: onSubmitComment)
        case .code:
            PullRequestFilesView(detail: detail, diffs: diffs)
        }
    }
}

private struct PullRequestActionsPopover: View {
    let isDraft: Bool
    @Binding var mergeMethod: PullRequestMergeMethod
    let onSelect: (PullRequestMenuAction) -> Void

    var body: some View {
        VStack(spacing: 2) {
            PullRequestActionRow(title: "Link to thread", icon: "link") {
                onSelect(.linkThread)
            }
            PullRequestActionRow(title: "Refresh", icon: "arrow.clockwise") {
                onSelect(.refresh)
            }

            sectionDivider

            PullRequestActionRow(
                title: "Ask a question",
                subtitle: "Opens a thread that knows which pull request you mean.",
                icon: "questionmark.bubble") {
                    onSelect(.askQuestion)
                }
            PullRequestActionRow(
                title: "Explain this PR",
                subtitle: "A walk through the diff and what to read closely.",
                icon: "book.pages") {
                    onSelect(.explain)
                }
            PullRequestActionRow(title: "Fix findings in a thread", icon: "hammer") {
                onSelect(.fixFindings)
            }

            sectionDivider

            PullRequestActionRow(
                title: "Convert to draft",
                icon: "doc.badge.ellipsis",
                isDisabled: isDraft) {
                    onSelect(.convertToDraft)
                }
            PullRequestActionRow(
                title: "Merge now",
                icon: "bolt",
                isDisabled: isDraft) {
                    onSelect(.mergeNow)
                }

            ForEach(PullRequestMergeMethod.allCases) { method in
                PullRequestActionRow(
                    title: method.title,
                    icon: method.icon,
                    isSelected: method == mergeMethod) {
                        onSelect(.setMergeMethod(method))
                    }
            }

            sectionDivider

            PullRequestActionRow(title: "Open on GitHub", icon: "arrow.up.right.square") {
                onSelect(.openOnGitHub)
            }
            PullRequestActionRow(title: "Copy link", icon: "link", shortcut: "⇧⌘C") {
                onSelect(.copyLink)
            }
            PullRequestActionRow(title: "Copy PR number", icon: "number", shortcut: "⇧⌘K") {
                onSelect(.copyNumber)
            }

            sectionDivider

            PullRequestActionRow(
                title: "Close pull request",
                icon: "xmark.circle",
                isDestructive: true) {
                    onSelect(.closePullRequest)
                }
        }
        .padding(6)
        .frame(width: 360)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
    }
}

private struct PullRequestActionRow: View {
    let title: String
    var subtitle: String?
    let icon: String
    var shortcut: String?
    var isSelected = false
    var isDisabled = false
    var isDestructive = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: subtitle == nil ? .center : .top, spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                } else if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .padding(.horizontal, 9)
            .padding(.vertical, subtitle == nil ? 6 : 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering && !isDisabled ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .onHover { hovering = $0 }
    }
}

private struct PullRequestSummaryView: View {
    let detail: PullRequestDetail
    @Binding var commentDraft: String
    let mentions: [PullRequestMention]
    let isLoadingMentions: Bool
    let isRefreshingComments: Bool
    let isSubmittingComment: Bool
    let onRefreshComments: () -> Void
    let onSubmitComment: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                PullRequestMetadata(detail: detail)

                if !detail.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    PullRequestCard {
                        MarkdownContentView(
                            source: PullRequestMarkdown.sanitize(detail.body),
                            baseURL: detail.url)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                PullRequestChecks(checks: detail.statusCheckRollup)

                PullRequestCommentsHeader(
                    isRefreshing: isRefreshingComments,
                    onRefresh: onRefreshComments)

                if !detail.discussion.isEmpty {
                    ForEach(detail.discussion) { comment in
                        PullRequestCommentView(comment: comment, baseURL: detail.url)
                    }
                }

                PullRequestCommentComposer(
                    text: $commentDraft,
                    mentions: mentions,
                    isLoadingMentions: isLoadingMentions,
                    isSubmitting: isSubmittingComment,
                    onSubmit: onSubmitComment)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct PullRequestMetadata: View {
    let detail: PullRequestDetail

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 26, verticalSpacing: 12) {
            GridRow {
                Label("Reviewers", systemImage: "person.2")
                    .foregroundStyle(.secondary)
                Text(detail.reviews.isEmpty ? "None" : detail.reviewers.joined(separator: ", "))
            }
            GridRow {
                Label("Labels", systemImage: "tag")
                    .foregroundStyle(.secondary)
                if detail.labels.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    HStack {
                        ForEach(detail.labels) { label in
                            PullRequestLabel(label: label)
                        }
                    }
                }
            }
        }
        .font(.system(size: 11))
    }
}

private struct PullRequestChecks: View {
    let checks: [PullRequestCheck]

    var body: some View {
        DisclosureGroup("Checks") {
            if checks.isEmpty {
                Text("No checks reported.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(checks) { check in
                        HStack {
                            Image(systemName: check.state.icon)
                                .foregroundStyle(check.state.color)
                            Text(check.name)
                                .lineLimit(1)
                            Spacer()
                            Text(check.state.description)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.system(size: 11))
                .padding(.vertical, 8)
            }
        }
        .font(.system(size: 12, weight: .medium))
    }
}

private struct PullRequestTimelineView: View {
    let detail: PullRequestDetail
    @Binding var commentDraft: String
    let mentions: [PullRequestMention]
    let isLoadingMentions: Bool
    let isRefreshingComments: Bool
    let isSubmittingComment: Bool
    let onRefreshComments: () -> Void
    let onSubmitComment: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                PullRequestCommentsHeader(
                    isRefreshing: isRefreshingComments,
                    onRefresh: onRefreshComments)

                ForEach(detail.discussion) { comment in
                    PullRequestCommentView(comment: comment, baseURL: detail.url)
                }

                if detail.discussion.isEmpty {
                    PullRequestEmptyState(
                        icon: "text.bubble",
                        title: "No Activity Yet",
                        message: "Reviews and comments will appear here.")
                }

                PullRequestCommentComposer(
                    text: $commentDraft,
                    mentions: mentions,
                    isLoadingMentions: isLoadingMentions,
                    isSubmitting: isSubmittingComment,
                    onSubmit: onSubmitComment)
            }
            .frame(maxWidth: 920)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct PullRequestCommentsHeader: View {
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Comments")
                .font(.system(size: 12, weight: .semibold))

            Spacer()

            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.green)

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing)
            .help("Load the latest pull request comments")
        }
    }
}

struct PullRequestCommentComposer: View {
    @Binding var text: String
    let mentions: [PullRequestMention]
    let isLoadingMentions: Bool
    let isSubmitting: Bool
    let onSubmit: () -> Void

    private struct ActiveMention {
        let range: Range<String.Index>
        let query: String
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var activeMention: ActiveMention? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex > text.startIndex {
            let previous = text[text.index(before: atIndex)]
            guard !previous.isLetter, !previous.isNumber, previous != "_" else { return nil }
        }

        let queryStart = text.index(after: atIndex)
        let query = text[queryStart...]
        guard query.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        return ActiveMention(range: atIndex..<text.endIndex, query: String(query))
    }

    private var mentionSuggestions: [PullRequestMention] {
        guard let activeMention else { return [] }
        let query = activeMention.query.lowercased()
        return mentions
            .filter { query.isEmpty || $0.login.lowercased().hasPrefix(query) }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Add a comment", systemImage: "text.bubble")
                .font(.system(size: 12, weight: .semibold))

            PullRequestCommentTextEditor(text: $text) {
                guard let mention = mentionSuggestions.first else { return false }
                insert(mention)
                return true
            }
            .frame(minHeight: 86, maxHeight: 150)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor))
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Leave a comment…")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .allowsHitTesting(false)
                }
            }

            if activeMention != nil {
                mentionPicker
            }

            HStack {
                Text("Markdown is supported")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(action: onSubmit) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Comment", systemImage: "paperplane")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedText.isEmpty || isSubmitting)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    @ViewBuilder private var mentionPicker: some View {
        VStack(alignment: .leading, spacing: 2) {
            if isLoadingMentions, mentionSuggestions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading repository members…")
                }
                .foregroundStyle(.secondary)
                .padding(9)
            } else if mentionSuggestions.isEmpty {
                Text("No matching repository member")
                    .foregroundStyle(.secondary)
                    .padding(9)
            } else {
                ForEach(mentionSuggestions) { mention in
                    Button {
                        insert(mention)
                    } label: {
                        HStack(spacing: 8) {
                            PullRequestAvatar(login: mention.login, size: 20)
                            Text("@\(mention.login)")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .font(.system(size: 11))
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private func insert(_ mention: PullRequestMention) {
        guard let activeMention else { return }
        text.replaceSubrange(activeMention.range, with: "@\(mention.login) ")
    }
}

private struct PullRequestFilesView: View {
    let detail: PullRequestDetail
    let diffs: [PullRequestFileDiff]

    @State private var collapsedFiles: Set<String> = []
    @State private var wrapsLines = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(detail.files) { file in
                        PullRequestFileDiffView(
                            file: file,
                            diff: diffs.first { $0.path == file.path },
                            isCollapsed: collapsedFiles.contains(file.path),
                            wrapsLines: wrapsLines,
                            onToggle: { toggle(file.path) })
                    }
                }
                .padding(12)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Label("All commits", systemImage: "chevron.down")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text("\(detail.files.count) files")
                .foregroundStyle(.secondary)

            Spacer()

            Text("+\(detail.additions)").foregroundStyle(.green)
            Text("-\(detail.deletions)").foregroundStyle(.red)

            Divider().frame(height: 20)

            Button {
                wrapsLines.toggle()
            } label: {
                Image(systemName: wrapsLines ? "text.word.spacing" : "text.alignleft")
            }
            .buttonStyle(.bordered)
            .help(wrapsLines ? "Disable Line Wrapping" : "Wrap Long Lines")

            Button {
                if collapsedFiles.count == detail.files.count {
                    collapsedFiles.removeAll()
                } else {
                    collapsedFiles = Set(detail.files.map(\.path))
                }
            } label: {
                Image(systemName: collapsedFiles.count == detail.files.count
                    ? "rectangle.expand.vertical"
                    : "rectangle.compress.vertical")
            }
            .buttonStyle(.bordered)
            .help(collapsedFiles.count == detail.files.count ? "Expand All Files" : "Collapse All Files")
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private func toggle(_ path: String) {
        if collapsedFiles.contains(path) {
            collapsedFiles.remove(path)
        } else {
            collapsedFiles.insert(path)
        }
    }
}

private struct PullRequestFileDiffView: View {
    let file: PullRequestFile
    let diff: PullRequestFileDiff?
    let isCollapsed: Bool
    let wrapsLines: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(isCollapsed ? .degrees(-90) : .zero)
                    Image(systemName: fileIcon)
                        .foregroundStyle(file.changeType == "ADDED" ? Color.green : Color.secondary)
                    Text(file.path)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 10)
                    Text("+\(file.additions)").foregroundStyle(.green)
                    Text("-\(file.deletions)").foregroundStyle(.red)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.primary.opacity(0.055))

            if !isCollapsed {
                Divider()
                if let diff, !diff.lines.isEmpty {
                    if wrapsLines {
                        LazyVStack(spacing: 0) {
                            ForEach(diff.lines) { line in
                                PullRequestDiffLineView(line: line, wrapsLines: true)
                            }
                        }
                    } else {
                        ScrollView(.horizontal) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(diff.lines) { line in
                                    PullRequestDiffLineView(line: line, wrapsLines: false)
                                }
                            }
                            .frame(minWidth: 900, alignment: .leading)
                        }
                    }
                } else {
                    Text(file.changeType == "REMOVED" ? "File removed" : "Diff is unavailable for this file")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var fileIcon: String {
        switch file.changeType {
        case "ADDED": "doc.badge.plus"
        case "REMOVED": "doc.badge.minus"
        default: "doc"
        }
    }
}

private struct PullRequestDiffLineView: View {
    let line: PullRequestDiffLine
    let wrapsLines: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.oldLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 7)
                .foregroundStyle(.tertiary)
                .background(line.numberBackground)
            Text(line.newLine.map(String.init) ?? "")
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 7)
                .foregroundStyle(.tertiary)
                .background(line.numberBackground)
            Text(line.marker)
                .frame(width: 22, alignment: .center)
                .foregroundStyle(line.markerColor)
            Text(verbatim: line.content.isEmpty ? " " : line.content)
                .fixedSize(horizontal: !wrapsLines, vertical: false)
                .frame(maxWidth: wrapsLines ? .infinity : nil, alignment: .leading)
                .padding(.trailing, 12)
        }
        .font(.system(size: 11, design: .monospaced))
        .frame(maxWidth: .infinity, minHeight: 21, alignment: .leading)
        .background(line.background)
    }
}

private struct PullRequestCommentView: View {
    let comment: PullRequestDiscussionItem
    let baseURL: URL

    var body: some View {
        PullRequestCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    PullRequestAvatar(login: comment.author.login, size: 18)
                    Text(comment.author.login)
                        .fontWeight(.semibold)
                    Text("· \(comment.relativeDate)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let state = comment.state {
                        Text(state.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(state == "CHANGES_REQUESTED" ? Color.yellow : Color.green)
                    }
                }
                .font(.system(size: 11))

                MarkdownContentView(
                    source: PullRequestMarkdown.sanitize(
                        comment.body.isEmpty ? "Reviewed without a comment." : comment.body),
                    baseURL: baseURL)
                    .font(.system(size: 12))
            }
        }
    }
}

private struct PullRequestCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color(nsColor: .separatorColor))
            )
    }
}

private struct PullRequestEmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PullRequestAvatar: View {
    let login: String
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.28))
            Text(String(login.prefix(1)).uppercased())
                .font(.system(size: max(7, size * 0.46), weight: .bold))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct PullRequestLabel: View {
    let label: PullRequestLabelData

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(label.colorValue)
                .frame(width: 6, height: 6)
            Text(label.name)
                .lineLimit(1)
        }
        .font(.system(size: 9))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor)))
    }
}

private struct PullRequestLabelText: View {
    let icon: String?
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.system(size: 10, design: .monospaced))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

@MainActor
private final class PullRequestWorkspaceModel: ObservableObject {
    @Published private(set) var authored: [PullRequestSummary] = []
    @Published private(set) var others: [PullRequestSummary] = []
    @Published private(set) var repository = ""
    @Published private(set) var currentBranch = ""
    @Published private(set) var selection: PullRequestSummary?
    @Published private(set) var detail: PullRequestDetail?
    @Published private(set) var diffs: [PullRequestFileDiff] = []
    @Published private(set) var isLoadingList = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var listError: String?
    @Published private(set) var detailError: String?
    @Published private(set) var actionMessage: String?
    @Published private(set) var isRunningAction = false
    @Published private(set) var mentions: [PullRequestMention] = []
    @Published private(set) var isLoadingMentions = false
    @Published private(set) var isRefreshingComments = false
    @Published var commentDraft = ""

    private var rootURL: URL?
    private var listGeneration = UUID()
    private var detailGeneration = UUID()
    private var isRefreshingConversation = false

    func load(from rootURL: URL?) async {
        guard self.rootURL?.standardizedFileURL != rootURL?.standardizedFileURL || authored.isEmpty && others.isEmpty
        else { return }
        self.rootURL = rootURL
        await loadList()
    }

    func refreshList() {
        Task { await loadList() }
    }

    func select(_ item: PullRequestSummary) {
        selection = item
        detail = nil
        diffs = []
        mentions = []
        isLoadingMentions = false
        detailError = nil
        commentDraft = ""
        Task { await loadDetail(item) }
    }

    func closeDetail() {
        selection = nil
        detail = nil
        diffs = []
        mentions = []
        isLoadingMentions = false
        detailError = nil
        actionMessage = nil
        commentDraft = ""
        detailGeneration = UUID()
    }

    func refreshDetail() {
        guard let selection else { return }
        Task { await loadDetail(selection) }
    }

    func refreshComments() {
        guard let selection else { return }
        Task { await refreshConversation(for: selection, showsFeedback: true) }
    }

    func pollComments() async {
        guard let selection else { return }
        await refreshConversation(for: selection, showsFeedback: false)
    }

    func checkout() {
        guard let selection, selection.repository == repository, let rootURL else { return }
        let branch = detail?.headRefName ?? selection.headRefName
        guard !branch.isEmpty, branch != currentBranch else { return }
        runAction(
            working: "Checking out \(branch)…",
            success: "Checked out \(branch)",
            arguments: ["pr", "checkout", String(selection.number), "--repo", selection.repository],
            rootURL: rootURL,
            checkedOutBranch: branch)
    }

    func postComment() {
        guard let selection, let rootURL else { return }
        let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        runAction(
            working: "Posting comment…",
            success: "Comment posted on #\(selection.number)",
            arguments: [
                "pr", "comment", String(selection.number), "--repo", selection.repository,
                "--body", body,
            ],
            rootURL: rootURL,
            onSuccess: { [weak self] in
                self?.commentDraft = ""
                PullRequestNotification.deliver(
                    title: "Comment posted",
                    body: "\(selection.repository)#\(selection.number): \(selection.title)",
                    url: selection.url)
            })
    }

    func convertToDraft() {
        guard let selection, let rootURL else { return }
        runAction(
            success: "Converted #\(selection.number) to draft",
            arguments: [
                "pr", "ready", String(selection.number), "--repo", selection.repository,
                "--undo",
            ],
            rootURL: rootURL,
            reloadList: true)
    }

    func merge(method: PullRequestMergeMethod, automatically: Bool) {
        guard let selection, let rootURL else { return }
        var arguments = [
            "pr", "merge", String(selection.number), "--repo", selection.repository,
            method.flag,
        ]
        if automatically {
            arguments.append("--auto")
        }
        runAction(
            success: automatically
                ? "Auto-merge enabled for #\(selection.number)"
                : "Merged #\(selection.number)",
            arguments: arguments,
            rootURL: rootURL,
            reloadList: !automatically)
    }

    func closePullRequest() {
        guard let selection, let rootURL else { return }
        runAction(
            success: "Closed #\(selection.number)",
            arguments: [
                "pr", "close", String(selection.number), "--repo", selection.repository,
            ],
            rootURL: rootURL,
            reloadList: true)
    }

    private func loadList() async {
        let generation = UUID()
        listGeneration = generation
        isLoadingList = true
        listError = nil
        guard let rootURL else {
            authored = []
            others = []
            repository = ""
            currentBranch = ""
            isLoadingList = false
            listError = "Focus a terminal inside a Git repository to load pull requests."
            return
        }

        do {
            let payload = try await Task.detached(priority: .userInitiated) {
                try GitHubCLI.loadPullRequests(from: rootURL)
            }.value
            guard generation == listGeneration else { return }
            repository = payload.repository
            currentBranch = payload.currentBranch
            authored = payload.authored
            others = payload.others
            isLoadingList = false
        } catch {
            guard generation == listGeneration else { return }
            authored = []
            others = []
            isLoadingList = false
            listError = PullRequestError.userMessage(for: error)
        }
    }

    private func loadDetail(_ item: PullRequestSummary) async {
        let generation = UUID()
        let rootURL = rootURL
        detailGeneration = generation
        isLoadingDetail = true
        detailError = nil

        do {
            let payload = try await Task.detached(priority: .userInitiated) {
                let detail = try GitHubCLI.loadDetail(for: item, from: rootURL)
                let diffs = (try? GitHubCLI.loadDiff(for: item, from: rootURL)) ?? []
                return (detail, diffs)
            }.value
            guard generation == detailGeneration else { return }
            detail = payload.0
            diffs = payload.1
            mentions = payload.0.mentionableUsers
            isLoadingDetail = false

            isLoadingMentions = true
            let repositoryUsers = await Task.detached(priority: .utility) {
                (try? GitHubCLI.loadMentionableUsers(repository: item.repository, from: rootURL)) ?? []
            }.value
            guard generation == detailGeneration else { return }
            mentions = PullRequestMention.merged(repositoryUsers + payload.0.mentionableUsers)
            isLoadingMentions = false
        } catch {
            guard generation == detailGeneration else { return }
            detail = nil
            diffs = []
            isLoadingDetail = false
            isLoadingMentions = false
            detailError = PullRequestError.userMessage(for: error)
        }
    }

    private func refreshConversation(for item: PullRequestSummary, showsFeedback: Bool) async {
        guard selection?.id == item.id,
              !isLoadingDetail,
              !isRunningAction,
              !isRefreshingConversation
        else { return }

        isRefreshingConversation = true
        if showsFeedback { isRefreshingComments = true }
        defer {
            isRefreshingConversation = false
            if showsFeedback { isRefreshingComments = false }
        }

        let previousDetail = detail
        let previousIDs = Set(previousDetail?.discussion.map(\.id) ?? [])
        let rootURL = rootURL
        do {
            let updated = try await Task.detached(priority: .utility) {
                try GitHubCLI.loadDetail(for: item, from: rootURL)
            }.value
            guard selection?.id == item.id else { return }

            detail = updated
            mentions = PullRequestMention.merged(mentions + updated.mentionableUsers)
            if showsFeedback { actionMessage = "Comments are up to date" }

            guard previousDetail != nil,
                  let newest = updated.discussion.last(where: { !previousIDs.contains($0.id) })
            else { return }
            let excerpt = newest.body
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(120)
            PullRequestNotification.deliver(
                title: "New comment from @\(newest.author.login)",
                body: "\(item.repository)#\(item.number): \(excerpt)",
                url: item.url)
        } catch {
            if showsFeedback {
                actionMessage = PullRequestError.userMessage(for: error)
            }
        }
    }

    private func runAction(
        working: String = "Working…",
        success: String,
        arguments: [String],
        rootURL: URL,
        reloadList: Bool = false,
        checkedOutBranch: String? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        guard !isRunningAction else { return }
        actionMessage = working
        isRunningAction = true
        Task {
            defer { isRunningAction = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    _ = try GitHubCLI.run(arguments, from: rootURL)
                }.value
                actionMessage = success
                if let checkedOutBranch {
                    currentBranch = checkedOutBranch
                }
                onSuccess?()
                if reloadList {
                    await loadList()
                }
                refreshDetail()
            } catch {
                actionMessage = PullRequestError.userMessage(for: error)
            }
        }
    }
}

private enum GitHubCLI {
    struct ListPayload: Sendable {
        let repository: String
        let currentBranch: String
        let authored: [PullRequestSummary]
        let others: [PullRequestSummary]
    }

    static func loadPullRequests(from rootURL: URL) throws -> ListPayload {
        let repositoryData = try run(["repo", "view", "--json", "nameWithOwner"], from: rootURL)
        let repository = try JSONDecoder().decode(GitHubRepository.self, from: repositoryData).nameWithOwner
        let branch = (try? Self.currentBranch(from: rootURL)) ?? ""

        let authoredData = try run([
            "search", "prs", "--author", "@me", "--state", "open", "--sort", "updated",
            "--order", "desc", "--limit", "12", "--json",
            "number,title,url,author,updatedAt,isDraft,repository,labels",
        ], from: rootURL)
        let searchItems = try JSONDecoder().decode([GitHubSearchPullRequest].self, from: authoredData)
        let authored = searchItems.map { $0.summary }

        let otherData = try run([
            "pr", "list", "--repo", repository, "--state", "open", "--limit", "60", "--json",
            PullRequestSummary.listFields,
        ], from: rootURL)
        let repositoryItems = try JSONDecoder().decode([GitHubPullRequest].self, from: otherData)
        let authoredURLs = Set(authored.map(\.url))
        let others = repositoryItems
            .map { $0.summary(repository: repository, isAuthored: false) }
            .filter { !authoredURLs.contains($0.url) }

        return ListPayload(
            repository: repository,
            currentBranch: branch,
            authored: authored,
            others: others)
    }

    static func loadDetail(for item: PullRequestSummary, from rootURL: URL?) throws -> PullRequestDetail {
        let data = try run([
            "pr", "view", String(item.number), "--repo", item.repository, "--json",
            "number,title,url,author,updatedAt,isDraft,reviewDecision,statusCheckRollup,additions,deletions,labels,headRefName,baseRefName,body,comments,reviews,files,commits",
        ], from: rootURL)
        return try JSONDecoder().decode(PullRequestDetail.self, from: data)
    }

    static func loadDiff(for item: PullRequestSummary, from rootURL: URL?) throws -> [PullRequestFileDiff] {
        let data = try run([
            "pr", "diff", String(item.number), "--repo", item.repository,
            "--color", "never",
        ], from: rootURL)
        let source = String(data: data, encoding: .utf8) ?? ""
        return PullRequestDiffParser.parse(source)
    }

    static func loadMentionableUsers(repository: String, from rootURL: URL?) throws -> [PullRequestMention] {
        let collaboratorsPath = "repos/\(repository)/collaborators?affiliation=all&per_page=100"
        let contributorsPath = "repos/\(repository)/contributors?anon=false&per_page=100"
        let data: Data
        do {
            data = try run(["api", collaboratorsPath], from: rootURL)
        } catch {
            data = try run(["api", contributorsPath], from: rootURL)
        }

        return try JSONDecoder()
            .decode([GitHubRepositoryUser].self, from: data)
            .compactMap { user in
                guard let login = user.login, !login.isEmpty else { return nil }
                return PullRequestMention(login: login)
            }
    }

    @discardableResult
    static func run(_ arguments: [String], from rootURL: URL?) throws -> Data {
        try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["gh"] + arguments,
            from: rootURL,
            failureMessage: "The GitHub CLI command failed.")
    }

    static func currentBranch(from rootURL: URL) throws -> String {
        let data = try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/git"),
            arguments: ["branch", "--show-current"],
            from: rootURL,
            failureMessage: "Could not read the current Git branch.")
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func runCommand(
        executableURL: URL,
        arguments: [String],
        from rootURL: URL?,
        failureMessage: String
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = rootURL
        process.standardOutput = output
        process.standardError = output

        var environment = ProcessInfo.processInfo.environment
        let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"]
        let currentPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = (commonPaths + [currentPath]).joined(separator: ":")
        process.environment = environment

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PullRequestError.commandFailed(message ?? failureMessage)
        }
        return data
    }
}

private struct PullRequestSummary: Identifiable, Hashable, Sendable {
    static let listFields = "number,title,url,author,updatedAt,isDraft,reviewDecision,additions,deletions,labels,headRefName,baseRefName"

    var id: String { "\(repository)#\(number)" }
    let number: Int
    let title: String
    let url: URL
    let author: PullRequestAuthor
    let updatedAt: String
    let isDraft: Bool
    let reviewDecision: String
    let statusCheckRollup: [PullRequestCheck]
    let additions: Int
    let deletions: Int
    let labels: [PullRequestLabelData]
    let headRefName: String
    let baseRefName: String
    let repository: String
    let isAuthored: Bool
    let fileCount: Int?

    var updatedDate: Date { PullRequestDate.parse(updatedAt) }
    var relativeUpdated: String { PullRequestDate.relative(updatedAt) }
    var checkState: PullRequestCheckState {
        PullRequestCheckState.aggregate(statusCheckRollup)
    }
}

private struct GitHubPullRequest: Decodable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let author: PullRequestAuthor
    let updatedAt: String
    let isDraft: Bool
    let reviewDecision: String?
    let statusCheckRollup: [PullRequestCheck]?
    let additions: Int
    let deletions: Int
    let labels: [PullRequestLabelData]
    let headRefName: String
    let baseRefName: String

    func summary(repository: String, isAuthored: Bool) -> PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: title,
            url: url,
            author: author,
            updatedAt: updatedAt,
            isDraft: isDraft,
            reviewDecision: reviewDecision ?? "",
            statusCheckRollup: statusCheckRollup ?? [],
            additions: additions,
            deletions: deletions,
            labels: labels,
            headRefName: headRefName,
            baseRefName: baseRefName,
            repository: repository,
            isAuthored: isAuthored,
            fileCount: nil)
    }
}

private struct GitHubSearchPullRequest: Decodable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let author: PullRequestAuthor
    let updatedAt: String
    let isDraft: Bool
    let repository: GitHubRepository
    let labels: [PullRequestLabelData]

    var summary: PullRequestSummary {
        PullRequestSummary(
            number: number,
            title: title,
            url: url,
            author: author,
            updatedAt: updatedAt,
            isDraft: isDraft,
            reviewDecision: "",
            statusCheckRollup: [],
            additions: 0,
            deletions: 0,
            labels: labels,
            headRefName: "",
            baseRefName: "",
            repository: repository.nameWithOwner,
            isAuthored: true,
            fileCount: nil)
    }
}

private struct GitHubRepository: Decodable, Sendable {
    let nameWithOwner: String
}

private struct GitHubRepositoryUser: Decodable, Sendable {
    let login: String?
}

private struct PullRequestDetail: Decodable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let author: PullRequestAuthor
    let updatedAt: String
    let isDraft: Bool
    let reviewDecision: String?
    let statusCheckRollup: [PullRequestCheck]
    let additions: Int
    let deletions: Int
    let labels: [PullRequestLabelData]
    let headRefName: String
    let baseRefName: String
    let body: String
    let comments: [PullRequestComment]
    let reviews: [PullRequestReview]
    let files: [PullRequestFile]
    let commits: [PullRequestCommit]

    var reviewers: [String] {
        Array(Set(reviews.map(\.author.login))).sorted()
    }

    var mentionableUsers: [PullRequestMention] {
        PullRequestMention.merged(
            [PullRequestMention(login: author.login)]
                + comments.map { PullRequestMention(login: $0.author.login) }
                + reviews.map { PullRequestMention(login: $0.author.login) })
    }

    var discussion: [PullRequestDiscussionItem] {
        let comments = comments.map {
            PullRequestDiscussionItem(
                id: "comment-\($0.id)",
                author: $0.author,
                body: $0.body,
                date: $0.createdAt,
                state: nil)
        }
        let reviews = reviews.map {
            PullRequestDiscussionItem(
                id: "review-\($0.id)",
                author: $0.author,
                body: $0.body,
                date: $0.submittedAt ?? updatedAt,
                state: $0.state)
        }
        return (comments + reviews).sorted { $0.date < $1.date }
    }
}

struct PullRequestMention: Identifiable, Hashable, Sendable {
    var id: String { login.lowercased() }
    let login: String

    static func merged(_ values: [PullRequestMention]) -> [PullRequestMention] {
        var seen: Set<String> = []
        return values
            .filter { seen.insert($0.login.lowercased()).inserted }
            .sorted { $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending }
    }
}

private struct PullRequestAuthor: Decodable, Hashable, Sendable {
    let login: String
}

private struct PullRequestLabelData: Identifiable, Decodable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let color: String

    var colorValue: Color {
        guard color.count == 6, let value = Int(color, radix: 16) else { return .secondary }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }
}

private struct PullRequestCheck: Identifiable, Decodable, Hashable, Sendable {
    var id: String { "\(name)-\(status)-\(conclusion)" }
    let name: String
    let status: String
    let conclusion: String

    var state: PullRequestCheckState {
        PullRequestCheckState.from(status: status, conclusion: conclusion)
    }
}

private struct PullRequestComment: Decodable, Sendable {
    let id: String
    let author: PullRequestAuthor
    let body: String
    let createdAt: String
}

private struct PullRequestReview: Decodable, Sendable {
    let id: String
    let author: PullRequestAuthor
    let body: String
    let state: String
    let submittedAt: String?
}

private struct PullRequestFile: Identifiable, Decodable, Sendable {
    var id: String { path }
    let path: String
    let additions: Int
    let deletions: Int
    let changeType: String
}

private struct PullRequestFileDiff: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let lines: [PullRequestDiffLine]
}

private struct PullRequestDiffLine: Identifiable, Sendable {
    enum Kind: Sendable {
        case context
        case addition
        case deletion
        case hunk
        case metadata
    }

    let id: Int
    let oldLine: Int?
    let newLine: Int?
    let content: String
    let kind: Kind

    var marker: String {
        switch kind {
        case .addition: "+"
        case .deletion: "−"
        default: ""
        }
    }

    var markerColor: Color {
        switch kind {
        case .addition: .green
        case .deletion: .red
        case .hunk: .cyan
        case .context, .metadata: .secondary
        }
    }

    var background: Color {
        switch kind {
        case .addition: Color.green.opacity(0.10)
        case .deletion: Color.red.opacity(0.10)
        case .hunk: Color.blue.opacity(0.09)
        case .context, .metadata: Color.clear
        }
    }

    var numberBackground: Color {
        switch kind {
        case .addition: Color.green.opacity(0.16)
        case .deletion: Color.red.opacity(0.16)
        case .hunk: Color.blue.opacity(0.13)
        case .context, .metadata: Color.primary.opacity(0.025)
        }
    }
}

private enum PullRequestDiffParser {
    static func parse(_ source: String) -> [PullRequestFileDiff] {
        var result: [PullRequestFileDiff] = []
        var path: String?
        var oldPath: String?
        var lines: [PullRequestDiffLine] = []
        var oldLine: Int?
        var newLine: Int?
        var isInsideHunk = false
        var lineID = 0

        func appendCurrentFile() {
            guard let path, !path.isEmpty else { return }
            result.append(PullRequestFileDiff(path: path, lines: lines))
        }

        for substring in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(substring)

            if rawLine.hasPrefix("diff --git ") {
                appendCurrentFile()
                let components = rawLine.dropFirst("diff --git ".count).split(separator: " ")
                path = components.last.map { normalizedPath(String($0)) }
                oldPath = nil
                lines = []
                oldLine = nil
                newLine = nil
                isInsideHunk = false
                lineID = 0
                continue
            }

            if rawLine.hasPrefix("--- ") {
                oldPath = normalizedPath(String(rawLine.dropFirst(4)))
                continue
            }

            if rawLine.hasPrefix("+++ ") {
                let candidate = normalizedPath(String(rawLine.dropFirst(4)))
                path = candidate == "/dev/null" ? oldPath : candidate
                continue
            }

            if rawLine.hasPrefix("@@ ") {
                let starts = hunkStarts(rawLine)
                oldLine = starts.old
                newLine = starts.new
                isInsideHunk = true
                lines.append(PullRequestDiffLine(
                    id: lineID,
                    oldLine: nil,
                    newLine: nil,
                    content: rawLine,
                    kind: .hunk))
                lineID += 1
                continue
            }

            guard isInsideHunk else { continue }

            let line: PullRequestDiffLine
            if rawLine.hasPrefix("+") {
                line = PullRequestDiffLine(
                    id: lineID,
                    oldLine: nil,
                    newLine: newLine,
                    content: String(rawLine.dropFirst()),
                    kind: .addition)
                newLine = newLine.map { $0 + 1 }
            } else if rawLine.hasPrefix("-") {
                line = PullRequestDiffLine(
                    id: lineID,
                    oldLine: oldLine,
                    newLine: nil,
                    content: String(rawLine.dropFirst()),
                    kind: .deletion)
                oldLine = oldLine.map { $0 + 1 }
            } else if rawLine.hasPrefix("\\") {
                line = PullRequestDiffLine(
                    id: lineID,
                    oldLine: nil,
                    newLine: nil,
                    content: rawLine,
                    kind: .metadata)
            } else {
                guard !rawLine.isEmpty else { continue }
                line = PullRequestDiffLine(
                    id: lineID,
                    oldLine: oldLine,
                    newLine: newLine,
                    content: rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine,
                    kind: .context)
                oldLine = oldLine.map { $0 + 1 }
                newLine = newLine.map { $0 + 1 }
            }
            lines.append(line)
            lineID += 1
        }

        appendCurrentFile()
        return result
    }

    private static func normalizedPath(_ source: String) -> String {
        var value = source.split(separator: "\t", maxSplits: 1).first.map(String.init) ?? source
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"") && value.hasSuffix("\"") {
            value.removeFirst()
            value.removeLast()
        }
        if value.hasPrefix("a/") || value.hasPrefix("b/") {
            value.removeFirst(2)
        }
        return value
    }

    private static func hunkStarts(_ header: String) -> (old: Int?, new: Int?) {
        let components = header.split(separator: " ")
        guard components.count >= 3 else { return (nil, nil) }
        return (
            lineStart(String(components[1]), prefix: "-"),
            lineStart(String(components[2]), prefix: "+"))
    }

    private static func lineStart(_ range: String, prefix: Character) -> Int? {
        guard range.first == prefix else { return nil }
        return Int(range.dropFirst().split(separator: ",", maxSplits: 1).first ?? "")
    }
}

private struct PullRequestCommit: Decodable, Sendable {
    let oid: String
    let messageHeadline: String
}

private struct PullRequestDiscussionItem: Identifiable {
    let id: String
    let author: PullRequestAuthor
    let body: String
    let date: String
    let state: String?

    var relativeDate: String { PullRequestDate.relative(date) }
}

private enum PullRequestCheckState {
    case success, failure, pending, none

    var icon: String {
        switch self {
        case .success: return "checkmark.circle"
        case .failure: return "xmark.circle"
        case .pending: return "clock"
        case .none: return "circle.dashed"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .pending: return .yellow
        case .none: return .secondary
        }
    }

    var description: String {
        switch self {
        case .success: return "Checks passing"
        case .failure: return "Checks failing"
        case .pending: return "Checks pending"
        case .none: return "No checks"
        }
    }

    static func from(status: String, conclusion: String) -> PullRequestCheckState {
        if status != "COMPLETED" { return .pending }
        if ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE"].contains(conclusion) {
            return .failure
        }
        if ["SUCCESS", "NEUTRAL", "SKIPPED"].contains(conclusion) { return .success }
        return .pending
    }

    static func aggregate(_ checks: [PullRequestCheck]) -> PullRequestCheckState {
        guard !checks.isEmpty else { return .none }
        let states = checks.map(\.state)
        if states.contains(.failure) { return .failure }
        if states.contains(.pending) { return .pending }
        return .success
    }
}

private enum PullRequestSort: String, CaseIterable, Identifiable {
    case recentlyUpdated, oldestUpdated, mostChanges
    var id: Self { self }
    var title: String {
        switch self {
        case .recentlyUpdated: return "Recently updated"
        case .oldestUpdated: return "Oldest updated"
        case .mostChanges: return "Most changes"
        }
    }
}

private enum PullRequestFilter: String, CaseIterable, Identifiable {
    case all, needsReview, changesRequested, drafts
    var id: Self { self }
    var title: String {
        switch self {
        case .all: return "All"
        case .needsReview: return "Needs review"
        case .changesRequested: return "Changes requested"
        case .drafts: return "Drafts"
        }
    }
}

private enum PullRequestScope: String, CaseIterable, Identifiable {
    case all, authored, others
    var id: Self { self }
    var title: String {
        switch self {
        case .all: return "All"
        case .authored: return "Authored"
        case .others: return "Others"
        }
    }
}

private enum PullRequestDetailTab: String, CaseIterable, Identifiable {
    case summary, timeline, code
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

private enum PullRequestMergeMethod: String, CaseIterable, Identifiable {
    case merge
    case squash
    case rebase

    var id: Self { self }

    var title: String {
        switch self {
        case .merge: return "Merge"
        case .squash: return "Squash and merge"
        case .rebase: return "Rebase and merge"
        }
    }

    var flag: String { "--\(rawValue)" }

    var icon: String {
        switch self {
        case .merge: return "arrow.triangle.merge"
        case .squash: return "arrow.down.to.line.compact"
        case .rebase: return "arrow.triangle.branch"
        }
    }
}

private enum PullRequestThreadAction {
    case link
    case question
    case explain
    case fixFindings

    func prompt(for pullRequest: PullRequestSummary) -> String {
        let context = "pull request \(pullRequest.repository)#\(pullRequest.number) (\(pullRequest.url.absoluteString))"
        switch self {
        case .link:
            return "Link this Codex thread to \(context). Inspect it with gh, establish the relevant context, then wait for my next instruction."
        case .question:
            return "I want to ask about \(context). Inspect the pull request with gh, establish the relevant context, then ask what I want to know. Do not modify files."
        case .explain:
            return "Explain \(context). Walk through the diff, its behavior changes, risks, and what to read closely. Do not modify files."
        case .fixFindings:
            return "Inspect review feedback and failing checks on \(context), fix every actionable finding in the working tree, and verify the result in the real target environment. Do not merge, close, or push the pull request."
        }
    }
}

private enum PullRequestMenuAction {
    case linkThread
    case refresh
    case askQuestion
    case explain
    case fixFindings
    case convertToDraft
    case mergeNow
    case setMergeMethod(PullRequestMergeMethod)
    case openOnGitHub
    case copyLink
    case copyNumber
    case closePullRequest
}

private enum PullRequestPendingAction: Identifiable {
    case convertToDraft
    case enableAutoMerge(PullRequestMergeMethod)
    case mergeNow(PullRequestMergeMethod)
    case closePullRequest

    var id: String {
        switch self {
        case .convertToDraft: return "convert-to-draft"
        case let .enableAutoMerge(method): return "auto-merge-\(method.rawValue)"
        case let .mergeNow(method): return "merge-now-\(method.rawValue)"
        case .closePullRequest: return "close"
        }
    }

    var title: String {
        switch self {
        case .convertToDraft: return "Convert to draft?"
        case .enableAutoMerge: return "Enable auto-merge?"
        case .mergeNow: return "Merge pull request now?"
        case .closePullRequest: return "Close pull request?"
        }
    }

    var message: String {
        switch self {
        case .convertToDraft:
            return "GitHub will mark this pull request as not ready for review."
        case let .enableAutoMerge(method):
            return "GitHub will use \(method.title.lowercased()) after all merge requirements pass."
        case let .mergeNow(method):
            return "GitHub will merge this pull request immediately using \(method.title.lowercased())."
        case .closePullRequest:
            return "The pull request will be closed without merging."
        }
    }

    var confirmTitle: String {
        switch self {
        case .convertToDraft: return "Convert to Draft"
        case .enableAutoMerge: return "Enable Auto-Merge"
        case .mergeNow: return "Merge Now"
        case .closePullRequest: return "Close Pull Request"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .mergeNow, .closePullRequest: return true
        case .convertToDraft, .enableAutoMerge: return false
        }
    }
}

private enum PullRequestMarkdown {
    static func sanitize(_ source: String) -> String {
        var value = replacing(#"(?s)<!--.*?-->"#, with: "", in: source)

        value = replacing(
            #"(?is)<details\b[^>]*>\s*<summary\b[^>]*>(.*?)</summary>"#,
            with: "\n#### $1\n",
            in: value)
        value = replacing(
            #"(?is)<summary\b[^>]*>(.*?)</summary>"#,
            with: "\n#### $1\n",
            in: value)
        value = replacing(#"(?i)<br\s*/?>"#, with: "\n", in: value)
        value = replacing(#"(?i)</?details\b[^>]*>"#, with: "", in: value)

        value = replacing(
            #"(?is)<a\b[^>]*href\s*=\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>"#,
            with: "[$2]($1)",
            in: value)
        value = replacing(#"(?i)<(?:strong|b)\b[^>]*>"#, with: "**", in: value)
        value = replacing(#"(?i)</(?:strong|b)>"#, with: "**", in: value)
        value = replacing(#"(?i)<(?:em|i)\b[^>]*>"#, with: "_", in: value)
        value = replacing(#"(?i)</(?:em|i)>"#, with: "_", in: value)
        value = replacing(#"(?i)<code\b[^>]*>"#, with: "`", in: value)
        value = replacing(#"(?i)</code>"#, with: "`", in: value)

        value = replacing(#"(?i)<li\b[^>]*>"#, with: "- ", in: value)
        value = replacing(#"(?i)</li>"#, with: "\n", in: value)
        value = replacing(#"(?i)</?(?:ul|ol)\b[^>]*>"#, with: "\n", in: value)
        value = replacing(#"(?i)</?p\b[^>]*>"#, with: "\n\n", in: value)
        value = replacing(#"(?i)</?(?:div|section|blockquote)\b[^>]*>"#, with: "\n", in: value)
        value = replacing(#"\n{3,}"#, with: "\n\n", in: value)

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(
        _ pattern: String,
        with template: String,
        in source: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
        let range = NSRange(source.startIndex..., in: source)
        return expression.stringByReplacingMatches(
            in: source,
            range: range,
            withTemplate: template)
    }
}

private struct PullRequestCommentTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onTab: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text
        else { return }

        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PullRequestCommentTextEditor

        init(parent: PullRequestCommentTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertTab(_:))
                    || commandSelector == #selector(NSResponder.insertTabIgnoringFieldEditor(_:))
            else { return false }
            return parent.onTab()
        }
    }
}

enum PullRequestNotification {
    static let categoryIdentifier = "momok.pull-request"
    static let openActionIdentifier = "momok.pull-request.open"
    static let urlKey = "pullRequestURL"
    private static let soundFilename = "universfield-new-notification-047-494238.caf"
    private static let fallbackSound: NSSound? = {
        guard let url = Bundle.main.url(
            forResource: "universfield-new-notification-047-494238",
            withExtension: "caf")
        else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }()

    static func deliver(title: String, body: String, url: URL) {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    playFallbackSound()
                    return
                }

                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = UNNotificationSound(
                    named: UNNotificationSoundName(rawValue: soundFilename))
                content.categoryIdentifier = categoryIdentifier
                content.threadIdentifier = "pull-requests"
                content.userInfo = [urlKey: url.absoluteString]

                let request = UNNotificationRequest(
                    identifier: "pull-request-comment-\(UUID().uuidString)",
                    content: content,
                    trigger: nil)
                try await center.add(request)
            } catch {
                playFallbackSound()
            }
        }
    }

    private static func playFallbackSound() {
        if fallbackSound?.play() != true {
            NSSound.beep()
        }
    }
}

private enum PullRequestError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message): return message
        }
    }

    static func userMessage(for error: Error) -> String {
        let value = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if value.contains("not logged into") || value.contains("authentication") {
            return "Sign in with `gh auth login`, then refresh."
        }
        if value.contains("not a git repository") || value.contains("unable to determine") {
            return "Focus a terminal inside a Git repository, then refresh."
        }
        return value
    }
}

private enum PullRequestDate {
    private static let formatter = ISO8601DateFormatter()

    static func parse(_ value: String) -> Date {
        formatter.date(from: value) ?? .distantPast
    }

    static func relative(_ value: String) -> String {
        let date = parse(value)
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3_600 { return "\(max(1, Int(interval / 60)))m ago" }
        if interval < 86_400 { return "\(max(1, Int(interval / 3_600)))h ago" }
        if interval < 2_592_000 { return "\(max(1, Int(interval / 86_400)))d ago" }
        if interval < 31_536_000 { return "\(max(1, Int(interval / 2_592_000)))mo ago" }
        return "\(max(1, Int(interval / 31_536_000)))y ago"
    }
}
