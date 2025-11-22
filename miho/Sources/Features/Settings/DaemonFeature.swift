@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct DaemonFeature: @preconcurrency Reducer {
  @ObservableState
  struct State: Equatable {
    struct Alerts: Equatable {
      var errorMessage: String?
    }

    var isRegistered: Bool = false
    var requiresApproval: Bool = false
    var isProcessing: Bool = false
    var alerts: Alerts = .init()
  }

  @CasePathable
  enum Action: Equatable {
    case onAppear
    case onDisappear
    case registerHelper
    case unregisterHelper
    case refreshStatus
    case openSystemSettings
    case statusUpdated(DaemonSnapshot)
    case operationFinished(String?)
    case dismissError
  }

  private enum CancelID {
    case domainStream
  }

  @Dependency(\.daemonService)
  var daemonService

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        daemonService.checkStatus()
        return startDomainStream()

      case .onDisappear:
        return .cancel(id: CancelID.domainStream)

      case let .statusUpdated(snapshot):
        state.isRegistered = snapshot.isRegistered
        state.requiresApproval = snapshot.requiresApproval
        return .none

      case .registerHelper:
        guard !state.isProcessing else {
          return .none
        }
        state.isProcessing = true
        state.alerts.errorMessage = nil
        return registerHelperEffect()

      case .unregisterHelper:
        guard !state.isProcessing else {
          return .none
        }
        state.isProcessing = true
        state.alerts.errorMessage = nil
        return unregisterHelperEffect()

      case .refreshStatus:
        daemonService.checkStatus()
        return .none

      case .openSystemSettings:
        daemonService.openSystemSettings()
        return .none

      case let .operationFinished(error):
        state.isProcessing = false
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

  init() { }

  private static func describe(_ error: any Error) -> String {
    let miho = MihoError(error: error)
    let prefix = "[\(miho.category.displayName)] "

    if let daemon = error as? DaemonError {
      switch daemon {
      case .notRegistered:
        return prefix + "Helper tool is not installed. Select Install Helper and try again."

      case .requiresApproval:
        return prefix + "In System Settings, go to Privacy & Security > Developer Tools and allow access for \"miho\"."

      case .notFound:
        return prefix + "Unable to locate the helper tool. Reinstall it from Settings and try again."

      case .connectionFailed:
        return prefix + "Failed to communicate with the helper tool. Restart it from Settings and try again."

      case let .registrationFailed(underlying),
           let .unregistrationFailed(underlying):
        return prefix + "\(daemon.userFriendlyMessage) (Reason: \(underlying.mihoMessage))"
      }
    }

    if let suggestion = miho.recoverySuggestion {
      return prefix + suggestion
    }

    return prefix + miho.message
  }

  private func startDomainStream() -> Effect<Action> {
    let daemonContainer = DaemonServiceDependency(service: daemonService)
    return .run { @MainActor send in
      for await domainState in daemonContainer.service.statePublisher.values {
        let snapshot = DaemonSnapshot(domainState)
        send(.statusUpdated(snapshot))
      }
    }
    .cancellable(id: CancelID.domainStream, cancelInFlight: true)
  }

  private func registerHelperEffect() -> Effect<Action> {
    let daemonContainer = DaemonServiceDependency(service: daemonService)
    return .run { @MainActor send in
      do {
        try await daemonContainer.service.register()
        send(.operationFinished(nil))
      } catch {
        send(.operationFinished(Self.describe(error)))
      }
    }
  }

  private func unregisterHelperEffect() -> Effect<Action> {
    let daemonContainer = DaemonServiceDependency(service: daemonService)
    return .run { @MainActor send in
      do {
        try await daemonContainer.service.unregister()
        send(.operationFinished(nil))
      } catch {
        send(.operationFinished(Self.describe(error)))
      }
    }
  }
}
