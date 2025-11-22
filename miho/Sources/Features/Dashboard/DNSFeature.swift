import ComposableArchitecture
import Foundation

@MainActor
struct DNSFeature: @preconcurrency Reducer {
  @ObservableState
  struct State {
    struct Alerts: Equatable {
      var errorMessage: String?
    }

    var domain: String = ""
    var recordType: String = "A"
    var recordTypes: [String] = ["A", "AAAA", "CNAME", "MX", "TXT", "NS"]
    var queryResult: DNSQueryResponse?
    var isQuerying: Bool = false
    var alerts: Alerts = .init()
  }

  @CasePathable
  enum Action {
    case updateDomain(String)
    case selectRecordType(String)
    case performQuery
    case queryFinished(Result<DNSQueryResponse, Error>)
    case dismissError
  }

  @Dependency(\.mihomoService)
  var mihomoService

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .updateDomain(domain):
        state.domain = domain
        return .none

      case let .selectRecordType(type):
        if state.recordType != type {
          state.recordType = type
        }
        return .none

      case .performQuery:
        guard !state.domain.isEmpty, !state.isQuerying else {
          return .none
        }
        state.isQuerying = true
        state.alerts.errorMessage = nil

        let domain = state.domain
        let recordType = state.recordType
        let service = mihomoService

        return .run { @MainActor send in
          do {
            let result = try await service.queryDNS(name: domain, type: recordType)
            send(.queryFinished(.success(result)))
          } catch {
            send(.queryFinished(.failure(error)))
          }
        }

      case let .queryFinished(result):
        state.isQuerying = false
        switch result {
        case let .success(response):
          state.queryResult = response

        case let .failure(error):
          state.alerts.errorMessage = (error as NSError).localizedDescription
          state.queryResult = nil
        }
        return .none

      case .dismissError:
        state.alerts.errorMessage = nil
        return .none
      }
    }
  }

  init() { }
}
