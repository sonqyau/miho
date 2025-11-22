@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct OverviewFeature: @preconcurrency Reducer {
  @ObservableState
  struct State: Equatable {
    struct OverviewSummary: Equatable {
      var downloadSpeed: String = "0 B/s"
      var uploadSpeed: String = "0 B/s"
      var connectionCount: Int = 0
      var version: String = ""
      var memoryUsage: Int64 = 0
    }

    var isConnected: Bool = false
    var overviewSummary: OverviewSummary = .init()
    var trafficHistory: [TrafficPoint] = []
  }

  @Dependency(\.mihomoService)
  var mihomoService

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case mihomoSnapshotUpdated(MihomoSnapshot)
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
          service.connect()
          for await domainState in service.statePublisher.values {
            let snapshot = MihomoSnapshot(domainState)
            send(.mihomoSnapshotUpdated(snapshot))
          }
        }
        .cancellable(id: CancelID.mihomoStream, cancelInFlight: true)

      case .onDisappear:
        return .cancel(id: CancelID.mihomoStream)

      case let .mihomoSnapshotUpdated(snapshot):
        state.isConnected = snapshot.isConnected
        state.overviewSummary = .init(
          downloadSpeed: Self.formatSpeed(snapshot.currentTraffic?.downloadSpeed),
          uploadSpeed: Self.formatSpeed(snapshot.currentTraffic?.uploadSpeed),
          connectionCount: snapshot.connections.count,
          version: snapshot.version,
          memoryUsage: snapshot.memoryUsage,
        )
        state.trafficHistory = snapshot.trafficHistory
        return .none
      }
    }
  }

  private static func formatSpeed(_ value: String?) -> String {
    value ?? "0 B/s"
  }
}
