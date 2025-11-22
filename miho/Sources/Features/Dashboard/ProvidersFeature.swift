@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct ProvidersFeature: @preconcurrency Reducer {
  @ObservableState
  struct State {
    struct Alerts: Equatable {
      var errorMessage: String?
    }

    var selectedSegment: Int = 0
    var proxyProviders: [String: ProxyProviderInfo] = [:]
    var ruleProviders: [String: RuleProviderInfo] = [:]
    var refreshingProxyProviders: Set<String> = []
    var healthCheckingProxyProviders: Set<String> = []
    var refreshingRuleProviders: Set<String> = []
    var alerts: Alerts = .init()
  }

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case selectSegment(Int)
    case refreshProxy(String)
    case healthCheckProxy(String)
    case refreshRule(String)
    case mihomoSnapshotUpdated(MihomoSnapshot)
    case refreshProxyFinished(name: String, error: String?)
    case healthCheckProxyFinished(name: String, error: String?)
    case refreshRuleFinished(name: String, error: String?)
    case dismissError
  }

  private enum CancelID {
    case mihomoStream
  }

  @Dependency(\.mihomoService)
  var mihomoService

  init() { }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        return onAppearEffect()

      case .onDisappear:
        return .cancel(id: CancelID.mihomoStream)

      case let .mihomoSnapshotUpdated(snapshot):
        state.proxyProviders = snapshot.proxyProviders
        state.ruleProviders = snapshot.ruleProviders
        return .none

      case let .selectSegment(index):
        state.selectedSegment = index
        return .none

      case let .refreshProxy(name):
        return refreshProxyEffect(state: &state, name: name)

      case let .healthCheckProxy(name):
        return healthCheckProxyEffect(state: &state, name: name)

      case let .refreshRule(name):
        return refreshRuleEffect(state: &state, name: name)

      case let .refreshProxyFinished(name, error):
        state.refreshingProxyProviders.remove(name)
        if let error {
          state.alerts.errorMessage = error
        }
        return .none

      case let .healthCheckProxyFinished(name, error):
        state.healthCheckingProxyProviders.remove(name)
        if let error {
          state.alerts.errorMessage = error
        }
        return .none

      case let .refreshRuleFinished(name, error):
        state.refreshingRuleProviders.remove(name)
        if let error {
          state.alerts.errorMessage = error
        }
        return .none

      case .dismissError:
        state.alerts.errorMessage = nil
        return .none
      }
    }
  }

  private func onAppearEffect() -> Effect<Action> {
    let service = mihomoService
    return .run { @MainActor send in
      service.requestDashboardRefresh()
      for await domainState in service.statePublisher.values {
        let snapshot = MihomoSnapshot(domainState)
        send(.mihomoSnapshotUpdated(snapshot))
      }
    }
    .cancellable(id: CancelID.mihomoStream, cancelInFlight: true)
  }

  private func refreshProxyEffect(
    state: inout State,
    name: String,
  ) -> Effect<Action> {
    guard !state.refreshingProxyProviders.contains(name) else {
      return .none
    }
    state.refreshingProxyProviders.insert(name)

    let service = mihomoService
    return .run { @MainActor send in
      do {
        try await service.updateProxyProvider(name: name)
        send(.refreshProxyFinished(name: name, error: nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.refreshProxyFinished(name: name, error: message))
      }
    }
  }

  private func healthCheckProxyEffect(
    state: inout State,
    name: String,
  ) -> Effect<Action> {
    guard !state.healthCheckingProxyProviders.contains(name) else {
      return .none
    }
    state.healthCheckingProxyProviders.insert(name)

    let service = mihomoService
    return .run { @MainActor send in
      do {
        try await service.healthCheckProxyProvider(name: name)
        send(.healthCheckProxyFinished(name: name, error: nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.healthCheckProxyFinished(name: name, error: message))
      }
    }
  }

  private func refreshRuleEffect(
    state: inout State,
    name: String,
  ) -> Effect<Action> {
    guard !state.refreshingRuleProviders.contains(name) else {
      return .none
    }
    state.refreshingRuleProviders.insert(name)

    let service = mihomoService
    return .run { @MainActor send in
      do {
        try await service.updateRuleProvider(name: name)
        send(.refreshRuleFinished(name: name, error: nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.refreshRuleFinished(name: name, error: message))
      }
    }
  }
}
