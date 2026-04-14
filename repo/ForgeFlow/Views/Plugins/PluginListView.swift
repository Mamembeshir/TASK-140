import SwiftUI

struct PluginListView: View {
    let pluginService: PluginService
    let postingService: PostingService
    @Environment(AppState.self) private var appState
    @State private var vm: PluginListViewModel?
    @State private var showingCreate = false
    @State private var newName = ""
    @State private var newDescription = ""
    @State private var newCategory = ""

    var body: some View {
        Group {
            if let vm {
                List {
                    ForEach(vm.plugins) { plugin in
                        NavigationLink {
                            pluginDetail(for: plugin)
                        } label: {
                            pluginRow(plugin)
                        }
                    }
                }
                .overlay {
                    if vm.plugins.isEmpty && !vm.isLoading {
                        EmptyStateView(
                            icon: "puzzlepiece.extension",
                            heading: "No Plugins",
                            description: "Create your first plugin to extend ForgeFlow."
                        )
                    }
                }
                .refreshable { await vm.load() }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Plugins")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingCreate = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create Plugin")
            }
        }
        .alert("New Plugin", isPresented: $showingCreate) {
            TextField("Name", text: $newName)
            TextField("Description", text: $newDescription)
            TextField("Category", text: $newCategory)
            Button("Create") {
                Task {
                    await vm?.createPlugin(name: newName, description: newDescription, category: newCategory)
                    newName = ""; newDescription = ""; newCategory = ""
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            let viewModel = PluginListViewModel(pluginService: pluginService, appState: appState)
            vm = viewModel
            await viewModel.load()
        }
    }

    private func pluginRow(_ plugin: PluginDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(plugin.name)
                    .font(.headline)
                Spacer()
                statusBadge(plugin.status)
            }
            Text(plugin.category)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(plugin.description)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func statusBadge(_ status: PluginStatus) -> some View {
        Text(status.rawValue.replacingOccurrences(of: "_", with: " "))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundStyle(statusColor(status))
            .clipShape(Capsule())
    }

    private func statusColor(_ status: PluginStatus) -> Color {
        switch status {
        case .draft: return .gray
        case .testing: return .orange
        case .pendingApproval: return .yellow
        case .approved: return .blue
        case .rejected: return .red
        case .active: return .green
        }
    }

    @ViewBuilder
    private func pluginDetail(for plugin: PluginDefinition) -> some View {
        switch plugin.status {
        case .draft, .testing:
            PluginEditorView(pluginId: plugin.id, pluginService: pluginService, postingService: postingService)
        case .pendingApproval:
            PluginApprovalView(pluginId: plugin.id, pluginService: pluginService)
        default:
            PluginApprovalView(pluginId: plugin.id, pluginService: pluginService)
        }
    }
}
