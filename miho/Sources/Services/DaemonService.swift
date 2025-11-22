import Combine
import Foundation

@MainActor
protocol DaemonService {
  var statePublisher: AnyPublisher<DaemonDomain.State, Never> { get }
  func currentState() -> DaemonDomain.State
  func register() async throws(DaemonError)
  func unregister() async throws(DaemonError)
  func checkStatus()
  func openSystemSettings()
  func flushDNSCache() async throws
}

@MainActor
struct DaemonDomainServiceAdapter: DaemonService {
  private let domain: DaemonDomain

  init(domain: DaemonDomain = .shared) {
    self.domain = domain
  }

  var statePublisher: AnyPublisher<DaemonDomain.State, Never> {
    domain.statePublisher()
  }

  func currentState() -> DaemonDomain.State {
    domain.state
  }

  func register() async throws(DaemonError) {
    try await domain.register()
  }

  func unregister() async throws(DaemonError) {
    try await domain.unregister()
  }

  func checkStatus() {
    domain.checkStatus()
  }

  func openSystemSettings() {
    domain.openSystemSettings()
  }

  func flushDNSCache() async throws {
    try await domain.flushDnsCache()
  }
}
