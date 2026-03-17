import SwiftUI

struct ActivityLogView: View {
    let dbManager: DatabaseManager

    @State private var records: [ActivityRecord] = []
    @State private var selectedRecord: ActivityRecord?
    @State private var searchText: String = ""
    @State private var totalCount: Int = 0

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium
        return f
    }()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search apps, windows, URLs...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit { refresh() }
                    if !searchText.isEmpty {
                        Button(action: { searchText = ""; refresh() }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)

                Divider()

                List(records, selection: $selectedRecord) { record in
                    RecordRow(record: record, timeFormatter: timeFormatter)
                        .tag(record)
                }
                .listStyle(.plain)

                Divider()

                HStack {
                    Text("\(records.count) shown / \(totalCount) total")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Refresh") { refresh() }
                        .font(.caption)
                }
                .padding(6)
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            if let record = selectedRecord {
                RecordDetailView(record: record, timeFormatter: timeFormatter)
            } else {
                Text("Select a record")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { refresh() }
    }

    private func refresh() {
        records = dbManager.fetchRecords(limit: 500, searchQuery: searchText)
        totalCount = dbManager.recordCount()
    }
}

// MARK: - Record Row

private struct RecordRow: View {
    let record: ActivityRecord
    let timeFormatter: DateFormatter

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(record.appName)
                    .font(.system(.body, weight: .semibold))
                Spacer()
                Text(timeFormatter.string(from: record.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(record.windowTitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            if !record.focusedRole.isEmpty {
                Text("\(record.focusedRole): \(record.focusedTitle)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if !record.url.isEmpty {
                Text(record.url)
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Record Detail View

private struct RecordDetailView: View {
    let record: ActivityRecord
    let timeFormatter: DateFormatter

    @State private var hierarchyExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                GroupBox("Application") {
                    DetailGrid {
                        DetailRow(label: "App", value: record.appName)
                        DetailRow(label: "Bundle ID", value: record.bundleId)
                        DetailRow(label: "Timestamp", value: timeFormatter.string(from: record.timestamp))
                    }
                }

                GroupBox("Window") {
                    DetailGrid {
                        DetailRow(label: "Title", value: record.windowTitle)
                        DetailRow(label: "Document", value: record.documentPath)
                        DetailRow(label: "URL", value: record.url)
                    }
                }

                GroupBox("Focused Element") {
                    DetailGrid {
                        DetailRow(label: "Role", value: record.focusedRole)
                        DetailRow(label: "Title", value: record.focusedTitle)
                    }
                    if !record.focusedValue.isEmpty {
                        Divider()
                        Text("Value")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(record.focusedValue)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !record.selectedText.isEmpty {
                        Divider()
                        Text("Selected Text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(record.selectedText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !record.windowHierarchy.isEmpty {
                    GroupBox {
                        DisclosureGroup("Window Hierarchy", isExpanded: $hierarchyExpanded) {
                            if let root = parseHierarchy(record.windowHierarchy) {
                                AXNodeTreeView(node: root, depth: 0)
                            } else {
                                Text(record.windowHierarchy)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    private func parseHierarchy(_ json: String) -> AXNode? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AXNode.self, from: data)
    }
}

// MARK: - AX Node Tree View

private struct AXNodeTreeView: View {
    let node: AXNode
    let depth: Int

    @State private var isExpanded = false

    private var label: String {
        var parts = [node.role]
        if !node.title.isEmpty { parts.append("\"\(node.title)\"") }
        else if !node.description.isEmpty { parts.append("\"\(node.description)\"") }
        if !node.subrole.isEmpty { parts.append("(\(node.subrole))") }
        return parts.joined(separator: " ")
    }

    private var hasValue: Bool {
        !node.value.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if node.children.isEmpty && !hasValue {
                Text(label)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.leading, CGFloat(depth * 16))
            } else {
                DisclosureGroup(isExpanded: $isExpanded) {
                    if hasValue {
                        Text("value: \(node.value)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.leading, CGFloat((depth + 1) * 16))
                            .textSelection(.enabled)
                    }
                    ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                        AXNodeTreeView(node: child, depth: depth + 1)
                    }
                } label: {
                    Text(label)
                        .font(.system(.caption, design: .monospaced))
                }
                .padding(.leading, CGFloat(depth * 16))
            }
        }
    }
}

// MARK: - Detail Helpers

private struct DetailGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value.isEmpty ? "—" : value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .gridColumnAlignment(.leading)
        }
    }
}

// MARK: - Identifiable / Hashable conformance for selection

extension ActivityRecord: Hashable {
    static func == (lhs: ActivityRecord, rhs: ActivityRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
