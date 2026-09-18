import AppKit
import SwiftUI

/// A repository issue dashboard backed by the authenticated `gh` CLI session.
struct TerminalIssuesView: View {
    let rootURL: URL?
    let onClose: () -> Void

    @StateObject private var model = IssueWorkspaceModel()

    var body: some View {
        Group {
            if let selection = model.selection {
                IssueDetailView(
                    summary: selection,
                    detail: model.detail,
                    isLoading: model.isLoadingDetail,
                    isRefreshingComments: model.isRefreshingComments,
                    isPostingComment: model.isPostingComment,
                    error: model.detailError,
                    actionMessage: model.actionMessage,
                    commentDraft: $model.commentDraft,
                    mentions: model.mentions,
                    isLoadingMentions: model.isLoadingMentions,
                    metadata: model.metadata,
                    metadataOptions: model.metadataOptions,
                    isLoadingMetadata: model.isLoadingMetadata,
                    isUpdatingMetadata: model.isUpdatingMetadata,
                    onBack: model.closeDetail,
                    onRefresh: model.refreshDetail,
                    onRefreshComments: model.refreshComments,
                    onPollComments: model.pollComments,
                    onSubmitComment: model.postComment,
                    onToggleAssignee: model.toggleAssignee,
                    onToggleLabel: model.toggleLabel,
                    onSetType: model.setType,
                    onSetMilestone: model.setMilestone,
                    onToggleProject: model.toggleProject,
                    onSetProjectField: model.setProjectField,
                    onSetRelationship: model.setRelationship,
                    onRemoveRelationship: model.removeRelationship,
                    onCreateBranch: model.createBranch,
                    onToggleSubscription: model.toggleSubscription)
            } else {
                IssueListView(model: model, onClose: onClose)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: rootURL?.standardizedFileURL.path) {
            await model.load(from: rootURL)
        }
    }
}

private struct IssueListView: View {
    @ObservedObject var model: IssueWorkspaceModel
    let onClose: () -> Void

    @State private var searchText = ""

    private var displayedIssues: [IssueSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.issues }
        return model.issues.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || String($0.number).contains(query)
                || $0.author.login.localizedCaseInsensitiveContains(query)
                || $0.labels.contains { $0.name.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Issues")
                    .font(.system(size: 13, weight: .semibold))

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search issues", text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 230)
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color(nsColor: .separatorColor))
                )

                Button(action: model.refreshList) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("Refresh Issues")

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close Issues")
            }
            .padding(.horizontal, 20)
            .frame(height: 58)

            Divider()

            if model.isLoadingList {
                ProgressView("Loading issues…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.listError {
                IssueEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Issues",
                    message: error,
                    actionTitle: "Try Again",
                    action: model.refreshList)
            } else if displayedIssues.isEmpty {
                IssueEmptyState(
                    icon: "exclamationmark.circle",
                    title: searchText.isEmpty ? "No Issues" : "No Matching Issues",
                    message: searchText.isEmpty
                        ? "This repository has no issues."
                        : "Try a different search term.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedIssues) { issue in
                            IssueRow(issue: issue) {
                                model.select(issue)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }
}

private struct IssueRow: View {
    let issue: IssueSummary
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: issue.state == "OPEN" ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(issue.state == "OPEN" ? Color.green : Color.purple)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 7) {
                    Text(issue.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        Text("#\(issue.number)")
                        Text("·")
                        Text(issue.author.login)
                        Text("· updated \(issue.relativeUpdated)")

                        ForEach(issue.labels.prefix(3)) { label in
                            IssueLabelView(label: label)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(hovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("Issue \(issue.number): \(issue.title)")
    }
}

private struct IssueDetailView: View {
    let summary: IssueSummary
    let detail: IssueDetail?
    let isLoading: Bool
    let isRefreshingComments: Bool
    let isPostingComment: Bool
    let error: String?
    let actionMessage: String?
    @Binding var commentDraft: String
    let mentions: [PullRequestMention]
    let isLoadingMentions: Bool
    let metadata: IssueMetadata?
    let metadataOptions: IssueMetadataOptions
    let isLoadingMetadata: Bool
    let isUpdatingMetadata: Bool
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onRefreshComments: () -> Void
    let onPollComments: () async -> Void
    let onSubmitComment: () -> Void
    let onToggleAssignee: (String) -> Void
    let onToggleLabel: (String) -> Void
    let onSetType: (IssueTypeOption?) -> Void
    let onSetMilestone: (String?) -> Void
    let onToggleProject: (IssueProjectOption) -> Void
    let onSetProjectField: (IssueProjectItem, IssueProjectField, IssueProjectFieldOption?) -> Void
    let onSetRelationship: (IssueRelationshipKind, Int) -> Void
    let onRemoveRelationship: (IssueRelationshipKind, IssueReference) -> Void
    let onCreateBranch: (String) -> Void
    let onToggleSubscription: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("Loading issue…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                IssueEmptyState(
                    icon: "exclamationmark.triangle",
                    title: "Could Not Load Issue",
                    message: error,
                    actionTitle: "Try Again",
                    action: onRefresh)
            } else if let detail {
                HStack(spacing: 0) {
                    content(detail)

                    Divider()

                    IssueMetadataSidebar(
                        issue: summary,
                        detail: detail,
                        metadata: metadata,
                        options: metadataOptions,
                        isLoading: isLoadingMetadata,
                        isUpdating: isUpdatingMetadata,
                        onToggleAssignee: onToggleAssignee,
                        onToggleLabel: onToggleLabel,
                        onSetType: onSetType,
                        onSetMilestone: onSetMilestone,
                        onToggleProject: onToggleProject,
                        onSetProjectField: onSetProjectField,
                        onSetRelationship: onSetRelationship,
                        onRemoveRelationship: onRemoveRelationship,
                        onCreateBranch: onCreateBranch,
                        onToggleSubscription: onToggleSubscription)
                        .frame(width: 300)
                }
            }
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .help("Back to Issues")

                Label("#\(summary.number)", systemImage: "exclamationmark.circle")
                    .font(.system(size: 10, design: .monospaced))

                Spacer()

                Button {
                    NSWorkspace.shared.open(summary.url)
                } label: {
                    Label("Open on GitHub", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 5) {
                Text(summary.repository)
                Text("#\(summary.number)")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .onTapGesture { NSWorkspace.shared.open(summary.url) }

            Text(summary.title)
                .font(.system(size: 18, weight: .semibold))

            HStack(spacing: 7) {
                IssueAvatar(login: summary.author.login, size: 20)
                Text(summary.author.login)
                Text("· updated \(summary.relativeUpdated)")
                Text("·")
                Label(
                    summary.state.capitalized,
                    systemImage: summary.state == "OPEN"
                        ? "exclamationmark.circle.fill"
                        : "checkmark.circle.fill")
                    .foregroundStyle(summary.state == "OPEN" ? Color.green : Color.purple)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func content(_ detail: IssueDetail) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if !detail.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    IssueCard {
                        MarkdownContentView(source: detail.body, baseURL: detail.url)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                IssueCommentsHeader(
                    isRefreshing: isRefreshingComments,
                    onRefresh: onRefreshComments)

                if detail.comments.isEmpty {
                    Text("No comments yet.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.comments) { comment in
                        IssueCommentView(comment: comment, baseURL: detail.url)
                    }
                }

                PullRequestCommentComposer(
                    text: $commentDraft,
                    mentions: mentions,
                    isLoadingMentions: isLoadingMentions,
                    isSubmitting: isPostingComment,
                    onSubmit: onSubmitComment)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct IssueCommentsHeader: View {
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
                    ProgressView().controlSize(.small)
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isRefreshing)
            .help("Load the latest issue comments")
        }
    }
}

private struct IssueMetadataSidebar: View {
    let issue: IssueSummary
    let detail: IssueDetail
    let metadata: IssueMetadata?
    let options: IssueMetadataOptions
    let isLoading: Bool
    let isUpdating: Bool
    let onToggleAssignee: (String) -> Void
    let onToggleLabel: (String) -> Void
    let onSetType: (IssueTypeOption?) -> Void
    let onSetMilestone: (String?) -> Void
    let onToggleProject: (IssueProjectOption) -> Void
    let onSetProjectField: (IssueProjectItem, IssueProjectField, IssueProjectFieldOption?) -> Void
    let onSetRelationship: (IssueRelationshipKind, Int) -> Void
    let onRemoveRelationship: (IssueRelationshipKind, IssueReference) -> Void
    let onCreateBranch: (String) -> Void
    let onToggleSubscription: () -> Void

    @State private var relationshipKind = IssueRelationshipKind.parent
    @State private var relationshipNumber = ""
    @State private var showingRelationshipEditor = false
    @State private var branchName = ""
    @State private var showingBranchEditor = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    ProgressView("Loading metadata…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }

                metadataSection("Assignees") {
                    Menu {
                        if options.assignees.isEmpty {
                            Text("No repository members found")
                        }
                        ForEach(options.assignees) { user in
                            Button {
                                onToggleAssignee(user.login)
                            } label: {
                                selectedLabel(
                                    user.login,
                                    selected: detail.assignees.contains { $0.login == user.login })
                            }
                        }
                    } label: {
                        sectionGear
                    }
                } content: {
                    if detail.assignees.isEmpty {
                        Text("No one")
                    } else {
                        FlowLayout(items: detail.assignees.map(\.login)) { login in
                            Label(login, systemImage: "person.crop.circle.fill")
                        }
                    }
                }

                metadataSection("Labels") {
                    Menu {
                        if options.labels.isEmpty { Text("No labels found") }
                        ForEach(options.labels) { label in
                            Button {
                                onToggleLabel(label.name)
                            } label: {
                                selectedLabel(
                                    label.name,
                                    selected: detail.labels.contains { $0.name == label.name })
                            }
                        }
                    } label: {
                        sectionGear
                    }
                } content: {
                    if detail.labels.isEmpty {
                        Text("No labels")
                    } else {
                        FlowLayout(items: detail.labels.map(\.name)) { name in
                            Text(name)
                        }
                    }
                }

                metadataSection("Type") {
                    Menu {
                        Button("No type") { onSetType(nil) }
                        Divider()
                        ForEach(options.issueTypes) { type in
                            Button {
                                onSetType(type)
                            } label: {
                                selectedLabel(type.name, selected: metadata?.issueType?.id == type.id)
                            }
                        }
                    } label: {
                        sectionGear
                    }
                } content: {
                    Text(metadata?.issueType?.name ?? "No type")
                }

                fieldsSection
                projectsSection

                metadataSection("Milestone") {
                    Menu {
                        Button("No milestone") { onSetMilestone(nil) }
                        Divider()
                        ForEach(options.milestones) { milestone in
                            Button {
                                onSetMilestone(milestone.title)
                            } label: {
                                selectedLabel(
                                    milestone.title,
                                    selected: detail.milestone?.title == milestone.title)
                            }
                        }
                    } label: {
                        sectionGear
                    }
                } content: {
                    Text(detail.milestone?.title ?? "No milestone")
                }

                relationshipsSection
                developmentSection
                notificationsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
        .disabled(isUpdating)
        .overlay(alignment: .top) {
            if isUpdating {
                ProgressView().controlSize(.small).padding(.top, 8)
            }
        }
        .sheet(isPresented: $showingRelationshipEditor) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add relationship").font(.headline)
                Picker("Relationship", selection: $relationshipKind) {
                    ForEach(IssueRelationshipKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                TextField("Issue number", text: $relationshipNumber)
                HStack {
                    Spacer()
                    Button("Cancel") { showingRelationshipEditor = false }
                    Button("Add") {
                        guard let number = Int(relationshipNumber), number > 0 else { return }
                        onSetRelationship(relationshipKind, number)
                        showingRelationshipEditor = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Int(relationshipNumber) == nil)
                }
            }
            .padding(20)
            .frame(width: 360)
        }
        .sheet(isPresented: $showingBranchEditor) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create linked branch").font(.headline)
                TextField("Branch name", text: $branchName)
                Text("This creates a branch on GitHub and links it to issue #\(issue.number).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel") { showingBranchEditor = false }
                    Button("Create") {
                        onCreateBranch(branchName)
                        showingBranchEditor = false
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(branchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 390)
        }
    }

    private var fieldsSection: some View {
        metadataSection("Fields") {
            EmptyView()
        } content: {
            if let project = metadata?.projectItems.first,
               let priority = project.fields.first(where: { $0.name == "Priority" }) {
                fieldMenu(project: project, field: priority)
            } else {
                HStack {
                    Text("Priority")
                    Spacer()
                    Text("Choose an option")
                }
                .padding(9)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var projectsSection: some View {
        metadataSection("Projects") {
            Menu {
                if options.projects.isEmpty { Text("No projects found") }
                ForEach(options.projects) { project in
                    Button {
                        onToggleProject(project)
                    } label: {
                        selectedLabel(
                            project.title,
                            selected: metadata?.projectItems.contains { $0.project.id == project.id } == true)
                    }
                }
            } label: {
                sectionGear
            }
        } content: {
            if metadata?.projectItems.isEmpty != false {
                Text("No projects")
            } else {
                ForEach(metadata?.projectItems ?? []) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            NSWorkspace.shared.open(item.project.url)
                        } label: {
                            Label(item.project.title, systemImage: "rectangle.split.2x2")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.plain)

                        if let status = item.fields.first(where: { $0.name == "Status" }) {
                            fieldMenu(project: item, field: status)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))
                }
            }
        }
    }

    private var relationshipsSection: some View {
        metadataSection("Relationships") {
            Button {
                relationshipNumber = ""
                showingRelationshipEditor = true
            } label: {
                sectionGear
            }
            .buttonStyle(.plain)
        } content: {
            let relationships = metadata?.relationships ?? []
            if relationships.isEmpty {
                Text("None yet")
            } else {
                ForEach(relationships) { relationship in
                    HStack(spacing: 6) {
                        Image(systemName: relationship.kind.icon)
                        Button("#\(relationship.issue.number) \(relationship.issue.title)") {
                            NSWorkspace.shared.open(relationship.issue.url)
                        }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                        Spacer(minLength: 2)
                        Button {
                            onRemoveRelationship(relationship.kind, relationship.issue)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .help("Remove relationship")
                    }
                }
            }
        }
    }

    private var developmentSection: some View {
        metadataSection("Development") {
            Button {
                branchName = "issue-\(issue.number)"
                showingBranchEditor = true
            } label: {
                sectionGear
            }
            .buttonStyle(.plain)
        } content: {
            if metadata?.development.isEmpty != false {
                Button("Create a branch") {
                    branchName = "issue-\(issue.number)"
                    showingBranchEditor = true
                }
                .buttonStyle(.link)
            } else {
                ForEach(metadata?.development ?? []) { item in
                    Button {
                        NSWorkspace.shared.open(item.url)
                    } label: {
                        Label(item.title, systemImage: item.icon)
                    }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                }
            }
        }
    }

    private var notificationsSection: some View {
        metadataSection("Notifications") {
            EmptyView()
        } content: {
            Button(action: onToggleSubscription) {
                Label(
                    metadata?.isSubscribed == true ? "Unsubscribe" : "Subscribe",
                    systemImage: metadata?.isSubscribed == true ? "bell.slash" : "bell")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func metadataSection<Accessory: View, Content: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                accessory()
            }
            content()
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func fieldMenu(project: IssueProjectItem, field: IssueProjectField) -> some View {
        Menu {
            Button("Clear") { onSetProjectField(project, field, nil) }
            Divider()
            ForEach(field.options) { option in
                Button {
                    onSetProjectField(project, field, option)
                } label: {
                    selectedLabel(option.name, selected: field.value == option.name)
                }
            }
        } label: {
            HStack {
                Text(field.name)
                Spacer()
                Text(field.value ?? "Choose an option")
                Image(systemName: "chevron.down")
            }
            .padding(9)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var sectionGear: some View {
        Image(systemName: "gearshape")
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
    }

    private func selectedLabel(_ title: String, selected: Bool) -> some View {
        Label(title, systemImage: selected ? "checkmark" : "circle")
    }
}

private struct FlowLayout<Content: View>: View {
    let items: [String]
    let content: (String) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.self) { item in content(item) }
        }
    }
}

private struct IssueCommentView: View {
    let comment: IssueComment
    let baseURL: URL

    var body: some View {
        IssueCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    IssueAvatar(login: comment.author.login, size: 22)
                    Text(comment.author.login)
                        .fontWeight(.semibold)
                    Text("· \(comment.relativeCreated)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.system(size: 11))

                MarkdownContentView(source: comment.body, baseURL: baseURL)
                    .font(.system(size: 12))
            }
        }
    }
}

private struct IssueCard<Content: View>: View {
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

private struct IssueAvatar: View {
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

private struct IssueLabelView: View {
    let label: IssueLabel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(label.colorValue)
                .frame(width: 6, height: 6)
            Text(label.name).lineLimit(1)
        }
        .font(.system(size: 9))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(nsColor: .separatorColor)))
    }
}

private struct IssueEmptyState: View {
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
            if let actionTitle, let action {
                Button(actionTitle, action: action)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private final class IssueWorkspaceModel: ObservableObject {
    @Published private(set) var repository = ""
    @Published private(set) var issues: [IssueSummary] = []
    @Published private(set) var selection: IssueSummary?
    @Published private(set) var detail: IssueDetail?
    @Published private(set) var mentions: [PullRequestMention] = []
    @Published private(set) var metadata: IssueMetadata?
    @Published private(set) var metadataOptions = IssueMetadataOptions()
    @Published private(set) var isLoadingList = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var isLoadingMentions = false
    @Published private(set) var isRefreshingComments = false
    @Published private(set) var isPostingComment = false
    @Published private(set) var isLoadingMetadata = false
    @Published private(set) var isUpdatingMetadata = false
    @Published private(set) var listError: String?
    @Published private(set) var detailError: String?
    @Published private(set) var actionMessage: String?
    @Published var commentDraft = ""

    private var rootURL: URL?
    private var listGeneration = UUID()
    private var detailGeneration = UUID()
    private var isRefreshingConversation = false

    func load(from rootURL: URL?) async {
        guard self.rootURL?.standardizedFileURL != rootURL?.standardizedFileURL || issues.isEmpty
        else { return }
        self.rootURL = rootURL
        await loadList()
    }

    func refreshList() {
        Task { await loadList() }
    }

    func select(_ issue: IssueSummary) {
        selection = issue
        detail = nil
        mentions = []
        metadata = nil
        metadataOptions = IssueMetadataOptions()
        commentDraft = ""
        detailError = nil
        actionMessage = nil
        Task { await loadDetail(issue) }
    }

    func closeDetail() {
        selection = nil
        detail = nil
        mentions = []
        metadata = nil
        metadataOptions = IssueMetadataOptions()
        commentDraft = ""
        detailError = nil
        actionMessage = nil
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

    func postComment() {
        guard let selection, let rootURL, !isPostingComment else { return }
        let body = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        isPostingComment = true
        actionMessage = "Posting comment…"
        Task {
            defer { isPostingComment = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try IssueGitHubCLI.postComment(
                        issue: selection,
                        body: body,
                        from: rootURL)
                }.value
                guard self.selection?.id == selection.id else { return }
                commentDraft = ""
                actionMessage = "Comment posted on issue #\(selection.number)"
                PullRequestNotification.deliver(
                    title: "Issue comment posted",
                    body: "\(selection.repository)#\(selection.number): \(selection.title)",
                    url: selection.url)
                await loadDetail(selection)
            } catch {
                actionMessage = IssueError.userMessage(for: error)
            }
        }
    }

    func toggleAssignee(_ login: String) {
        guard let detail else { return }
        let assigned = detail.assignees.contains { $0.login == login }
        updateIssue(
            arguments: [assigned ? "--remove-assignee" : "--add-assignee", login],
            success: assigned ? "Assignee removed" : "Assignee added")
    }

    func toggleLabel(_ name: String) {
        guard let detail else { return }
        let applied = detail.labels.contains { $0.name == name }
        updateIssue(
            arguments: [applied ? "--remove-label" : "--add-label", name],
            success: applied ? "Label removed" : "Label added")
    }

    func setType(_ type: IssueTypeOption?) {
        performMetadataUpdate(success: type.map { "Type set to \($0.name)" } ?? "Type removed") {
            try IssueGitHubCLI.setIssueType(
                issue: $0,
                issueID: $1.issueID,
                typeID: type?.id,
                from: $2)
        }
    }

    func setMilestone(_ title: String?) {
        updateIssue(
            arguments: title.map { ["--milestone", $0] } ?? ["--remove-milestone"],
            success: title.map { "Milestone set to \($0)" } ?? "Milestone removed")
    }

    func toggleProject(_ project: IssueProjectOption) {
        let applied = metadata?.projectItems.contains { $0.project.id == project.id } == true
        updateIssue(
            arguments: [applied ? "--remove-project" : "--add-project", project.title],
            success: applied ? "Project removed" : "Project added")
    }

    func setProjectField(
        _ item: IssueProjectItem,
        _ field: IssueProjectField,
        _ option: IssueProjectFieldOption?
    ) {
        performMetadataUpdate(success: "\(field.name) updated") { _, _, rootURL in
            try IssueGitHubCLI.setProjectField(
                item: item,
                field: field,
                option: option,
                from: rootURL)
        }
    }

    func setRelationship(_ kind: IssueRelationshipKind, _ number: Int) {
        performMetadataUpdate(success: "Relationship added") {
            try IssueGitHubCLI.addRelationship(
                kind: kind,
                issue: $0,
                issueID: $1.issueID,
                relatedNumber: number,
                from: $2)
        }
    }

    func removeRelationship(_ kind: IssueRelationshipKind, _ related: IssueReference) {
        performMetadataUpdate(success: "Relationship removed") {
            try IssueGitHubCLI.removeRelationship(
                kind: kind,
                issue: $0,
                issueID: $1.issueID,
                related: related,
                from: $2)
        }
    }

    func createBranch(_ name: String) {
        let branch = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return }
        performMetadataUpdate(success: "Branch \(branch) created") {
            try IssueGitHubCLI.createBranch(issue: $0, name: branch, from: $2)
        }
    }

    func toggleSubscription() {
        performMetadataUpdate(success: metadata?.isSubscribed == true ? "Notifications disabled" : "Notifications enabled") {
            try IssueGitHubCLI.setSubscription(
                issueID: $1.issueID,
                subscribed: !$1.isSubscribed,
                from: $2)
        }
    }

    private func loadList() async {
        let generation = UUID()
        listGeneration = generation
        isLoadingList = true
        listError = nil
        guard let rootURL else {
            issues = []
            repository = ""
            isLoadingList = false
            listError = "Focus a terminal inside a Git repository to load issues."
            return
        }

        do {
            let payload = try await Task.detached(priority: .userInitiated) {
                try IssueGitHubCLI.loadIssues(from: rootURL)
            }.value
            guard generation == listGeneration else { return }
            repository = payload.repository
            issues = payload.issues
            isLoadingList = false
        } catch {
            guard generation == listGeneration else { return }
            issues = []
            isLoadingList = false
            listError = IssueError.userMessage(for: error)
        }
    }

    private func loadDetail(_ issue: IssueSummary) async {
        let generation = UUID()
        let rootURL = rootURL
        detailGeneration = generation
        isLoadingDetail = true
        isLoadingMetadata = true
        detailError = nil

        do {
            async let updatedTask = Task.detached(priority: .userInitiated) {
                try IssueGitHubCLI.loadDetail(for: issue, from: rootURL)
            }.value
            async let metadataTask = Task.detached(priority: .utility) {
                try IssueGitHubCLI.loadMetadata(for: issue, from: rootURL)
            }.value
            let (updated, metadataPayload) = try await (updatedTask, metadataTask)
            guard generation == detailGeneration else { return }
            detail = updated
            metadata = metadataPayload.metadata
            metadataOptions = metadataPayload.options
            mentions = updated.mentionableUsers
            isLoadingDetail = false
            isLoadingMetadata = false

            isLoadingMentions = true
            let repositoryUsers = await Task.detached(priority: .utility) {
                (try? IssueGitHubCLI.loadMentionableUsers(
                    repository: issue.repository,
                    from: rootURL)) ?? []
            }.value
            guard generation == detailGeneration else { return }
            mentions = PullRequestMention.merged(repositoryUsers + updated.mentionableUsers)
            isLoadingMentions = false
        } catch {
            guard generation == detailGeneration else { return }
            detail = nil
            isLoadingDetail = false
            isLoadingMetadata = false
            isLoadingMentions = false
            detailError = IssueError.userMessage(for: error)
        }
    }

    private func updateIssue(arguments: [String], success: String) {
        performMetadataUpdate(success: success) {
            try IssueGitHubCLI.editIssue(issue: $0, arguments: arguments, from: $2)
        }
    }

    private func performMetadataUpdate(
        success: String,
        operation: @escaping @Sendable (IssueSummary, IssueMetadata, URL?) throws -> Void
    ) {
        guard let issue = selection, let metadata, !isUpdatingMetadata else { return }
        let rootURL = rootURL
        isUpdatingMetadata = true
        actionMessage = "Updating issue…"
        Task {
            defer { isUpdatingMetadata = false }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try operation(issue, metadata, rootURL)
                }.value
                guard selection?.id == issue.id else { return }
                actionMessage = success
                await loadDetail(issue)
                await refreshListAfterMetadataUpdate()
            } catch {
                actionMessage = IssueError.userMessage(for: error)
            }
        }
    }

    private func refreshListAfterMetadataUpdate() async {
        guard let rootURL else { return }
        let task = Task.detached(priority: .utility) {
            try IssueGitHubCLI.loadIssues(from: rootURL)
        }
        guard let payload = try? await task.value else { return }
        repository = payload.repository
        issues = payload.issues
        if let selectedNumber = selection?.number,
           let refreshed = issues.first(where: { $0.number == selectedNumber }) {
            selection = refreshed
        }
    }

    private func refreshConversation(for issue: IssueSummary, showsFeedback: Bool) async {
        guard selection?.id == issue.id,
              !isLoadingDetail,
              !isPostingComment,
              !isRefreshingConversation
        else { return }

        isRefreshingConversation = true
        if showsFeedback { isRefreshingComments = true }
        defer {
            isRefreshingConversation = false
            if showsFeedback { isRefreshingComments = false }
        }

        let previousDetail = detail
        let previousIDs = Set(previousDetail?.comments.map(\.id) ?? [])
        let rootURL = rootURL
        do {
            let updated = try await Task.detached(priority: .utility) {
                try IssueGitHubCLI.loadDetail(for: issue, from: rootURL)
            }.value
            guard selection?.id == issue.id else { return }

            detail = updated
            mentions = PullRequestMention.merged(mentions + updated.mentionableUsers)
            if showsFeedback { actionMessage = "Comments are up to date" }

            guard previousDetail != nil,
                  let newest = updated.comments.last(where: { !previousIDs.contains($0.id) })
            else { return }
            let excerpt = newest.body
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(120)
            PullRequestNotification.deliver(
                title: "New issue comment from @\(newest.author.login)",
                body: "\(issue.repository)#\(issue.number): \(excerpt)",
                url: issue.url)
        } catch {
            if showsFeedback {
                actionMessage = IssueError.userMessage(for: error)
            }
        }
    }
}

private enum IssueGitHubCLI {
    struct ListPayload: Sendable {
        let repository: String
        let issues: [IssueSummary]
    }

    static func loadIssues(from rootURL: URL) throws -> ListPayload {
        let repositoryData = try run(["repo", "view", "--json", "nameWithOwner"], from: rootURL)
        let repository = try JSONDecoder()
            .decode(IssueRepository.self, from: repositoryData)
            .nameWithOwner
        let data = try run([
            "issue", "list", "--repo", repository, "--state", "all", "--limit", "100",
            "--json", "number,title,url,author,updatedAt,state,labels",
        ], from: rootURL)
        let issues = try JSONDecoder().decode([IssueListItem].self, from: data)
            .map { $0.summary(repository: repository) }
            .sorted { $0.updatedDate > $1.updatedDate }
        return ListPayload(repository: repository, issues: issues)
    }

    static func loadDetail(for issue: IssueSummary, from rootURL: URL?) throws -> IssueDetail {
        let data = try run([
            "issue", "view", String(issue.number), "--repo", issue.repository, "--json",
            "number,title,url,author,createdAt,updatedAt,state,body,labels,assignees,milestone,comments",
        ], from: rootURL)
        return try JSONDecoder().decode(IssueDetail.self, from: data)
    }

    static func loadMetadata(
        for issue: IssueSummary,
        from rootURL: URL?
    ) throws -> IssueMetadataPayload {
        let components = issue.repository.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            throw IssueError.commandFailed("Invalid repository name: \(issue.repository)")
        }
        let owner = components[0]
        let repositoryName = components[1]
        let data = try run([
            "api", "graphql",
            "-f", "query=\(metadataQuery)",
            "-f", "owner=\(owner)",
            "-f", "name=\(repositoryName)",
            "-F", "number=\(issue.number)",
        ], from: rootURL)
        let envelope = try JSONDecoder().decode(IssueMetadataEnvelope.self, from: data)
        guard let node = envelope.data.repository.issue else {
            throw IssueError.commandFailed("Issue #\(issue.number) was not found.")
        }

        let labels = try? JSONDecoder().decode(
            [IssueLabel].self,
            from: run([
                "label", "list", "--repo", issue.repository, "--limit", "100",
                "--json", "name,color",
            ], from: rootURL))
        let milestones = try? JSONDecoder().decode(
            [IssueMilestone].self,
            from: run([
                "api", "repos/\(issue.repository)/milestones?state=all&per_page=100",
            ], from: rootURL))
        let assignees = (try? loadMentionableUsers(repository: issue.repository, from: rootURL)) ?? []
        let issueTypes = loadIssueTypes(owner: owner, from: rootURL)
        let projects = loadProjects(owner: owner, from: rootURL)

        var projectItems = node.projectItems.nodes.map { item in
            let pairs: [(String, (name: String, value: String))] = item.fieldValues.nodes.compactMap { value in
                guard let field = value.field, let name = value.name else { return nil }
                return (field.id, (name: field.name, value: name))
            }
            let values = Dictionary(uniqueKeysWithValues: pairs)
            let available = loadProjectFields(
                project: item.project,
                values: values,
                from: rootURL)
            return IssueProjectItem(id: item.id, project: item.project, fields: available)
        }
        projectItems.sort { $0.project.title.localizedCaseInsensitiveCompare($1.project.title) == .orderedAscending }

        var relationships: [IssueRelationship] = []
        if let parent = node.parent {
            relationships.append(IssueRelationship(kind: .parent, issue: parent))
        }
        relationships += node.subIssues.nodes.map { IssueRelationship(kind: .subIssue, issue: $0) }
        relationships += node.blockedBy.nodes.map { IssueRelationship(kind: .blockedBy, issue: $0) }
        relationships += node.blocking.nodes.map { IssueRelationship(kind: .blocking, issue: $0) }

        var development = node.closedByPullRequestsReferences.nodes.map {
            IssueDevelopmentItem(
                id: "pr-\($0.number)",
                title: "#\($0.number) \($0.title)",
                url: $0.url,
                icon: "arrow.triangle.pull")
        }
        development += loadLinkedBranches(for: issue, from: rootURL)

        return IssueMetadataPayload(
            metadata: IssueMetadata(
                issueID: node.id,
                issueType: node.issueType,
                projectItems: projectItems,
                relationships: relationships,
                development: development,
                isSubscribed: node.viewerSubscription == "SUBSCRIBED"),
            options: IssueMetadataOptions(
                assignees: assignees,
                labels: labels ?? [],
                milestones: milestones ?? [],
                issueTypes: issueTypes,
                projects: projects))
    }

    static func loadMentionableUsers(
        repository: String,
        from rootURL: URL?
    ) throws -> [PullRequestMention] {
        let collaboratorsPath = "repos/\(repository)/collaborators?affiliation=all&per_page=100"
        let contributorsPath = "repos/\(repository)/contributors?anon=false&per_page=100"
        let data: Data
        do {
            data = try run(["api", collaboratorsPath], from: rootURL)
        } catch {
            data = try run(["api", contributorsPath], from: rootURL)
        }
        return try JSONDecoder()
            .decode([IssueRepositoryUser].self, from: data)
            .compactMap { user in
                guard let login = user.login, !login.isEmpty else { return nil }
                return PullRequestMention(login: login)
            }
    }

    static func postComment(issue: IssueSummary, body: String, from rootURL: URL) throws {
        _ = try run([
            "issue", "comment", String(issue.number), "--repo", issue.repository,
            "--body", body,
        ], from: rootURL)
    }

    static func editIssue(
        issue: IssueSummary,
        arguments: [String],
        from rootURL: URL?
    ) throws {
        _ = try run(
            ["issue", "edit", String(issue.number), "--repo", issue.repository] + arguments,
            from: rootURL)
    }

    static func setIssueType(
        issue: IssueSummary,
        issueID: String,
        typeID: String?,
        from rootURL: URL?
    ) throws {
        _ = try run([
            "api", "graphql",
            "-f", "query=\(updateIssueTypeMutation)",
            "-f", "issueID=\(issueID)",
            "-F", "typeID=\(typeID ?? "null")",
        ], from: rootURL)
    }

    static func setProjectField(
        item: IssueProjectItem,
        field: IssueProjectField,
        option: IssueProjectFieldOption?,
        from rootURL: URL?
    ) throws {
        var arguments = [
            "project", "item-edit",
            "--id", item.id,
            "--project-id", item.project.id,
            "--field-id", field.id,
        ]
        if let option {
            arguments += ["--single-select-option-id", option.id]
        } else {
            arguments.append("--clear")
        }
        _ = try run(arguments, from: rootURL)
    }

    static func addRelationship(
        kind: IssueRelationshipKind,
        issue: IssueSummary,
        issueID: String,
        relatedNumber: Int,
        from rootURL: URL?
    ) throws {
        let related = try loadIssueReference(
            repository: issue.repository,
            number: relatedNumber,
            from: rootURL)
        let query: String
        let variables: [(String, String)]
        switch kind {
        case .parent:
            query = addSubIssueMutation
            variables = [("issueID", related.id), ("relatedID", issueID)]
        case .subIssue:
            query = addSubIssueMutation
            variables = [("issueID", issueID), ("relatedID", related.id)]
        case .blockedBy:
            query = addBlockedByMutation
            variables = [("issueID", issueID), ("relatedID", related.id)]
        case .blocking:
            query = addBlockedByMutation
            variables = [("issueID", related.id), ("relatedID", issueID)]
        }
        try runMutation(query, variables: variables, from: rootURL)
    }

    static func removeRelationship(
        kind: IssueRelationshipKind,
        issue: IssueSummary,
        issueID: String,
        related: IssueReference,
        from rootURL: URL?
    ) throws {
        let query: String
        let variables: [(String, String)]
        switch kind {
        case .parent:
            query = removeSubIssueMutation
            variables = [("issueID", related.id), ("relatedID", issueID)]
        case .subIssue:
            query = removeSubIssueMutation
            variables = [("issueID", issueID), ("relatedID", related.id)]
        case .blockedBy:
            query = removeBlockedByMutation
            variables = [("issueID", issueID), ("relatedID", related.id)]
        case .blocking:
            query = removeBlockedByMutation
            variables = [("issueID", related.id), ("relatedID", issueID)]
        }
        try runMutation(query, variables: variables, from: rootURL)
    }

    static func createBranch(issue: IssueSummary, name: String, from rootURL: URL?) throws {
        _ = try run([
            "issue", "develop", String(issue.number), "--repo", issue.repository,
            "--name", name,
        ], from: rootURL)
    }

    static func setSubscription(issueID: String, subscribed: Bool, from rootURL: URL?) throws {
        _ = try run([
            "api", "graphql",
            "-f", "query=\(updateSubscriptionMutation)",
            "-f", "issueID=\(issueID)",
            "-f", "state=\(subscribed ? "SUBSCRIBED" : "UNSUBSCRIBED")",
        ], from: rootURL)
    }

    private static func loadIssueTypes(owner: String, from rootURL: URL?) -> [IssueTypeOption] {
        guard let data = try? run([
            "api", "graphql",
            "-f", "query=\(issueTypesQuery)",
            "-f", "owner=\(owner)",
        ], from: rootURL),
        let envelope = try? JSONDecoder().decode(IssueTypesEnvelope.self, from: data)
        else { return [] }
        return envelope.data.organization?.issueTypes.nodes ?? []
    }

    private static func loadProjects(owner: String, from rootURL: URL?) -> [IssueProjectOption] {
        guard let data = try? run([
            "project", "list", "--owner", owner, "--limit", "100", "--format", "json",
        ], from: rootURL),
        let envelope = try? JSONDecoder().decode(IssueProjectsEnvelope.self, from: data)
        else { return [] }
        return envelope.projects.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func loadProjectFields(
        project: IssueProjectOption,
        values: [String: (name: String, value: String)],
        from rootURL: URL?
    ) -> [IssueProjectField] {
        guard let data = try? run([
            "project", "field-list", String(project.number), "--owner", project.owner.login,
            "--format", "json",
        ], from: rootURL),
        let envelope = try? JSONDecoder().decode(IssueProjectFieldsEnvelope.self, from: data)
        else { return [] }
        return envelope.fields
            .filter { $0.name == "Status" || $0.name == "Priority" }
            .map { field in
                IssueProjectField(
                    id: field.id,
                    name: field.name,
                    value: values[field.id]?.value
                        ?? values.values.first(where: { $0.name == field.name })?.value,
                    options: field.options ?? [])
            }
    }

    private static func loadLinkedBranches(
        for issue: IssueSummary,
        from rootURL: URL?
    ) -> [IssueDevelopmentItem] {
        guard let data = try? run([
            "issue", "develop", String(issue.number), "--repo", issue.repository, "--list",
        ], from: rootURL),
        let output = String(data: data, encoding: .utf8)
        else { return [] }
        return output.split(whereSeparator: \.isNewline).enumerated().compactMap { index, line in
            let title = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let branch = title.split(separator: ":").last.map(String.init) ?? title
            let encoded = branch.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? branch
            let url = URL(string: "https://github.com/\(issue.repository)/tree/\(encoded)") ?? issue.url
            return IssueDevelopmentItem(
                id: "branch-\(index)-\(title)",
                title: title,
                url: url,
                icon: "arrow.triangle.branch")
        }
    }

    private static func loadIssueReference(
        repository: String,
        number: Int,
        from rootURL: URL?
    ) throws -> IssueReference {
        let components = repository.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2 else {
            throw IssueError.commandFailed("Invalid repository name: \(repository)")
        }
        let data = try run([
            "api", "graphql",
            "-f", "query=\(issueReferenceQuery)",
            "-f", "owner=\(components[0])",
            "-f", "name=\(components[1])",
            "-F", "number=\(number)",
        ], from: rootURL)
        let envelope = try JSONDecoder().decode(IssueReferenceEnvelope.self, from: data)
        guard let issue = envelope.data.repository.issue else {
            throw IssueError.commandFailed("Related issue #\(number) was not found.")
        }
        return issue
    }

    private static func runMutation(
        _ query: String,
        variables: [(String, String)],
        from rootURL: URL?
    ) throws {
        var arguments = ["api", "graphql", "-f", "query=\(query)"]
        for (name, value) in variables {
            arguments += ["-f", "\(name)=\(value)"]
        }
        _ = try run(arguments, from: rootURL)
    }

    private static let metadataQuery = #"""
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issue(number: $number) {
          id viewerSubscription
          issueType { id name description }
          parent { id number title url state }
          subIssues(first: 50) { nodes { id number title url state } }
          blockedBy(first: 50) { nodes { id number title url state } }
          blocking(first: 50) { nodes { id number title url state } }
          closedByPullRequestsReferences(first: 50) { nodes { number title url state } }
          projectItems(first: 50) {
            nodes {
              id
              project {
                id number title url
                owner { ... on Organization { login } ... on User { login } }
              }
              fieldValues(first: 50) {
                nodes {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name optionId
                    field { ... on ProjectV2SingleSelectField { id name } }
                  }
                }
              }
            }
          }
        }
      }
    }
    """#

    private static let issueTypesQuery = #"""
    query($owner: String!) {
      organization(login: $owner) {
        issueTypes(first: 50) { nodes { id name description } }
      }
    }
    """#

    private static let issueReferenceQuery = #"""
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        issue(number: $number) { id number title url state }
      }
    }
    """#

    private static let updateIssueTypeMutation = #"""
    mutation($issueID: ID!, $typeID: ID) {
      updateIssueIssueType(input: { issueId: $issueID, issueTypeId: $typeID }) {
        issue { id }
      }
    }
    """#

    private static let updateSubscriptionMutation = #"""
    mutation($issueID: ID!, $state: SubscriptionState!) {
      updateSubscription(input: { subscribableId: $issueID, state: $state }) {
        subscribable { viewerSubscription }
      }
    }
    """#

    private static let addSubIssueMutation = #"""
    mutation($issueID: ID!, $relatedID: ID!) {
      addSubIssue(input: { issueId: $issueID, subIssueId: $relatedID, replaceParent: true }) {
        issue { id }
      }
    }
    """#

    private static let removeSubIssueMutation = #"""
    mutation($issueID: ID!, $relatedID: ID!) {
      removeSubIssue(input: { issueId: $issueID, subIssueId: $relatedID }) {
        issue { id }
      }
    }
    """#

    private static let addBlockedByMutation = #"""
    mutation($issueID: ID!, $relatedID: ID!) {
      addBlockedBy(input: { issueId: $issueID, blockingIssueId: $relatedID }) {
        issue { id }
      }
    }
    """#

    private static let removeBlockedByMutation = #"""
    mutation($issueID: ID!, $relatedID: ID!) {
      removeBlockedBy(input: { issueId: $issueID, blockingIssueId: $relatedID }) {
        issue { id }
      }
    }
    """#

    @discardableResult
    private static func run(_ arguments: [String], from rootURL: URL?) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh"] + arguments
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
            throw IssueError.commandFailed(message ?? "The GitHub CLI command failed.")
        }
        return data
    }
}

private struct IssueSummary: Identifiable, Sendable {
    var id: String { "\(repository)#\(number)" }
    let number: Int
    let title: String
    let url: URL
    let author: IssueAuthor
    let updatedAt: String
    let state: String
    let labels: [IssueLabel]
    let repository: String

    var updatedDate: Date { IssueDate.parse(updatedAt) }
    var relativeUpdated: String { IssueDate.relative(updatedAt) }
}

private struct IssueListItem: Decodable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let author: IssueAuthor
    let updatedAt: String
    let state: String
    let labels: [IssueLabel]

    func summary(repository: String) -> IssueSummary {
        IssueSummary(
            number: number,
            title: title,
            url: url,
            author: author,
            updatedAt: updatedAt,
            state: state,
            labels: labels,
            repository: repository)
    }
}

private struct IssueDetail: Decodable, Sendable {
    let number: Int
    let title: String
    let url: URL
    let author: IssueAuthor
    let createdAt: String
    let updatedAt: String
    let state: String
    let body: String
    let labels: [IssueLabel]
    let assignees: [IssueAuthor]
    let milestone: IssueMilestone?
    let comments: [IssueComment]

    var mentionableUsers: [PullRequestMention] {
        PullRequestMention.merged(
            [PullRequestMention(login: author.login)]
                + assignees.map { PullRequestMention(login: $0.login) }
                + comments.map { PullRequestMention(login: $0.author.login) })
    }
}

private struct IssueMetadata: Sendable {
    let issueID: String
    let issueType: IssueTypeOption?
    let projectItems: [IssueProjectItem]
    let relationships: [IssueRelationship]
    let development: [IssueDevelopmentItem]
    let isSubscribed: Bool
}

private struct IssueMetadataOptions: Sendable {
    var assignees: [PullRequestMention] = []
    var labels: [IssueLabel] = []
    var milestones: [IssueMilestone] = []
    var issueTypes: [IssueTypeOption] = []
    var projects: [IssueProjectOption] = []
}

private struct IssueMetadataPayload: Sendable {
    let metadata: IssueMetadata
    let options: IssueMetadataOptions
}

private struct IssueMilestone: Identifiable, Decodable, Sendable {
    var id: String { title }
    let title: String
}

private struct IssueTypeOption: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let description: String?
}

private struct IssueProjectOption: Identifiable, Decodable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let owner: IssueProjectOwner
}

private struct IssueProjectOwner: Decodable, Sendable {
    let login: String
}

private struct IssueProjectItem: Identifiable, Sendable {
    let id: String
    let project: IssueProjectOption
    let fields: [IssueProjectField]
}

private struct IssueProjectField: Identifiable, Sendable {
    let id: String
    let name: String
    let value: String?
    let options: [IssueProjectFieldOption]
}

private struct IssueProjectFieldOption: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
}

private struct IssueReference: Identifiable, Decodable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let state: String
}

private enum IssueRelationshipKind: String, CaseIterable, Identifiable, Sendable {
    case parent
    case subIssue
    case blockedBy
    case blocking

    var id: String { rawValue }
    var title: String {
        switch self {
        case .parent: "Parent issue"
        case .subIssue: "Sub-issue"
        case .blockedBy: "Blocked by"
        case .blocking: "Blocking"
        }
    }
    var icon: String {
        switch self {
        case .parent: "arrow.up.left"
        case .subIssue: "arrow.down.right"
        case .blockedBy: "exclamationmark.octagon"
        case .blocking: "hand.raised"
        }
    }
}

private struct IssueRelationship: Identifiable, Sendable {
    var id: String { "\(kind.rawValue)-\(issue.id)" }
    let kind: IssueRelationshipKind
    let issue: IssueReference
}

private struct IssueDevelopmentItem: Identifiable, Sendable {
    let id: String
    let title: String
    let url: URL
    let icon: String
}

private struct IssueComment: Identifiable, Decodable, Sendable {
    let id: String
    let author: IssueAuthor
    let body: String
    let createdAt: String

    var relativeCreated: String { IssueDate.relative(createdAt) }
}

private struct IssueAuthor: Decodable, Sendable {
    let login: String
}

private struct IssueLabel: Identifiable, Decodable, Sendable {
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

private struct IssueRepository: Decodable, Sendable {
    let nameWithOwner: String
}

private struct IssueRepositoryUser: Decodable, Sendable {
    let login: String?
}

private struct IssueMetadataEnvelope: Decodable, Sendable {
    let data: DataNode

    struct DataNode: Decodable, Sendable {
        let repository: RepositoryNode
    }

    struct RepositoryNode: Decodable, Sendable {
        let issue: IssueNode?
    }

    struct IssueNode: Decodable, Sendable {
        let id: String
        let viewerSubscription: String
        let issueType: IssueTypeOption?
        let parent: IssueReference?
        let subIssues: IssueReferenceConnection
        let blockedBy: IssueReferenceConnection
        let blocking: IssueReferenceConnection
        let closedByPullRequestsReferences: PullRequestConnection
        let projectItems: ProjectItemConnection
    }

    struct IssueReferenceConnection: Decodable, Sendable {
        let nodes: [IssueReference]
    }

    struct PullRequestConnection: Decodable, Sendable {
        let nodes: [PullRequestNode]
    }

    struct PullRequestNode: Decodable, Sendable {
        let number: Int
        let title: String
        let url: URL
        let state: String
    }

    struct ProjectItemConnection: Decodable, Sendable {
        let nodes: [ProjectItemNode]
    }

    struct ProjectItemNode: Decodable, Sendable {
        let id: String
        let project: IssueProjectOption
        let fieldValues: FieldValueConnection
    }

    struct FieldValueConnection: Decodable, Sendable {
        let nodes: [FieldValueNode]
    }

    struct FieldValueNode: Decodable, Sendable {
        let name: String?
        let optionId: String?
        let field: FieldNode?
    }

    struct FieldNode: Decodable, Sendable {
        let id: String
        let name: String
    }
}

private struct IssueTypesEnvelope: Decodable, Sendable {
    let data: DataNode

    struct DataNode: Decodable, Sendable {
        let organization: OrganizationNode?
    }

    struct OrganizationNode: Decodable, Sendable {
        let issueTypes: IssueTypesNode
    }

    struct IssueTypesNode: Decodable, Sendable {
        let nodes: [IssueTypeOption]
    }
}

private struct IssueProjectsEnvelope: Decodable, Sendable {
    let projects: [IssueProjectOption]
}

private struct IssueProjectFieldsEnvelope: Decodable, Sendable {
    let fields: [Field]

    struct Field: Decodable, Sendable {
        let id: String
        let name: String
        let options: [IssueProjectFieldOption]?
    }
}

private struct IssueReferenceEnvelope: Decodable, Sendable {
    let data: DataNode

    struct DataNode: Decodable, Sendable {
        let repository: RepositoryNode
    }

    struct RepositoryNode: Decodable, Sendable {
        let issue: IssueReference?
    }
}

private enum IssueDate {
    private static let formatter = ISO8601DateFormatter()

    static func parse(_ value: String) -> Date {
        formatter.date(from: value) ?? .distantPast
    }

    static func relative(_ value: String) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: parse(value), relativeTo: Date())
    }
}

private enum IssueError: LocalizedError {
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
