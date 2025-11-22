import Combine
import Foundation

@MainActor
protocol ProxyService {
  var statePublisher: AnyPublisher<ProxyDomain.State, Never> { get }
  func currentState() -> ProxyDomain.State
  func toggleSystemProxy() async throws
  func toggleTunMode() async throws
  func setAllowLAN(_ enabled: Bool) async throws
  func switchMode(_ mode: ProxyMode) async throws
  func reloadConfig() async throws
  func disableSystemProxy() async throws
}

@MainActor
struct ProxyConfigDomainServiceAdapter: ProxyService {
  private let domain: ProxyDomain

  init(domain: ProxyDomain = .shared) {
    self.domain = domain
  }

  var statePublisher: AnyPublisher<ProxyDomain.State, Never> {
    domain.statePublisher()
  }

  func currentState() -> ProxyDomain.State {
    domain.currentState()
  }

  func toggleSystemProxy() async throws {
    try await domain.toggleSystemProxy()
  }

  func toggleTunMode() async throws {
    try await domain.toggleTunMode()
  }

  func setAllowLAN(_ enabled: Bool) async throws {
    try await domain.setAllowLAN(enabled)
  }

  func switchMode(_ mode: ProxyMode) async throws {
    await domain.switchMode(mode)
  }

  func reloadConfig() async throws {
    await domain.reloadConfig()
  }

  func disableSystemProxy() async throws {
    try await domain.disableSystemProxy()
  }
}
