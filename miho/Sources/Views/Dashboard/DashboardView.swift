import Charts
import ComposableArchitecture
import Perception
import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
  case overview
  case proxies
  case connections
  case rules
  case providers
  case dns
  case logs

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "Overview"
    case .proxies: "Proxies"
    case .connections: "Connections"
    case .rules: "Rules"
    case .providers: "Providers"
    case .dns: "DNS"
    case .logs: "Logs"
    }
  }

  var icon: String {
    switch self {
    case .overview: "chart.bar.fill"
    case .proxies: "arrow.triangle.branch"
    case .connections: "network"
    case .rules: "list.bullet"
    case .providers: "externaldrive.fill"
    case .dns: "globe"
    case .logs: "doc.text.fill"
    }
  }
}

struct DashboardView: View {
  let store: StoreOf<DashboardFeature>
  @Bindable private var bindableStore: StoreOf<DashboardFeature>

  init(store: StoreOf<DashboardFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  private var selectedTabBinding: Binding<DashboardTab> {
    Binding(
      get: { bindableStore.selectedTab },
      set: { tab in
        guard tab != bindableStore.selectedTab else {
          return
        }
        bindableStore.send(.selectTab(tab))
      },
    )
  }

  var body: some View {
    NavigationSplitView {
      List(DashboardTab.allCases, selection: selectedTabBinding) { tab in
        Label(tab.title, systemImage: tab.icon)
          .tag(tab)
          .symbolEffect(.bounce, value: bindableStore.selectedTab == tab)
      }
      .navigationTitle("Dashboard")
      .frame(minWidth: 200)
    } detail: {
      Group {
        switch bindableStore.selectedTab {
        case .overview:
          OverviewView(store: store.scope(state: \.overview, action: \.overview))

        case .proxies:
          ProxiesView(store: store.scope(state: \.proxies, action: \.proxies))

        case .connections:
          ConnectionsView(store: store.scope(state: \.connections, action: \.connections))

        case .rules:
          RulesView(store: store.scope(state: \.rules, action: \.rules))

        case .providers:
          ProvidersView(store: store.scope(state: \.providers, action: \.providers))

        case .dns:
          DNSView(store: store.scope(state: \.dns, action: \.dns))

        case .logs:
          LogsView(store: store.scope(state: \.logs, action: \.logs))
        }
      }
      .frame(minWidth: 600, minHeight: 400)
    }
    .onAppear { bindableStore.send(.onAppear) }
    .onDisappear { bindableStore.send(.onDisappear) }
  }
}
