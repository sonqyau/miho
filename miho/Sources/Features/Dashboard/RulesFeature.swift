@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct RulesFeature: @preconcurrency Reducer {
  @ObservableState
  struct State {
    struct RuleStatistic: Identifiable {
      var rule: String
      var count: Int
      var totalDownload: Int64
      var totalUpload: Int64
      var connections: [ConnectionSnapshot.Connection]

      var id: String { rule }
    }

    struct Alerts: Equatable {
      var errorMessage: String?
    }

    struct Summary: Equatable {
      var activeRules: Int = 0
      var totalConnections: Int = 0
      var filteredRules: Int = 0
    }

    var rules: [RuleStatistic] = []
    var searchText: String = ""
    var isSearchFocused: Bool = false
    var summary: Summary = .init()
    var alerts: Alerts = .init()

    var allConnections: [ConnectionSnapshot.Connection] = []
  }

  @Dependency(\.mihomoService)
  var mihomoService

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case updateSearch(String)
    case setSearchFocus(Bool)
    case mihomoSnapshotUpdated(MihomoSnapshot)
    case dismissError
  }

  private enum CancelID {
    case mihomoStream
  }

  init() { }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        let service = mihomoService
        return .run { @MainActor send in
          service.requestDashboardRefresh()
          for await domainState in service.statePublisher.values {
            let snapshot = MihomoSnapshot(domainState)
            send(.mihomoSnapshotUpdated(snapshot))
          }
        }
        .cancellable(id: CancelID.mihomoStream, cancelInFlight: true)

      case .onDisappear:
        return .cancel(id: CancelID.mihomoStream)

      case let .mihomoSnapshotUpdated(snapshot):
        state.allConnections = snapshot.connections
        rebuildRuleStatistics(state: &state)
        return .none

      case let .updateSearch(text):
        if state.searchText != text {
          state.searchText = text
          rebuildRuleStatistics(state: &state)
        }
        return .none

      case let .setSearchFocus(isFocused):
        state.isSearchFocused = isFocused
        return .none

      case .dismissError:
        state.alerts.errorMessage = nil
        return .none
      }
    }
  }

  private func rebuildRuleStatistics(state: inout State) {
    let connections = state.allConnections

    var stats: [String: State.RuleStatistic] = [:]

    for connection in connections {
      let ruleKey = connection.ruleString
      if var stat = stats[ruleKey] {
        stat.count += 1
        stat.totalDownload += connection.download
        stat.totalUpload += connection.upload
        stat.connections.append(connection)
        stats[ruleKey] = stat
      } else {
        stats[ruleKey] = .init(
          rule: ruleKey,
          count: 1,
          totalDownload: connection.download,
          totalUpload: connection.upload,
          connections: [connection],
        )
      }
    }

    var results = Array(stats.values).sorted { lhs, rhs in
      if lhs.count == rhs.count {
        return lhs.rule < rhs.rule
      }
      return lhs.count > rhs.count
    }

    let search = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !search.isEmpty {
      results = results.filter { $0.rule.localizedCaseInsensitiveContains(search) }
    }

    state.rules = results
    state.summary = .init(
      activeRules: results.count,
      totalConnections: results.reduce(into: 0) { $0 += $1.count },
      filteredRules: search.isEmpty ? 0 : results.count,
    )
  }
}
