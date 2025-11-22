@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct ConnectionsFeature: @preconcurrency Reducer {
  @ObservableState
  struct State {
    struct Alerts: Equatable {
      var errorMessage: String?
    }

    var connections: [ConnectionSnapshot.Connection] = []
    var searchText: String = ""
    var selectedFilter: ConnectionFilter = .all
    var closingConnections: Set<String> = []
    var isClosingAll: Bool = false
    var alerts: Alerts = .init()
  }

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case updateSearch(String)
    case selectFilter(ConnectionFilter)
    case closeConnection(String)
    case closeAll
    case mihomoSnapshotUpdated(MihomoSnapshot)
    case closeConnectionFinished(id: String, error: String?)
    case closeAllFinished(error: String?)
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
        state.connections = snapshot.connections
        return .none

      case let .updateSearch(text):
        if state.searchText != text {
          state.searchText = text
        }
        return .none

      case let .selectFilter(filter):
        if state.selectedFilter != filter {
          state.selectedFilter = filter
        }
        return .none

      case let .closeConnection(id):
        return closeConnectionEffect(state: &state, id: id)

      case .closeAll:
        return closeAllEffect(state: &state)

      case let .closeConnectionFinished(id, error):
        state.closingConnections.remove(id)
        if let error {
          state.alerts.errorMessage = error
        }
        return .none

      case let .closeAllFinished(error):
        state.isClosingAll = false
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

  private func closeConnectionEffect(
    state: inout State,
    id: String,
  ) -> Effect<Action> {
    guard !state.closingConnections.contains(id) else {
      return .none
    }
    state.closingConnections.insert(id)

    let service = mihomoService
    return .run { @MainActor send in
      do {
        try await service.closeConnection(id: id)
        send(.closeConnectionFinished(id: id, error: nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.closeConnectionFinished(id: id, error: message))
      }
    }
  }

  private func closeAllEffect(state: inout State) -> Effect<Action> {
    guard !state.isClosingAll else {
      return .none
    }
    state.isClosingAll = true

    let service = mihomoService
    return .run { @MainActor send in
      do {
        try await service.closeAllConnections()
        send(.closeAllFinished(error: nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.closeAllFinished(error: message))
      }
    }
  }
}
