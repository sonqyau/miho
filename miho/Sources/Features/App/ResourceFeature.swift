import ComposableArchitecture
import Foundation

@MainActor
struct ResourceFeature: @preconcurrency Reducer {
  @ObservableState
  struct State: Equatable {
    var isInitialized: Bool = false
    var lastErrorDescription: String?
  }

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case domainStateUpdated(ResourceSnapshot)
  }

  private enum CancelID {
    case domainStream
  }

  @Dependency(\.resourceService)
  var resourceService

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        let service = resourceService
        return .run { @MainActor send in
          for await snapshot in service.statePublisher.values {
            send(.domainStateUpdated(snapshot))
          }
        }
        .cancellable(id: CancelID.domainStream, cancelInFlight: true)

      case .onDisappear:
        return .cancel(id: CancelID.domainStream)

      case let .domainStateUpdated(snapshot):
        state.isInitialized = snapshot.isInitialized
        state.lastErrorDescription = snapshot.lastErrorDescription
        return .none
      }
    }
  }

  init() { }
}
