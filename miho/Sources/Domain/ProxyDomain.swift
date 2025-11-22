@preconcurrency import Combine
import Dependencies
import Foundation
import Observation
import OSLog
import SystemConfiguration
import UserNotifications

@MainActor
private enum ProxyDomainDependencies {
  @Dependency(\.networkInspector)
  static var networkInspector
}

@MainActor
@Observable
final class ProxyDomain {
  struct State: Equatable {
    var isSystemProxyEnabled: Bool
    var isTunModeEnabled: Bool
    var currentMode: ProxyMode
    var allowLAN: Bool
    var httpPort: Int
    var socksPort: Int
    var mixedPort: Int?

    var statusSummary: String {
      var parts: [String] = []

      if isSystemProxyEnabled {
        if let mixedPort {
          parts.append("System proxy (mixed: \(mixedPort))")
        } else {
          parts.append("System proxy (HTTP: \(httpPort), SOCKS: \(socksPort))")
        }
      }

      if isTunModeEnabled {
        parts.append("TUN mode")
      }

      return parts.isEmpty ? "Disabled" : parts.joined(separator: " + ")
    }
  }

  static let shared = ProxyDomain()

  private let logger = MihoLog.shared.logger(for: .proxy)
  private let daemonManager = DaemonDomain.shared

  var isSystemProxyEnabled = false {
    didSet { if isSystemProxyEnabled != oldValue { emitState() } }
  }

  var isTunModeEnabled = false {
    didSet { if isTunModeEnabled != oldValue { emitState() } }
  }

  var currentMode: ProxyMode = .rule {
    didSet { if currentMode != oldValue { emitState() } }
  }

  var allowLAN = false {
    didSet { if allowLAN != oldValue { emitState() } }
  }

  var httpPort: Int = 7890 {
    didSet { if httpPort != oldValue { emitState() } }
  }

  var socksPort: Int = 7891 {
    didSet { if socksPort != oldValue { emitState() } }
  }

  var mixedPort: Int? {
    didSet { if mixedPort != oldValue { emitState() } }
  }

  private var configWatcher: ConfigDomain?
  private let stateSubject: CurrentValueSubject<State, Never>
  private let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/clash/config.yaml")
  private var cachedConfig: (model: ProxyModel, modified: Date)?

  private var proxyChangeObserver: (any NSObjectProtocol)?
  private var networkChangeObserver: (any NSObjectProtocol)?
  private var wakeObserver: (any NSObjectProtocol)?

  private init() {
    stateSubject = CurrentValueSubject(
      State(
        isSystemProxyEnabled: false,
        isTunModeEnabled: false,
        currentMode: .rule,
        allowLAN: false,
        httpPort: 7890,
        socksPort: 7891,
        mixedPort: nil,
      ),
    )
    setupConfigWatcher()
    setupNetworkObservers()
  }

  private func setupConfigWatcher() {
    configWatcher = ConfigDomain(url: configURL) { [weak self] in
      await self?.reloadConfig()
    }
  }

  private func setupNetworkObservers() {
    proxyChangeObserver = NotificationCenter.default.addObserver(
      forName: .systemProxyDidChange,
      object: nil,
      queue: .main,
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.handleProxyConfigChange()
      }
    }

    networkChangeObserver = NotificationCenter.default.addObserver(
      forName: .networkInterfaceDidChange,
      object: nil,
      queue: .main,
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.handleNetworkInterfaceChange()
      }
    }

    wakeObserver = NotificationCenter.default.addObserver(
      forName: .systemDidWakeFromSleep,
      object: nil,
      queue: .main,
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        await self?.handleSystemWake()
      }
    }
  }

  func enableSystemProxy() async throws {
    daemonManager.checkStatus()

    if daemonManager.requiresApproval {
      throw DaemonError.requiresApproval
    }

    if !daemonManager.isRegistered {
      try await daemonManager.register()
    }

    let config = try? await loadConfig()
    let http = config?.mixedPort ?? config?.httpPort ?? httpPort
    let socks = config?.mixedPort ?? config?.socksPort ?? socksPort

    do {
      try await daemonManager.enableProxy(
        httpPort: http,
        socksPort: socks,
        pacUrl: nil,
        filterInterface: true,
        ignoreList: [],
      )
      isSystemProxyEnabled = true
      logger.info(
        "System proxy enabled.",
        metadata: ["httpPort": "\(http)", "socksPort": "\(socks)"],
      )
    } catch {
      isSystemProxyEnabled = false
      logger.error("Failed to enable system proxy.", error: error)
      throw error
    }
  }

  func disableSystemProxy() async throws {
    do {
      try await daemonManager.disableProxy(filterInterface: true)
      isSystemProxyEnabled = false
      logger.info("System proxy disabled.")
    } catch {
      logger.error("Failed to disable system proxy.", error: error)
      throw error
    }
  }

  func toggleSystemProxy() async throws {
    if isSystemProxyEnabled {
      try await disableSystemProxy()
    } else {
      try await enableSystemProxy()
    }
  }

  func enableTunMode() async throws {
    if !daemonManager.isRegistered {
      try await daemonManager.register()
    }
    let config = try? await loadConfig()
    let dnsServer = config?.tunDNS ?? "198.18.0.2"

    try await daemonManager.updateTun(enabled: true, dnsServer: dnsServer)

    try await updateCoreTunMode(enabled: true)

    isTunModeEnabled = true
    logger.info("TUN mode enabled.", metadata: ["dnsServer": dnsServer])
  }

  func disableTunMode() async throws {
    try await daemonManager.updateTun(enabled: false, dnsServer: "")
    try await updateCoreTunMode(enabled: false)

    isTunModeEnabled = false
    logger.info("TUN mode disabled.")
  }

  func toggleTunMode() async throws {
    if isTunModeEnabled {
      try await disableTunMode()
    } else {
      try await enableTunMode()
    }
  }

  func setAllowLAN(_ enabled: Bool) async throws {
    guard allowLAN != enabled else {
      return
    }

    do {
      try await updateCoreAllowLAN(enabled: enabled)
      allowLAN = enabled
      logger.info("Allow LAN setting updated.", metadata: ["enabled": enabled ? "true" : "false"])
    } catch {
      logger.error("Failed to update Allow LAN setting.", error: error)
      throw error
    }
  }

  func switchMode(_ mode: ProxyMode) async {
    currentMode = mode
    await updateCoreMode(mode)
  }

  @inline(__always)
  private func loadConfig() async throws -> ProxyModel {
    let attrs = try FileManager.default.attributesOfItem(atPath: configURL.path)
    let mod = (attrs[.modificationDate] as? Date) ?? .distantPast
    if let cached = cachedConfig, cached.modified == mod {
      return cached.model
    }

    let data = try Data(contentsOf: configURL, options: [.mappedIfSafe, .uncached])
    let decoded = try YAMLDecoder().decode(ProxyModel.self, from: data)
    cachedConfig = (decoded, mod)
    return decoded
  }

  func reloadConfig() async {
    do {
      let cfg = try await loadConfig()
      currentMode = ProxyMode(rawValue: cfg.mode ?? "rule") ?? .rule
      allowLAN = cfg.allowLan
      httpPort = cfg.httpPort
      socksPort = cfg.effectiveSocksPort
      mixedPort = cfg.mixedPort
      isTunModeEnabled = cfg.tunEnabled
      emitState()
    } catch {
      logger.error("Failed to reload configuration.", error: error)
    }
  }

  private func updateCoreMode(_ mode: ProxyMode) async {
    guard let url = URL(string: "http://127.0.0.1:9090/configs") else {
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["mode": mode.rawValue])

    do {
      _ = try await URLSession.shared.data(for: req)
    } catch {
      logger.error("Proxy mode update failed", error: error)
    }
  }

  private func updateCoreTunMode(enabled: Bool) async throws {
    guard let url = URL(string: "http://127.0.0.1:9090/configs") else {
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["tun": ["enable": enabled]])

    _ = try await URLSession.shared.data(for: req)
  }

  private func updateCoreAllowLAN(enabled: Bool) async throws {
    guard let url = URL(string: "http://127.0.0.1:9090/configs") else {
      return
    }

    var req = URLRequest(url: url)
    req.httpMethod = "PATCH"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: ["allow-lan": enabled])

    _ = try await URLSession.shared.data(for: req)
  }

  var statusDescription: String {
    snapshotState().statusSummary
  }

  private func handleProxyConfigChange() async {
    guard isSystemProxyEnabled else {
      return
    }

    let port = mixedPort ?? httpPort
    let isMihomo = await ProxyDomainDependencies.networkInspector.isSystemProxySetToMihomo(
      port,
      socksPort,
      true,
    )
    if !isMihomo {
      logger.notice("System proxy configuration changed by an external process.")
    }
  }

  private func handleNetworkInterfaceChange() async {
    guard let iface = await ProxyDomainDependencies.networkInspector.getPrimaryInterfaceName()
    else {
      return
    }
    let ip = await ProxyDomainDependencies.networkInspector.getPrimaryIPAddress(false) ?? "unknown"
    logger.info("Primary network interface updated.", metadata: ["interface": iface, "address": ip])
  }

  private func handleSystemWake() async {
    guard isSystemProxyEnabled else {
      return
    }

    let port = mixedPort ?? httpPort
    let isMihomo = await ProxyDomainDependencies.networkInspector.isSystemProxySetToMihomo(
      port,
      socksPort,
      true,
    )
    if !isMihomo {
      logger.notice("System proxy not detected after wake; attempting to restore.")
      do {
        try await enableSystemProxy()
      } catch {
        logger.error("Unable to restore system proxy after wake.", error: error)
      }
    }
  }

  func statePublisher() -> AnyPublisher<State, Never> {
    stateSubject
      .receive(on: RunLoop.main)
      .eraseToAnyPublisher()
  }

  func currentState() -> State {
    stateSubject.value
  }

  private func snapshotState() -> State {
    State(
      isSystemProxyEnabled: isSystemProxyEnabled,
      isTunModeEnabled: isTunModeEnabled,
      currentMode: currentMode,
      allowLAN: allowLAN,
      httpPort: httpPort,
      socksPort: socksPort,
      mixedPort: mixedPort,
    )
  }

  @inline(__always)
  private func emitState() {
    stateSubject.send(snapshotState())
  }
}

enum ProxyMode: String, Codable, CaseIterable {
  case rule
  case global
  case direct

  var displayName: String {
    switch self {
    case .rule: "Rule"
    case .global: "Global"
    case .direct: "Direct"
    }
  }
}

@MainActor
final class ConfigDomain {
  private var fileDescriptor: CInt = -1
  private var dispatchSource: (any DispatchSourceFileSystemObject)?
  private let onChange: @Sendable () async -> Void
  private let logger = MihoLog.shared.logger(for: .core)

  private var shouldSuppressNextChange = false

  init(url: URL, onChange: @escaping @Sendable () async -> Void) {
    self.onChange = onChange
    startWatching(url: url)
  }

  private func startWatching(url: URL) {
    let fd = open(url.path, O_EVTONLY)
    guard fd >= 0 else {
      logger.error("Failed to open config file for watching")
      return
    }
    fileDescriptor = fd

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: [.write, .delete, .rename],
      queue: .main,
    )

    source.setEventHandler { [weak self] in
      guard let self else {
        return
      }
      handleFileEvent()
    }

    source.setCancelHandler { [weak self] in
      guard let self else {
        return
      }
      closeFileDescriptor()
    }

    source.resume()
    dispatchSource = source
    logger.info("Config file watching started")
  }

  func suppressNextChange() {
    shouldSuppressNextChange = true
    logger.debug("Next change suppressed")
  }

  private func sendChangeNotification() async {
    let content = UNMutableNotificationContent()
    content.title = "Configuration Changed"
    content.body = "Reload to apply updates"
    content.sound = .default
    content.categoryIdentifier = "CONFIG_CHANGE"

    let request = UNNotificationRequest(
      identifier: "cfg-\(Date().timeIntervalSince1970)",
      content: content,
      trigger: nil,
    )

    do {
      try await UNUserNotificationCenter.current().add(request)
    } catch {
      logger.debug("Notification delivery failed", error: error)
    }
  }

  deinit {
    dispatchSource?.cancel()
  }

  private func handleFileEvent() {
    if shouldSuppressNextChange {
      shouldSuppressNextChange = false
      logger.debug("Change suppressed")
      return
    }

    logger.info("Config file changed")

    Task(priority: .utility) { [onChange] in
      await self.sendChangeNotification()
      await onChange()
    }
  }

  private func closeFileDescriptor() {
    guard fileDescriptor >= 0 else {
      return
    }
    close(fileDescriptor)
    fileDescriptor = -1
  }
}
