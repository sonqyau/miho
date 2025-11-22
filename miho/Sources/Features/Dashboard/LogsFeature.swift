@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct LogsFeature: @preconcurrency Reducer {
  @ObservableState
  struct State {
    struct Alerts: Equatable {
      var errorMessage: String?
    }

    struct Summary: Equatable {
      var totalLogs: Int = 0
      var filteredLogs: Int = 0
    }

    var logs: [LogMessage] = []
    var selectedLevel: String = "info"
    var searchText: String = ""
    var isStreaming: Bool = false
    var autoScroll: Bool = true
    var filteredLogs: [LogMessage] = []
    var summary: Summary = .init()
    var alerts: Alerts = .init()
  }

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case selectLevel(String)
    case updateSearch(String)
    case toggleAutoScroll(Bool)
    case toggleStreaming
    case clearLogs
    case mihomoSnapshotUpdated(MihomoSnapshot)
    case dismissError
  }

  private enum CancelID {
    case mihomoStream
  }

  @Dependency(\.mihomoService)
  var mihomoService

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        return onAppearEffect()

      case .onDisappear:
        let wasStreaming = state.isStreaming
        state.isStreaming = false
        return onDisappearEffect(wasStreaming: wasStreaming)

      case let .mihomoSnapshotUpdated(snapshot):
        state.logs = snapshot.logs
        refreshLogsDerivedState(state: &state)
        return .none

      case let .selectLevel(level):
        guard state.selectedLevel != level else {
          return .none
        }
        state.selectedLevel = level

        guard state.isStreaming else {
          return .none
        }
        return restartLogStream(level: level)

      case let .updateSearch(text):
        if state.searchText != text {
          state.searchText = text
          refreshLogsDerivedState(state: &state)
        }
        return .none

      case let .toggleAutoScroll(flag):
        state.autoScroll = flag
        return .none

      case .toggleStreaming:
        state.isStreaming.toggle()
        let level = state.selectedLevel
        return toggleStreamingEffect(isStreaming: state.isStreaming, level: level)

      case .clearLogs:
        state.logs.removeAll()
        refreshLogsDerivedState(state: &state)
        return clearLogsEffect()

      case .dismissError:
        state.alerts.errorMessage = nil
        return .none
      }
    }
  }

  init() { }

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

  private func onDisappearEffect(wasStreaming: Bool) -> Effect<Action> {
    .merge(
      .cancel(id: CancelID.mihomoStream),
      wasStreaming
        ? .run { @MainActor _ in
          mihomoService.stopLogStream()
        }
        : .none,
    )
  }

  private func restartLogStream(level: String) -> Effect<Action> {
    .run { @MainActor _ in
      mihomoService.stopLogStream()
      mihomoService.startLogStream(level: level)
    }
  }

  private func toggleStreamingEffect(isStreaming: Bool, level: String) -> Effect<Action> {
    if isStreaming {
      .run { @MainActor _ in
        mihomoService.startLogStream(level: level)
      }
    } else {
      .run { @MainActor _ in
        mihomoService.stopLogStream()
      }
    }
  }

  private func clearLogsEffect() -> Effect<Action> {
    .run { @MainActor _ in
      mihomoService.clearLogs()
    }
  }

  private func refreshLogsDerivedState(state: inout State) {
    let search = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if search.isEmpty {
      state.filteredLogs = state.logs
    } else {
      state.filteredLogs = state.logs.filter { message in
        message.payload.localizedCaseInsensitiveContains(search)
      }
    }
    state.summary = .init(
      totalLogs: state.logs.count,
      filteredLogs: search.isEmpty ? 0 : state.filteredLogs.count,
    )
  }
}
