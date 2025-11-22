import Combine
import Foundation

@MainActor
protocol MihomoService {
  var statePublisher: AnyPublisher<MihomoDomain.State, Never> { get }
  func connect()
  func disconnect()
  func currentState() -> MihomoDomain.State
  func requestDashboardRefresh()
  func selectProxy(group: String, proxy: String) async throws
  func closeConnection(id: String) async throws
  func closeAllConnections() async throws
  func testGroupDelay(name: String) async throws
  func startLogStream(level: String?)
  func stopLogStream()
  func clearLogs()
  func reloadConfig(path: String, payload: String) async throws
  func queryDNS(name: String, type: String) async throws -> DNSQueryResponse
  func updateProxyProvider(name: String) async throws
  func healthCheckProxyProvider(name: String) async throws
  func updateRuleProvider(name: String) async throws
}

@MainActor
struct APIDomainMihomoServiceAdapter: MihomoService {
  private let domain: MihomoDomain

  init(domain: MihomoDomain = .shared) {
    self.domain = domain
  }

  var statePublisher: AnyPublisher<MihomoDomain.State, Never> {
    domain.statePublisher()
  }

  func connect() {
    domain.connect()
  }

  func disconnect() {
    domain.disconnect()
  }

  func currentState() -> MihomoDomain.State {
    domain.currentState()
  }

  func requestDashboardRefresh() {
    domain.requestDashboardRefresh()
  }

  func selectProxy(group: String, proxy: String) async throws {
    try await domain.selectProxy(group: group, proxy: proxy)
  }

  func closeConnection(id: String) async throws {
    try await domain.closeConnection(id: id)
  }

  func closeAllConnections() async throws {
    try await domain.closeAllConnections()
  }

  func testGroupDelay(name: String) async throws {
    _ = try await domain.testGroupDelay(name: name)
  }

  func startLogStream(level: String?) {
    domain.startLogStream(level: level)
  }

  func stopLogStream() {
    domain.stopLogStream()
  }

  func clearLogs() {
    domain.clearLogs()
  }

  func reloadConfig(path: String, payload: String) async throws {
    try await domain.reloadConfig(path: path, payload: payload)
  }

  func queryDNS(name: String, type: String) async throws -> DNSQueryResponse {
    try await domain.queryDNS(name: name, type: type)
  }

  func updateProxyProvider(name: String) async throws {
    try await domain.updateProxyProvider(name: name)
  }

  func healthCheckProxyProvider(name: String) async throws {
    try await domain.healthCheckProxyProvider(name: name)
  }

  func updateRuleProvider(name: String) async throws {
    try await domain.updateRuleProvider(name: name)
  }
}
