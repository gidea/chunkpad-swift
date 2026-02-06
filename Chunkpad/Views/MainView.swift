import SwiftUI

struct MainView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            List(AppState.SidebarTab.allCases, selection: $appState.selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Chunkpad")
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selectedTab {
        case .chat:
            ChatView()
        case .documents:
            DocumentsView()
        case .settings:
            SettingsView()
        }
    }
}
