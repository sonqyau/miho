@preconcurrency import Combine
import ErrorKit
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class MihomoDomain {
  struct State {
    var trafficHistory: [TrafficPoint]
    var currentTraffic: TrafficSnapshot?
    var connections: [ConnectionSnapshot.Connection]
    var memoryUsage: Int64
    var version: String
    var logs: [LogMessage]
    var proxies: [String: ProxyInfo]
    var groups: [String: GroupInfo]
    var rules: [RuleInfo]
    var proxyProviders: [String: ProxyProviderInfo]
    var ruleProviders: [String: RuleProviderInfo]
    var config: ClashConfig?
    var isConnected: Bool
  }

  static let shared = MihomoDomain()

  private let logger = MihoLog.shared.logger(for: .api)

  private let stateSubject: CurrentValueSubject<State, Never>

  private(set) var trafficHistory: [TrafficPoint] = [] {
    didSet { emitState() }
  }

  private(set) var currentTraffic: TrafficSnapshot? {
    didSet { emitState() }
  }

  private(set) var connections: [ConnectionSnapshot.Connection] = [] {
    didSet { emitState() }
  }

  private(set) var memoryUsage: Int64 = 0 {
    didSet { emitState() }
  }

  private(set) var version: String = "" {
    didSet { emitState() }
  }

  private(set) var logs: [LogMessage] = [] {
    didSet { emitState() }
  }

  private(set) var proxies: [String: ProxyInfo] = [:] {
    didSet { emitState() }
  }

  private(set) var groups: [String: GroupInfo] = [:] {
    didSet { emitState() }
  }

  private(set) var rules: [RuleInfo] = [] {
    didSet { emitState() }
  }

  private(set) var proxyProviders: [String: ProxyProviderInfo] = [:] {
    didSet { emitState() }
  }

  private(set) var ruleProviders: [String: RuleProviderInfo] = [:] {
    didSet { emitState() }
  }

  private(set) var config: ClashConfig? {
    didSet { emitState() }
  }

  private(set) var isConnected = false {
    didSet { emitState() }
  }

  private var trafficTask: URLSessionWebSocketTask?
  private var memoryTask: URLSessionWebSocketTask?
  private var logTask: URLSessionWebSocketTask?
  private var connectionTask: Task<Void, Never>?
  private var dataRefreshTask: Task<Void, Never>?

  private var baseURL: String
  private var secret: String?
  private static let maxTrafficPoints = 120
  private static let maxLogEntries = 500

  private init() {
    stateSubject = CurrentValueSubject(
      State(
        trafficHistory: [],
        currentTraffic: nil,
        connections: [],
        memoryUsage: 0,
        version: "",
        logs: [],
        proxies: [:],
        groups: [:],
        rules: [],
        proxyProviders: [:],
        ruleProviders: [:],
        config: nil,
        isConnected: false,
      ),
    )
    baseURL = "http://127.0.0.1:9090"
    secret = nil
  }

  nonisolated func configure(baseURL: String, secret: String?) {
    Task { @MainActor in
      self.baseURL = baseURL
      self.secret = secret
    }
  }

  func connect() {
    guard !isConnected else {
      return
    }

    startTrafficStream()
    startMemoryStream()
    startConnectionPolling()
    startDataRefresh()
    fetchVersion()

    isConnected = true
  }

  func disconnect() {
    trafficTask?.cancel()
    memoryTask?.cancel()
    logTask?.cancel()
    connectionTask?.cancel()
    dataRefreshTask?.cancel()

    trafficTask = nil
    memoryTask = nil
    logTask = nil
    connectionTask = nil
    dataRefreshTask = nil
    isConnected = false
  }

  func statePublisher() -> AnyPublisher<State, Never> {
    stateSubject
      .receive(on: RunLoop.main)
      .eraseToAnyPublisher()
  }

  func currentState() -> State {
    stateSubject.value
  }

  func requestDashboardRefresh() {
    Task(priority: .utility) { @MainActor in
      await self.refreshDashboardData()
    }
  }

  func clearLogs() {
    logs.removeAll()
  }

  private var state: State {
    State(
      trafficHistory: trafficHistory,
      currentTraffic: currentTraffic,
      connections: connections,
      memoryUsage: memoryUsage,
      version: version,
      logs: logs,
      proxies: proxies,
      groups: groups,
      rules: rules,
      proxyProviders: proxyProviders,
      ruleProviders: ruleProviders,
      config: config,
      isConnected: isConnected,
    )
  }

  private func emitState() {
    stateSubject.send(state)
  }

  private func startDataRefresh() {
    dataRefreshTask?.cancel()
    dataRefreshTask = Task(priority: .utility) { [weak self] in
      guard let self else {
        return
      }

      await refreshDashboardData()

      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { break }
        await refreshDashboardData()
      }
    }
  }

  private func refreshDashboardData() async {
    await fetchProxies()
    await fetchGroups()
    await fetchRules()
    await fetchProxyProviders()
    await fetchRuleProviders()
    await fetchConfig()
  }

  private func startTrafficStream() {
    guard let url = URL(string: "\(baseURL)/traffic".replacingOccurrences(of: "http", with: "ws"))
    else {
      return
    }

    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 30,
    )
    if let secret {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    let task = URLSession.shared.webSocketTask(with: request)
    trafficTask = task
    task.resume()

    Task(priority: .high) { @MainActor in
      await consumeTrafficStream(task: task)
    }
  }

  private func consumeTrafficStream(task: URLSessionWebSocketTask) async {
    let stream = TrafficDataStream(task: task)

    do {
      for try await traffic in stream {
        currentTraffic = traffic

        let point = TrafficPoint(
          timestamp: Date(),
          upload: Double(traffic.up),
          download: Double(traffic.down),
        )

        trafficHistory.append(point)

        if trafficHistory.count > Self.maxTrafficPoints {
          trafficHistory.removeFirst(trafficHistory.count - Self.maxTrafficPoints)
        }
      }
    } catch {
      logger.notice("Traffic stream closed unexpectedly", error: error)
      reconnectTrafficStream()
    }
  }

  private func reconnectTrafficStream() {
    trafficTask?.cancel()
    trafficTask = nil

    Task(priority: .utility) {
      try? await Task.sleep(for: .seconds(2))
      startTrafficStream()
    }
  }

  private func startMemoryStream() {
    guard let url = URL(string: "\(baseURL)/memory".replacingOccurrences(of: "http", with: "ws"))
    else {
      return
    }

    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 30,
    )
    if let secret {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    let task = URLSession.shared.webSocketTask(with: request)
    memoryTask = task
    task.resume()

    Task(priority: .utility) { @MainActor in
      await consumeMemoryStream(task: task)
    }
  }

  private func consumeMemoryStream(task: URLSessionWebSocketTask) async {
    let stream = WebSocketMessageStream(task: task)

    do {
      for try await text in stream {
        guard let data = text.data(using: .utf8),
              let memory = try? JSONDecoder().decode(MemorySnapshot.self, from: data)
        else {
          continue
        }

        memoryUsage = memory.inuse
      }
    } catch {
      logger.notice("Memory stream closed unexpectedly", error: error)
      reconnectMemoryStream()
    }
  }

  private func reconnectMemoryStream() {
    memoryTask?.cancel()
    memoryTask = nil

    Task(priority: .utility) {
      try? await Task.sleep(for: .seconds(2))
      startMemoryStream()
    }
  }

  private func startConnectionPolling() {
    connectionTask?.cancel()
    connectionTask = Task(priority: .utility) { [weak self] in
      guard let self else {
        return
      }

      while !Task.isCancelled {
        await fetchConnections()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  private func fetchConnections() async {
    guard let url = URL(string: "\(baseURL)/connections") else {
      return
    }

    var request = URLRequest(
      url: url,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 5,
    )
    if let secret {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    do {
      let (data, _) = try await URLSession.shared.data(for: request)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        if let date = DateFormatting.parseISO8601(dateString) {
          return date
        }
        throw DecodingError.dataCorruptedError(
          in: container,
          debugDescription: "Invalid date format.",
        )
      }
      let snapshot = try decoder.decode(ConnectionSnapshot.self, from: data)
      connections = snapshot.connections
    } catch {
      logger.error("Failed to fetch connections snapshot.", error: error)
    }
  }

  private func fetchVersion() {
    guard let url = URL(string: "\(baseURL)/version") else {
      return
    }

    var request = URLRequest(url: url)
    if let secret {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    Task(name: "Fetch Mihomo Version") {
      do {
        let (data, _) = try await URLSession.shared.data(for: request)
        let versionInfo = try JSONDecoder().decode(ClashVersion.self, from: data)
        await MainActor.run {
          self.version = versionInfo.version
          self.logger.info("Fetched Mihomo version.", metadata: ["version": versionInfo.version])
        }
      } catch {
        self.logger.error("Failed to fetch Mihomo version.", error: error)
      }
    }
  }

  private func makeRequest(
    path: String,
    method: String = "GET",
    body: Data? = nil,
    queryItems: [URLQueryItem] = [],
  ) async throws -> (Data, HTTPURLResponse) {
    var components = URLComponents(string: "\(baseURL)\(path)")
    components?.queryItems = queryItems.isEmpty ? nil : queryItems

    guard let url = components?.url else {
      throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.httpBody = body

    if let secret {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let capturedRequest = request
    let (data, response) = try await NetworkError.catch { @Sendable () async throws -> (
      Data,
      URLResponse
    ) in
      try await URLSession.shared.data(for: capturedRequest)
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw URLError(.badServerResponse)
    }

    if httpResponse.statusCode >= 400 {
      if let error = try? JSONDecoder().decode(APIError.self, from: data) {
        throw error
      }
      throw URLError(.badServerResponse)
    }

    return (data, httpResponse)
  }

  private func fetchProxies() async {
    do {
      let (data, _) = try await makeRequest(path: "/proxies")
      let response = try JSONDecoder().decode(ProxiesResponse.self, from: data)
      proxies = response.proxies
    } catch {
      logger.error("Failed to fetch proxies from API.", error: error)
    }
  }

  private func fetchGroups() async {
    do {
      let (data, _) = try await makeRequest(path: "/group")
      let response = try JSONDecoder().decode(GroupsResponse.self, from: data)
      groups = response.proxies
    } catch {
      logger.error("Failed to fetch proxy groups from API.", error: error)
    }
  }

  private func fetchRules() async {
    do {
      let (data, _) = try await makeRequest(path: "/rules")
      let response = try JSONDecoder().decode(RulesResponse.self, from: data)
      rules = response.rules
    } catch {
      logger.error("Failed to fetch rules from API.", error: error)
    }
  }

  private func fetchProxyProviders() async {
    do {
      let (data, _) = try await makeRequest(path: "/providers/proxies")
      let response = try JSONDecoder().decode(ProxyProvidersResponse.self, from: data)
      proxyProviders = response.providers
    } catch {
      logger.error("Failed to fetch proxy providers from API.", error: error)
    }
  }

  private func fetchRuleProviders() async {
    do {
      let (data, _) = try await makeRequest(path: "/providers/rules")
      let response = try JSONDecoder().decode(RuleProvidersResponse.self, from: data)
      ruleProviders = response.providers
    } catch {
      logger.error("Failed to fetch rule providers from API.", error: error)
    }
  }

  private func fetchConfig() async {
    do {
      let (data, _) = try await makeRequest(path: "/configs")
      config = try JSONDecoder().decode(ClashConfig.self, from: data)
    } catch {
      let chain = ErrorKit.errorChainDescription(for: error)
      logger.error("Failed to fetch configuration.\n\(chain)", error: error)
    }
  }

  func startLogStream(level: String? = nil) {
    var path = "/logs"
    if let level {
      path += "?level=\(level)"
    }

    guard let url = URL(string: "\(baseURL)\(path)".replacingOccurrences(of: "http", with: "ws"))
    else {
      return
    }

    var request = URLRequest(url: url)
    if let secret {
      request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
    }

    let task = URLSession.shared.webSocketTask(with: request)
    logTask = task
    task.resume()

    Task(name: "Log Stream Consumer") { @MainActor in
      await consumeLogStream(task: task)
    }
  }

  private func consumeLogStream(task: URLSessionWebSocketTask) async {
    let stream = WebSocketMessageStream(task: task)

    do {
      for try await text in stream {
        guard let data = text.data(using: .utf8),
              let log = try? JSONDecoder().decode(LogMessage.self, from: data)
        else {
          continue
        }

        logs.append(log)

        if logs.count > Self.maxLogEntries {
          logs.removeFirst(logs.count - Self.maxLogEntries)
        }
      }
    } catch {
      logger.debug("Log stream error.", error: error)
    }
  }

  func stopLogStream() {
    logTask?.cancel()
    logTask = nil
  }

  func getConfig() async throws -> ClashConfig {
    let (data, _) = try await makeRequest(path: "/configs")
    return try JSONDecoder().decode(ClashConfig.self, from: data)
  }

  func reloadConfig(path: String = "", payload: String = "") async throws {
    let request = ConfigUpdateRequest(path: path, payload: payload)
    let body = try JSONEncoder().encode(request)
    _ = try await makeRequest(
      path: "/configs",
      method: "PUT",
      body: body,
      queryItems: [URLQueryItem(name: "force", value: "true")],
    )
    logger.info("Reloaded Config")
    await fetchConfig()
  }

  func updateConfig(_ updates: [String: Any]) async throws {
    let body = try JSONSerialization.data(withJSONObject: updates)
    _ = try await makeRequest(path: "/configs", method: "PATCH", body: body)
    logger.info("Updated Config")
    await fetchConfig()
  }

  func upgradeGeo2() async throws {
    _ = try await makeRequest(path: "/configs/geo", method: "POST", body: Data())
    logger.info("Updated GEO database")
  }

  func restart() async throws {
    _ = try await makeRequest(path: "/restart", method: "POST", body: Data())
    logger.info("Restarted core")
  }

  func upgradeCore() async throws {
    _ = try await makeRequest(path: "/upgrade", method: "POST", body: Data())
    logger.info("Upgraded core")
  }

  func upgradeUI() async throws {
    _ = try await makeRequest(path: "/upgrade/ui", method: "POST", body: Data())
    logger.info("Upgraded UI")
  }

  func upgradeGeo1() async throws {
    _ = try await makeRequest(path: "/upgrade/geo", method: "POST", body: Data())
    logger.info("Upgraded GEO database")
  }

  func flushFakeIPCache() async throws {
    _ = try await makeRequest(path: "/cache/fakeip/flush", method: "POST", body: Data())
    logger.info("Flushed fake IP cache")
  }

  func closeAllConnections() async throws {
    _ = try await makeRequest(path: "/connections", method: "DELETE")
    logger.info("Closed all connections")
    await fetchConnections()
  }

  func closeConnection(id: String) async throws {
    _ = try await makeRequest(path: "/connections/\(id)", method: "DELETE")
    logger.info("Closed connection: \(id)")
    await fetchConnections()
  }

  func selectProxy(group: String, proxy: String) async throws {
    let encodedGroup = group.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? group
    let request = ProxySelectRequest(name: proxy)
    let body = try JSONEncoder().encode(request)
    _ = try await makeRequest(path: "/proxies/\(encodedGroup)", method: "PUT", body: body)
    logger.info("Selected proxy \(proxy) for group \(group)")
    await fetchProxies()
    await fetchGroups()
  }

  func testProxyDelay(
    name: String,
    url: String = "https://www.apple.com/library/test/success.html",
    timeout: Int = 5000,
  ) async throws -> ProxyDelayTest {
    let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    let queryItems = [
      URLQueryItem(name: "url", value: url),
      URLQueryItem(name: "timeout", value: "\(timeout)"),
    ]
    let (data, _) = try await makeRequest(
      path: "/proxies/\(encodedName)/delay",
      queryItems: queryItems,
    )
    return try JSONDecoder().decode(ProxyDelayTest.self, from: data)
  }

  func testGroupDelay(
    name: String,
    url: String = "https://www.apple.com/library/test/success.html",
    timeout: Int = 5000,
  ) async throws {
    let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    let queryItems = [
      URLQueryItem(name: "url", value: url),
      URLQueryItem(name: "timeout", value: "\(timeout)"),
    ]
    _ = try await makeRequest(path: "/group/\(encodedName)/delay", queryItems: queryItems)
    logger.info("Tested group delay: \(name)")
    await fetchGroups()
  }

  func updateProxyProvider(name: String) async throws {
    let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    _ = try await makeRequest(
      path: "/providers/proxies/\(encodedName)",
      method: "PUT",
      body: Data(),
    )
    logger.info("Updated proxy provider: \(name)")
    await fetchProxyProviders()
  }

  func healthCheckProxyProvider(name: String) async throws {
    let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    _ = try await makeRequest(path: "/providers/proxies/\(encodedName)/healthcheck")
    logger.info("Health check for proxy provider: \(name)")
    await fetchProxyProviders()
  }

  func updateRuleProvider(name: String) async throws {
    let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
    _ = try await makeRequest(path: "/providers/rules/\(encodedName)", method: "PUT", body: Data())
    logger.info("Updated rule provider: \(name)")
    await fetchRuleProviders()
  }

  func queryDNS(name: String, type: String = "A") async throws -> DNSQueryResponse {
    let queryItems = [
      URLQueryItem(name: "name", value: name),
      URLQueryItem(name: "type", value: type),
    ]
    let (data, _) = try await makeRequest(path: "/dns/query", queryItems: queryItems)
    return try JSONDecoder().decode(DNSQueryResponse.self, from: data)
  }

  func triggerGC() async throws {
    _ = try await makeRequest(path: "/debug/gc", method: "PUT", body: Data())
    logger.info("Triggered garbage collection")
  }
}
