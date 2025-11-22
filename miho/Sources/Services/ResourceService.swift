import Combine
import Foundation

struct ResourceSnapshot: Equatable {
  var isInitialized: Bool
  var lastErrorDescription: String?
}

@MainActor
protocol ResourceService: AnyObject {
  var statePublisher: AnyPublisher<ResourceSnapshot, Never> { get }
  func currentState() -> ResourceSnapshot
  func initialize() async throws
  func ensureDefaultConfig() throws
  var configDirectory: URL { get }
}

@MainActor
final class ResourceDomainServiceAdapter: ResourceService {
  private let domain: ResourceDomain
  private let stateSubject: CurrentValueSubject<ResourceSnapshot, Never>

  init(domain: ResourceDomain = .shared) {
    self.domain = domain
    let snapshot = ResourceSnapshot(
      isInitialized: domain.isInitialized,
      lastErrorDescription: Self.describe(domain.initializationError),
    )
    stateSubject = CurrentValueSubject(snapshot)
  }

  var statePublisher: AnyPublisher<ResourceSnapshot, Never> {
    stateSubject.receive(on: RunLoop.main).eraseToAnyPublisher()
  }

  func currentState() -> ResourceSnapshot {
    stateSubject.value
  }

  func initialize() async throws {
    do {
      try await domain.initialize()
      publish()
    } catch {
      publish()
      throw error
    }
  }

  func ensureDefaultConfig() throws {
    try domain.ensureDefaultConfig()
  }

  var configDirectory: URL {
    domain.configDirectory
  }

  private func publish() {
    let snapshot = ResourceSnapshot(
      isInitialized: domain.isInitialized,
      lastErrorDescription: Self.describe(domain.initializationError),
    )
    stateSubject.send(snapshot)
  }

  private static func describe(_ error: (any Error)?) -> String? {
    guard let error else {
      return nil
    }

    let miho = MihoError(error: error)
    let prefix = "[\(miho.category.displayName)] "

    if let resource = error as? ResourceError {
      if let suggestion = resource.recoverySuggestion {
        return prefix + resource.userFriendlyMessage + "\n\n" + suggestion
      }
      return prefix + resource.userFriendlyMessage
    }

    if let suggestion = miho.recoverySuggestion {
      return prefix + suggestion
    }

    return prefix + miho.message
  }
}
