@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct PersistenceFeature: @preconcurrency Reducer {
  @ObservableState
  struct State {
    struct Alerts: Equatable {
      var errorMessage: String?
    }

    var configs: [PersistenceModel] = []
    var remoteInstances: [RemoteInstance] = []
    var isLocalMode: Bool = true
    var activeRemoteInstance: RemoteInstance?
    var isUpdatingAll: Bool = false
    var showingAddConfig: Bool = false
    var showingAddInstance: Bool = false
    var alerts: Alerts = .init()
  }

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case refreshAll
    case activateConfig(PersistenceModel)
    case updateConfig(PersistenceModel)
    case deleteConfig(PersistenceModel)
    case showAddConfig(Bool)
    case showAddInstance(Bool)
    case activateInstance(RemoteInstance?)
    case deleteInstance(RemoteInstance)
    case domainStateUpdated(PersistenceDomain.State)
    case operationFinished(String?)
    case dismissError
  }

  private enum CancelID {
    case domainStream
  }

  @Dependency(\.persistenceService)
  var persistenceService

  init() { }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        return onAppearEffect()

      case .onDisappear:
        return .cancel(id: CancelID.domainStream)

      case let .domainStateUpdated(domainState):
        state.configs = domainState.configs
        state.remoteInstances = domainState.remoteInstances
        state.isLocalMode = domainState.isLocalMode
        state.activeRemoteInstance = domainState.activeRemoteInstance
        return .none

      case .refreshAll:
        return refreshAllEffect(state: &state)

      case let .activateConfig(config):
        return activateConfigEffect(config: config)

      case let .updateConfig(config):
        return updateConfigEffect(config: config)

      case let .deleteConfig(config):
        return deleteConfigEffect(config: config)

      case let .activateInstance(instance):
        return activateInstanceEffect(instance: instance)

      case let .deleteInstance(instance):
        return deleteInstanceEffect(instance: instance)

      case let .showAddConfig(flag):
        state.showingAddConfig = flag
        return .none

      case let .showAddInstance(flag):
        state.showingAddInstance = flag
        return .none

      case let .operationFinished(error):
        state.isUpdatingAll = false
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
    let service = persistenceService
    return .run { @MainActor send in
      for await domainState in service.statePublisher.values {
        send(.domainStateUpdated(domainState))
      }
    }
    .cancellable(id: CancelID.domainStream, cancelInFlight: true)
  }

  private func refreshAllEffect(state: inout State) -> Effect<Action> {
    guard !state.isUpdatingAll else {
      return .none
    }
    state.isUpdatingAll = true
    let service = persistenceService
    return .run { @MainActor send in
      await service.updateAllConfigs()
      send(.operationFinished(nil))
    }
  }

  private func activateConfigEffect(config: PersistenceModel) -> Effect<Action> {
    let service = persistenceService
    return .run { @MainActor send in
      do {
        try await service.activateConfig(config)
        send(.operationFinished(nil))
      } catch {
        send(.operationFinished(Self.describe(error)))
      }
    }
  }

  private func updateConfigEffect(config: PersistenceModel) -> Effect<Action> {
    let service = persistenceService
    return .run { @MainActor send in
      do {
        try await service.updateConfig(config)
        send(.operationFinished(nil))
      } catch {
        send(.operationFinished(Self.describe(error)))
      }
    }
  }

  private func deleteConfigEffect(config: PersistenceModel) -> Effect<Action> {
    let service = persistenceService
    return .run { @MainActor send in
      do {
        try service.removeConfig(config)
        send(.operationFinished(nil))
      } catch {
        send(.operationFinished(Self.describe(error)))
      }
    }
  }

  private func activateInstanceEffect(instance: RemoteInstance?) -> Effect<Action> {
    let service = persistenceService
    return .run { @MainActor send in
      service.activateRemoteInstance(instance)
      send(.operationFinished(nil))
    }
  }

  private func deleteInstanceEffect(instance: RemoteInstance) -> Effect<Action> {
    let service = persistenceService
    return .run { @MainActor send in
      do {
        try service.removeRemoteInstance(instance)
        send(.operationFinished(nil))
      } catch {
        send(.operationFinished(Self.describe(error)))
      }
    }
  }

  private static func describe(_ error: any Error) -> String {
    let miho = MihoError(error: error)
    let prefix = "[\(miho.category.displayName)] "

    if let remote = error as? PersistenceError {
      switch remote {
      case .notInitialized:
        return prefix + "Persistence is not initialized. Please restart the app and try again."

      case .invalidURL:
        return prefix + "The URL you entered is not valid. Please check the format and try again."

      case .duplicateURL:
        return prefix + "A config with this URL already exists. Please use a different URL."

      case .downloadFailed:
        return prefix + "Failed to download the config. Please check your network connection and try again."

      case .invalidEncoding:
        return prefix + "The downloaded config file has invalid encoding. Please verify the source or try another URL."

      case let .validationFailed(reason):
        return prefix + reason

      case let .secretStorageFailed(reason):
        return prefix + reason
      }
    }

    if let suggestion = miho.recoverySuggestion {
      return prefix + suggestion
    }

    return prefix + miho.message
  }
}
