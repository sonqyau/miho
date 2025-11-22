import ComposableArchitecture
import Perception
import SwiftUI

struct ProvidersView: View {
  let store: StoreOf<ProvidersFeature>
  @Bindable private var bindableStore: StoreOf<ProvidersFeature>

  init(store: StoreOf<ProvidersFeature>) {
    self.store = store
    _bindableStore = Bindable(wrappedValue: store)
  }

  var body: some View {
    Form {
      providerTypeSection

      if bindableStore.selectedSegment == 0 {
        proxyProvidersSection
      } else {
        ruleProvidersSection
      }
    }
    .formStyle(.grouped)
    .scrollContentBackground(.hidden)
    .navigationTitle("Provider directory")
    .task { bindableStore.send(.onAppear) }
    .onDisappear { bindableStore.send(.onDisappear) }
    .alert(
      "Error",
      isPresented: Binding(
        get: { bindableStore.alerts.errorMessage != nil },
        set: { presented in if !presented { bindableStore.send(.dismissError) } },
      ),
    ) {
      Button("OK") { bindableStore.send(.dismissError) }
    } message: {
      if let message = bindableStore.alerts.errorMessage {
        Text(message)
      }
    }
  }

  private var proxyProviders: [(String, ProxyProviderInfo)] {
    bindableStore.proxyProviders.sorted { $0.key < $1.key }
  }

  private var ruleProviders: [(String, RuleProviderInfo)] {
    bindableStore.ruleProviders.sorted { $0.key < $1.key }
  }

  private var providerTypeSection: some View {
    Section {
      Picker("Provider type", selection: Binding(
        get: { bindableStore.selectedSegment },
        set: { bindableStore.send(.selectSegment($0)) },
      )) {
        Text("Proxy Providers").tag(0)
        Text("Rule Providers").tag(1)
      }
      .pickerStyle(.segmented)
    } header: {
      Label("Source", systemImage: "switch.2")
    }
  }

  private var proxyProvidersSection: some View {
    Section {
      if proxyProviders.isEmpty {
        ContentUnavailableView(
          "No proxy providers",
          systemImage: "externaldrive.fill",
          description: Text("No proxy providers are configured."),
        )
        .frame(maxWidth: .infinity, minHeight: 120)
      } else {
        ForEach(proxyProviders, id: \.0) { name, provider in
          ProxyProviderCard(
            name: name,
            provider: provider,
            isRefreshing: bindableStore.refreshingProxyProviders.contains(name),
            isHealthChecking: bindableStore.healthCheckingProxyProviders.contains(name),
            onRefresh: { bindableStore.send(.refreshProxy(name)) },
            onHealthCheck: { bindableStore.send(.healthCheckProxy(name)) },
          )
        }
      }
    } header: {
      Label("Proxy providers", systemImage: "externaldrive")
    }
  }

  private var ruleProvidersSection: some View {
    Section {
      if ruleProviders.isEmpty {
        ContentUnavailableView(
          "No rule providers",
          systemImage: "list.bullet.rectangle",
          description: Text("No rule providers are configured."),
        )
        .frame(maxWidth: .infinity, minHeight: 120)
      } else {
        ForEach(ruleProviders, id: \.0) { name, provider in
          RuleProviderCard(
            name: name,
            provider: provider,
            isRefreshing: bindableStore.refreshingRuleProviders.contains(name),
            onRefresh: { bindableStore.send(.refreshRule(name)) },
          )
        }
      }
    } header: {
      Label("Rule providers", systemImage: "list.bullet")
    }
  }
}

private struct ProxyProviderCard: View {
  let name: String
  let provider: ProxyProviderInfo
  let isRefreshing: Bool
  let isHealthChecking: Bool
  let onRefresh: () -> Void
  let onHealthCheck: () -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading) {
        HStack {
          VStack(alignment: .leading) {
            Text(name)
              .font(.headline)
            Text(provider.type.uppercased())
              .font(.caption)
            Text(provider.vehicleType)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Button("Run health check") {
            onHealthCheck()
          }
          .disabled(isHealthChecking)

          Button("Refresh Provider") {
            onRefresh()
          }
          .disabled(isRefreshing)
        }

        HStack {
          Label("\(provider.proxies.count) proxies", systemImage: "number")
            .font(.caption)
            .foregroundStyle(.secondary)

          if let updated = provider.updatedAt {
            Label(updated.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

private struct RuleProviderCard: View {
  let name: String
  let provider: RuleProviderInfo
  let isRefreshing: Bool
  let onRefresh: () -> Void

  var body: some View {
    GroupBox {
      VStack(alignment: .leading) {
        HStack {
          VStack(alignment: .leading) {
            Text(name)
              .font(.headline)
            Text(provider.behavior.uppercased())
              .font(.caption)
            Text(provider.vehicleType)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer()

          if isRefreshing {
            ProgressView()
              .controlSize(.small)
          } else {
            Button("Refresh Provider") {
              onRefresh()
            }
          }
        }

        HStack {
          Label("\(provider.ruleCount) rules", systemImage: "number")
            .font(.caption)
            .foregroundStyle(.secondary)

          if let updated = provider.updatedAt {
            Label(updated.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}
