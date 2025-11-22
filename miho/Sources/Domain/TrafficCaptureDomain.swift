@preconcurrency import Combine
import Darwin
import Dependencies
import ErrorKit
import Foundation
import Observation
import OSLog
import SystemConfiguration

// swiftlint:disable conditional_returns_on_newline
enum TrafficCaptureMode: String, CaseIterable, Codable, Sendable {
  case global
  case pac
  case manual
  case tun

  var displayName: String {
    switch self {
    case .global: "Global"
    case .pac: "PAC"
    case .manual: "Manual"
    case .tun: "TUN"
    }
  }

  var summary: String {
    switch self {
    case .global:
      "Route all traffic through Mihomo using macOS system proxy settings"

    case .pac:
      "Use a PAC file to decide which traffic is proxied"

    case .manual:
      "Only manage the Mihomo core without touching system network settings"

    case .tun:
      "Create a virtual interface to transparently capture traffic"
    }
  }
}

struct TrafficCaptureDriverID: Hashable, Codable, Sendable, RawRepresentable {
  let rawValue: String
}

enum TrafficCaptureDriverKind: String, Codable, CaseIterable, Sendable {
  case systemConfiguration
  case networkSetup
  case process
  case spawn
  case tunDevice
  case utun
  case pf
  case divert
  case transparentRouting
}

struct TrafficCaptureDriverDescriptor: Equatable, Hashable, Sendable {
  let id: TrafficCaptureDriverID
  let name: String
  let kind: TrafficCaptureDriverKind
  let supportedModes: Set<TrafficCaptureMode>
  let requiresPrivileges: Bool
}

struct TrafficCaptureDriverStatus: Equatable, Sendable {
  var isActive: Bool
  var summary: String
  var diagnostics: String?
}

struct TrafficCaptureActivationContext: Sendable {
  var httpPort: Int
  var socksPort: Int
  var pacURL: URL?
  var configurationDirectory: URL?
  var environment: [String: String]

  static let empty = Self(
    httpPort: 0,
    socksPort: 0,
    pacURL: nil,
    configurationDirectory: nil,
    environment: [:],
  )
}

@MainActor
protocol TrafficCaptureDriver: AnyObject {
  var descriptor: TrafficCaptureDriverDescriptor { get }
  var supportedModes: Set<TrafficCaptureMode> { get }

  func fallbackPriority(for mode: TrafficCaptureMode) -> Int
  func isAvailable(for mode: TrafficCaptureMode) -> Bool

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws

  func deactivate(mode: TrafficCaptureMode) async throws
  func status(for mode: TrafficCaptureMode) async -> TrafficCaptureDriverStatus
}

extension TrafficCaptureDriver {
  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 0 }

  func isAvailable(for mode: TrafficCaptureMode) -> Bool {
    supportedModes.contains(mode)
  }
}

protocol SystemProxyDriver: TrafficCaptureDriver { }
protocol PacProxyDriver: TrafficCaptureDriver { }
protocol ManualProcessDriver: TrafficCaptureDriver { }
protocol TunnelDriver: TrafficCaptureDriver { }

struct TrafficCaptureDriverFailure: Equatable, Sendable {
  let driverID: TrafficCaptureDriverID
  let errorDescription: String
}

enum TrafficCaptureDomainError: LocalizedError, Throwable {
  case noDriversAvailable(mode: TrafficCaptureMode)
  case activationFailed(mode: TrafficCaptureMode, failures: [TrafficCaptureDriverFailure])

  var userFriendlyMessage: String {
    errorDescription ?? "Traffic capture error"
  }

  var errorDescription: String? {
    switch self {
    case let .noDriversAvailable(mode):
      return "No drivers are registered for mode \(mode.displayName)."

    case let .activationFailed(mode, failures):
      let reasons = failures.map { "\($0.driverID.rawValue): \($0.errorDescription)" }
        .joined(separator: ", ")
      return "Unable to activate \(mode.displayName). Attempted drivers: \(reasons)"
    }
  }
}

@MainActor
@Observable
final class TrafficCaptureDomain {
  struct State: Equatable {
    var selectedMode: TrafficCaptureMode
    var activeDriver: TrafficCaptureDriverID?
    var preferredDrivers: [TrafficCaptureMode: TrafficCaptureDriverID]
    var autoFallbackEnabled: Bool
    var isActivating: Bool
    var isActive: Bool
    var availableDrivers: [TrafficCaptureMode: [TrafficCaptureDriverDescriptor]]
    var lastErrorDescription: String?
  }

  static let shared = TrafficCaptureDomain()

  var selectedMode: TrafficCaptureMode = .manual {
    didSet {
      if selectedMode != oldValue {
        SettingsManager.shared.trafficCaptureMode = selectedMode
        emitState()
      }
    }
  }

  var activeDriver: TrafficCaptureDriverID? {
    didSet { emitState() }
  }

  var autoFallbackEnabled = true {
    didSet {
      if autoFallbackEnabled != oldValue {
        SettingsManager.shared.trafficCaptureAutoFallbackEnabled = autoFallbackEnabled
        emitState()
      }
    }
  }

  var isActivating = false {
    didSet { emitState() }
  }

  var isActive = false {
    didSet { emitState() }
  }

  var lastErrorDescription: String? {
    didSet { emitState() }
  }

  private var preferredDrivers: [TrafficCaptureMode: TrafficCaptureDriverID] = [:] {
    didSet {
      SettingsManager.shared.trafficCapturePreferredDrivers = preferredDrivers
      emitState()
    }
  }

  @ObservationIgnored private var drivers: [TrafficCaptureDriverID: any TrafficCaptureDriver] = [:]

  @ObservationIgnored private let stateSubject: CurrentValueSubject<State, Never>

  private init() {
    stateSubject = CurrentValueSubject(
      State(
        selectedMode: .manual,
        activeDriver: nil,
        preferredDrivers: [:],
        autoFallbackEnabled: true,
        isActivating: false,
        isActive: false,
        availableDrivers: [:],
        lastErrorDescription: nil,
      ),
    )

    registerDefaultDrivers()
    restorePreferences()
    emitState()
  }

  func register(driver: any TrafficCaptureDriver) {
    drivers[driver.descriptor.id] = driver
    emitState()
  }

  func unregisterDriver(with id: TrafficCaptureDriverID) {
    drivers.removeValue(forKey: id)
    if activeDriver == id {
      activeDriver = nil
      isActive = false
    }
    emitState()
  }

  func setPreferredDriver(_ id: TrafficCaptureDriverID?, for mode: TrafficCaptureMode) {
    preferredDrivers[mode] = id
  }

  func statePublisher() -> AnyPublisher<State, Never> {
    stateSubject
      .receive(on: RunLoop.main)
      .eraseToAnyPublisher()
  }

  func currentState() -> State {
    stateSubject.value
  }

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext = .empty,
  ) async throws {
    selectedMode = mode
    lastErrorDescription = nil
    let chain = resolveDriverChain(for: mode)
    guard !chain.isEmpty else {
      throw TrafficCaptureDomainError.noDriversAvailable(mode: mode)
    }

    isActivating = true
    defer { isActivating = false }

    var failures: [TrafficCaptureDriverFailure] = []

    for driver in chain {
      guard driver.isAvailable(for: mode) else { continue }
      do {
        try await driver.activate(mode: mode, context: context)
        activeDriver = driver.descriptor.id
        isActive = true
        emitState()
        return
      } catch {
        let failure = TrafficCaptureDriverFailure(
          driverID: driver.descriptor.id,
          errorDescription: error.localizedDescription,
        )
        failures.append(failure)
        lastErrorDescription = failure.errorDescription
        if !autoFallbackEnabled { break }
      }
    }

    activeDriver = nil
    isActive = false

    let error = TrafficCaptureDomainError.activationFailed(mode: mode, failures: failures)
    lastErrorDescription = error.localizedDescription
    throw error
  }

  func deactivateCurrentMode() async {
    guard let activeDriver, let driver = drivers[activeDriver] else {
      self.activeDriver = nil
      isActive = false
      return
    }

    do {
      try await driver.deactivate(mode: selectedMode)
    } catch {
      lastErrorDescription = error.localizedDescription
    }

    self.activeDriver = nil
    isActive = false
  }

  private func resolveDriverChain(for mode: TrafficCaptureMode) -> [any TrafficCaptureDriver] {
    let allDrivers = drivers.values.filter { $0.supportedModes.contains(mode) }
    if allDrivers.isEmpty {
      return []
    }

    let preferred = preferredDrivers[mode]

    let sorted = allDrivers.sorted { lhs, rhs in
      if let preferred {
        if lhs.descriptor.id == preferred {
          return true
        }
        if rhs.descriptor.id == preferred {
          return false
        }
      }

      let lhsPriority = lhs.fallbackPriority(for: mode)
      let rhsPriority = rhs.fallbackPriority(for: mode)

      if lhsPriority == rhsPriority {
        return lhs.descriptor.name < rhs.descriptor.name
      }

      return lhsPriority < rhsPriority
    }

    if autoFallbackEnabled {
      return sorted
    } else if let first = sorted.first {
      return [first]
    }

    return sorted
  }

  private func snapshotState() -> State {
    State(
      selectedMode: selectedMode,
      activeDriver: activeDriver,
      preferredDrivers: preferredDrivers,
      autoFallbackEnabled: autoFallbackEnabled,
      isActivating: isActivating,
      isActive: isActive,
      availableDrivers: availableDriverDescriptors(),
      lastErrorDescription: lastErrorDescription,
    )
  }

  private func availableDriverDescriptors()
  -> [TrafficCaptureMode: [TrafficCaptureDriverDescriptor]] {
    var mapping: [TrafficCaptureMode: [TrafficCaptureDriverDescriptor]] = [:]

    for driver in drivers.values {
      for mode in driver.supportedModes {
        mapping[mode, default: []].append(driver.descriptor)
      }
    }

    for mode in TrafficCaptureMode.allCases where mapping[mode] == nil {
      mapping[mode] = []
    }

    for key in mapping.keys {
      mapping[key]?.sort(by: { $0.name < $1.name })
    }

    return mapping
  }

  private func registerDefaultDrivers() {
    let defaultDrivers: [any TrafficCaptureDriver] = [
      SystemConfigurationGlobalDriver(),
      NetworkSetupGlobalDriver(),
      SystemConfigurationPACDriver(),
      NetworkSetupPACDriver(),
      ProcessManualDriver(),
      PosixSpawnManualDriver(),
      TunDeviceDriver(),
      PfTransparentProxyDriver(),
      DivertSocketDriver(),
      RoutingRuleDriver(),
    ]

    defaultDrivers.forEach { register(driver: $0) }
  }

  private func restorePreferences() {
    let settings = SettingsManager.shared
    selectedMode = settings.trafficCaptureMode
    autoFallbackEnabled = settings.trafficCaptureAutoFallbackEnabled
    preferredDrivers = settings.trafficCapturePreferredDrivers
  }

  private func emitState() {
    stateSubject.send(snapshotState())
  }
}

enum TrafficCaptureDriverError: LocalizedError, Throwable {
  case systemConfigurationUnavailable
  case networkSetupUnavailable
  case commandFailed(executable: String, arguments: [String], output: String)
  case processAlreadyRunning
  case processNotRunning
  case executableNotFound
  case spawnFailed(Int32)
  case tunDeviceUnavailable
  case pfConfigurationFailed(String)
  case divertConfigurationFailed(String)
  case routingConfigurationFailed(String)

  var userFriendlyMessage: String {
    errorDescription ?? "Traffic capture driver error"
  }

  var errorDescription: String? {
    switch self {
    case .systemConfigurationUnavailable:
      "Unable to access SystemConfiguration preferences."

    case .networkSetupUnavailable:
      "The `networksetup` command is not available on this system."

    case let .commandFailed(executable, _, output):
      "Command \(executable) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"

    case .processAlreadyRunning:
      "The Mihomo core is already running."

    case .processNotRunning:
      "The Mihomo core is not running."

    case .executableNotFound:
      "Unable to locate the Mihomo executable in the application bundle."

    case let .spawnFailed(code):
      "posix_spawn failed with error code \(code)."

    case .tunDeviceUnavailable:
      "Unable to allocate a TUN/UTUN device."

    case let .pfConfigurationFailed(message):
      "PF configuration failed: \(message)"

    case let .divertConfigurationFailed(message):
      "Divert socket configuration failed: \(message)"

    case let .routingConfigurationFailed(message):
      "Routing rule configuration failed: \(message)"
    }
  }
}

@MainActor
private enum TrafficCaptureDependencies {
  @Dependency(\.networkInspector)
  static var networkInspector
}

enum TrafficCaptureCommandRunner {
  static func run(
    executable: String,
    arguments: [String],
    environment: [String: String] = [:],
  ) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if !environment.isEmpty {
      var env = ProcessInfo.processInfo.environment
      environment.forEach { env[$0.key] = $0.value }
      process.environment = env
    }

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let outData = stdout.fileHandleForReading.readDataToEndOfFile()
    let errData = stderr.fileHandleForReading.readDataToEndOfFile()

    let output = [outData, errData]
      .compactMap { String(data: $0, encoding: .utf8) }
      .joined()

    guard process.terminationStatus == 0 else {
      throw TrafficCaptureDriverError.commandFailed(
        executable: executable,
        arguments: arguments,
        output: output,
      )
    }

    return output
  }
}

enum SystemProxyConfigurator {
  static func updateProxyConfiguration(
    modifier: (inout [String: Any]) -> Void,
  ) throws {
    guard let prefs = SCPreferencesCreate(nil, "com.swift.miho.proxy" as CFString, nil) else {
      throw TrafficCaptureDriverError.systemConfigurationUnavailable
    }

    guard let currentSet = SCNetworkSetCopyCurrent(prefs) else {
      throw TrafficCaptureDriverError.systemConfigurationUnavailable
    }

    guard let services = SCNetworkSetCopyServices(currentSet) as? [SCNetworkService] else {
      throw TrafficCaptureDriverError.systemConfigurationUnavailable
    }

    var modified = false

    for service in services {
      guard
        let proto = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies),
        var config = SCNetworkProtocolGetConfiguration(proto) as? [String: Any]
      else { continue }

      modifier(&config)

      if SCNetworkProtocolSetConfiguration(proto, config as CFDictionary) {
        modified = true
      }
    }

    guard modified else { return }
    guard SCPreferencesCommitChanges(prefs), SCPreferencesApplyChanges(prefs) else {
      throw TrafficCaptureDriverError.systemConfigurationUnavailable
    }
  }
}

@MainActor
final class SystemConfigurationGlobalDriver: SystemProxyDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "sc-global"),
    name: "SystemConfiguration Global",
    kind: .systemConfiguration,
    supportedModes: [.global],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.global]
  private let logger = MihoLog.shared.logger(for: .proxySettings)
  private var activeContext: TrafficCaptureActivationContext?

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .global else { return }

    try SystemProxyConfigurator.updateProxyConfiguration { config in
      config[kCFNetworkProxiesHTTPEnable as String] = 1
      config[kCFNetworkProxiesHTTPPort as String] = context.httpPort
      config[kCFNetworkProxiesHTTPProxy as String] = "127.0.0.1"

      config[kCFNetworkProxiesHTTPSEnable as String] = 1
      config[kCFNetworkProxiesHTTPSPort as String] = context.httpPort
      config[kCFNetworkProxiesHTTPSProxy as String] = "127.0.0.1"

      config[kCFNetworkProxiesSOCKSEnable as String] = 1
      config[kCFNetworkProxiesSOCKSPort as String] = context.socksPort
      config[kCFNetworkProxiesSOCKSProxy as String] = "127.0.0.1"

      config[kCFNetworkProxiesProxyAutoConfigEnable as String] = 0
      config[kCFNetworkProxiesProxyAutoConfigURLString as String] = ""
    }

    activeContext = context
    logger.info(
      "SystemConfiguration global proxy enabled",
      metadata: ["http": "\(context.httpPort)", "socks": "\(context.socksPort)"],
    )
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .global else { return }

    try SystemProxyConfigurator.updateProxyConfiguration { config in
      config[kCFNetworkProxiesHTTPEnable as String] = 0
      config[kCFNetworkProxiesHTTPSEnable as String] = 0
      config[kCFNetworkProxiesSOCKSEnable as String] = 0
    }

    activeContext = nil
    logger.info("SystemConfiguration global proxy disabled")
  }

  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 0 }

  func status(for mode: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    guard mode == .global else {
      return TrafficCaptureDriverStatus(isActive: false, summary: "Unavailable", diagnostics: nil)
    }

    guard let context = activeContext else {
      return TrafficCaptureDriverStatus(isActive: false, summary: "Idle", diagnostics: nil)
    }

    let isActive = await TrafficCaptureDependencies.networkInspector.isSystemProxySetToMihomo(
      context.httpPort,
      context.socksPort,
      false,
    )

    return TrafficCaptureDriverStatus(
      isActive: isActive,
      summary: isActive ? "System proxies point to Mihomo" : "Awaiting system proxy update",
      diagnostics: nil,
    )
  }
}

@MainActor
final class NetworkSetupGlobalDriver: SystemProxyDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "networksetup-global"),
    name: "networksetup Global",
    kind: .networkSetup,
    supportedModes: [.global],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.global]
  private let logger = MihoLog.shared.logger(for: .proxySettings)
  private var services: [String] = []
  private var activeContext: TrafficCaptureActivationContext?

  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 1 }

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .global else { return }
    services = try listNetworkServices()

    for service in services {
      try runNetworkSetup(["-setwebproxy", service, "127.0.0.1", "\(context.httpPort)"])
      try runNetworkSetup(["-setsecurewebproxy", service, "127.0.0.1", "\(context.httpPort)"])
      try runNetworkSetup(["-setsocksfirewallproxy", service, "127.0.0.1", "\(context.socksPort)"])
      try runNetworkSetup(["-setwebproxystate", service, "on"])
      try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
      try runNetworkSetup(["-setsocksfirewallproxystate", service, "on"])
      try runNetworkSetup(["-setautoproxystate", service, "off"])
    }

    activeContext = context
    logger.info("networksetup global proxy enabled", metadata: ["services": "\(services.count)"])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .global else { return }

    for service in services {
      do {
        try runNetworkSetup(["-setwebproxystate", service, "off"])
        try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
        try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
      } catch {
        logger.error(
          "Failed to reset network service",
          metadata: ["service": service],
          error: error,
        )
      }
    }

    services.removeAll()
    activeContext = nil
    logger.info("networksetup global proxy disabled")
  }

  func status(for mode: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    guard mode == .global else {
      return TrafficCaptureDriverStatus(isActive: false, summary: "Unavailable", diagnostics: nil)
    }

    guard let context = activeContext else {
      return TrafficCaptureDriverStatus(isActive: false, summary: "Idle", diagnostics: nil)
    }

    let isActive = NetworkDomain.shared.isSystemProxySetToMihomo(
      httpPort: context.httpPort,
      socksPort: context.socksPort,
      strict: false,
    )

    return TrafficCaptureDriverStatus(
      isActive: isActive,
      summary: isActive ? "networksetup configured" : "Awaiting networksetup",
      diagnostics: services.joined(separator: ", "),
    )
  }

  private func listNetworkServices() throws -> [String] {
    let output = try runNetworkSetup(["-listallnetworkservices"])
    let lines = output
      .split(separator: "\n")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    return lines.compactMap { line in
      guard !line.isEmpty, !line.hasPrefix("An asterisk") else { return nil }
      return line.replacingOccurrences(of: "*", with: "")
    }
  }

  @discardableResult
  private func runNetworkSetup(_ args: [String]) throws -> String {
    try TrafficCaptureCommandRunner.run(executable: "/usr/sbin/networksetup", arguments: args)
  }
}

@MainActor
final class SystemConfigurationPACDriver: PacProxyDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "sc-pac"),
    name: "SystemConfiguration PAC",
    kind: .systemConfiguration,
    supportedModes: [.pac],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.pac]
  private var activeURL: URL?
  private let logger = MihoLog.shared.logger(for: .proxySettings)

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .pac, let url = context.pacURL else { return }

    try SystemProxyConfigurator.updateProxyConfiguration { config in
      config[kCFNetworkProxiesProxyAutoConfigEnable as String] = 1
      config[kCFNetworkProxiesProxyAutoConfigURLString as String] = url.absoluteString
      config[kCFNetworkProxiesHTTPEnable as String] = 0
      config[kCFNetworkProxiesHTTPSEnable as String] = 0
      config[kCFNetworkProxiesSOCKSEnable as String] = 0
    }

    activeURL = url
    logger.info("SystemConfiguration PAC enabled", metadata: ["url": url.absoluteString])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .pac else { return }
    try SystemProxyConfigurator.updateProxyConfiguration { config in
      config[kCFNetworkProxiesProxyAutoConfigEnable as String] = 0
      config[kCFNetworkProxiesProxyAutoConfigURLString as String] = ""
    }
    activeURL = nil
    logger.info("SystemConfiguration PAC disabled")
  }

  func status(for mode: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    guard mode == .pac else {
      return TrafficCaptureDriverStatus(isActive: false, summary: "Unavailable", diagnostics: nil)
    }
    return TrafficCaptureDriverStatus(
      isActive: activeURL != nil,
      summary: activeURL != nil ? "PAC configured via SystemConfiguration" : "Idle",
      diagnostics: activeURL?.absoluteString,
    )
  }
}

@MainActor
final class NetworkSetupPACDriver: PacProxyDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "networksetup-pac"),
    name: "networksetup PAC",
    kind: .networkSetup,
    supportedModes: [.pac],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.pac]
  private var services: [String] = []
  private var pacURL: URL?
  private let logger = MihoLog.shared.logger(for: .proxySettings)

  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 1 }

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .pac, let url = context.pacURL else { return }
    services = try listNetworkServices()

    for service in services {
      try runNetworkSetup(["-setautoproxyurl", service, url.absoluteString])
      try runNetworkSetup(["-setautoproxystate", service, "on"])
      try runNetworkSetup(["-setwebproxystate", service, "off"])
      try runNetworkSetup(["-setsecurewebproxystate", service, "off"])
      try runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
    }

    pacURL = url
    logger.info("networksetup PAC enabled", metadata: ["url": url.absoluteString])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .pac else { return }
    for service in services {
      do {
        try runNetworkSetup(["-setautoproxystate", service, "off"])
      } catch {
        logger.error(
          "Failed to disable PAC for service",
          metadata: ["service": service],
          error: error,
        )
      }
    }
    pacURL = nil
    services.removeAll()
    logger.info("networksetup PAC disabled")
  }

  func status(for mode: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    guard mode == .pac else {
      return TrafficCaptureDriverStatus(isActive: false, summary: "Unavailable", diagnostics: nil)
    }
    return TrafficCaptureDriverStatus(
      isActive: pacURL != nil,
      summary: pacURL != nil ? "PAC applied via networksetup" : "Idle",
      diagnostics: pacURL?.absoluteString,
    )
  }

  private func listNetworkServices() throws -> [String] {
    let output = try runNetworkSetup(["-listallnetworkservices"])
    let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    return lines.filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
  }

  @discardableResult
  private func runNetworkSetup(_ args: [String]) throws -> String {
    try TrafficCaptureCommandRunner.run(executable: "/usr/sbin/networksetup", arguments: args)
  }
}

@MainActor
final class ProcessManualDriver: ManualProcessDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "process-manual"),
    name: "Process Controller",
    kind: .process,
    supportedModes: [.manual],
    requiresPrivileges: false,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.manual]
  private var process: Process?
  private let logger = MihoLog.shared.logger(for: .proxy)

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .manual else { return }
    guard process?.isRunning != true else { throw TrafficCaptureDriverError.processAlreadyRunning }

    guard let executableURL = Bundle.main.url(
      forResource: "miho",
      withExtension: nil,
      subdirectory: "Resources",
    ) else {
      throw TrafficCaptureDriverError.executableNotFound
    }

    let resourceDomain = ResourceDomain.shared
    let proc = Process()
    proc.executableURL = executableURL
    proc.arguments = [
      "-d",
      resourceDomain.configDirectory.path,
      "-f",
      resourceDomain.configFilePath.path,
    ]
    proc.environment = context.environment.merging(ProcessInfo.processInfo.environment) { $1 }

    let stdout = Pipe()
    let stderr = Pipe()
    proc.standardOutput = stdout
    proc.standardError = stderr

    stdout.fileHandleForReading.readabilityHandler = { handle in
      if let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty {
        self.logger.debug("mihomo: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
      }
    }

    stderr.fileHandleForReading.readabilityHandler = { handle in
      if let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty {
        self.logger.error("mihomo error: \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
      }
    }

    try proc.run()
    process = proc
    logger.info("Mihomo core started via Process")
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .manual else { return }
    guard let process else { throw TrafficCaptureDriverError.processNotRunning }
    process.terminate()
    process.waitUntilExit()
    self.process = nil
    logger.info("Mihomo core stopped via Process")
  }

  func status(for _: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    let running = process?.isRunning == true
    return TrafficCaptureDriverStatus(
      isActive: running,
      summary: running ? "Process running" : "Idle",
      diagnostics: running ? "PID: \(process?.processIdentifier ?? 0)" : nil,
    )
  }
}

@MainActor
final class PosixSpawnManualDriver: ManualProcessDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "spawn-manual"),
    name: "posix_spawn Controller",
    kind: .spawn,
    supportedModes: [.manual],
    requiresPrivileges: false,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.manual]
  private var childPID: pid_t?
  private let logger = MihoLog.shared.logger(for: .proxy)

  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 1 }

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .manual else {
      return
    }
    guard childPID == nil else {
      throw TrafficCaptureDriverError.processAlreadyRunning
    }

    guard let executableURL = Bundle.main.url(
      forResource: "miho",
      withExtension: nil,
      subdirectory: "Resources",
    ) else {
      throw TrafficCaptureDriverError.executableNotFound
    }

    let resourceDomain = ResourceDomain.shared
    let args = [
      executableURL.path,
      "-d", resourceDomain.configDirectory.path,
      "-f", resourceDomain.configFilePath.path,
    ]

    var environment = ProcessInfo.processInfo.environment
    context.environment.forEach { environment[$0.key] = $0.value }

    let argv = PosixSpawnArgumentBuilder.build(arguments: args)
    let envp = PosixSpawnArgumentBuilder.build(environment: environment)
    defer {
      PosixSpawnArgumentBuilder.destroy(argv)
      PosixSpawnArgumentBuilder.destroy(envp)
    }

    var pid = pid_t()
    let status = posix_spawn(&pid, executableURL.path, nil, nil, argv, envp)
    guard status == 0 else {
      throw TrafficCaptureDriverError.spawnFailed(status)
    }
    childPID = pid
    logger.info("Mihomo core started via posix_spawn", metadata: ["pid": "\(pid)"])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .manual else {
      return
    }
    guard let pid = childPID else {
      throw TrafficCaptureDriverError.processNotRunning
    }
    kill(pid, SIGTERM)
    childPID = nil
    logger.info("Mihomo core terminated via posix_spawn driver")
  }

  func status(for _: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    let running = childPID != nil
    return TrafficCaptureDriverStatus(
      isActive: running,
      summary: running ? "posix_spawn running" : "Idle",
      diagnostics: running ? "PID: \(childPID ?? 0)" : nil,
    )
  }
}

enum PosixSpawnArgumentBuilder {
  static func build(arguments: [String]) -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
    let pointer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
      .allocate(capacity: arguments.count + 1)
    for (index, argument) in arguments.enumerated() {
      pointer[index] = strdup(argument)
    }
    pointer[arguments.count] = nil
    return pointer
  }

  static func build(environment: [String: String])
  -> UnsafeMutablePointer<UnsafeMutablePointer<CChar>?> {
    let pairs = environment.map { "\($0.key)=\($0.value)" }
    return build(arguments: pairs)
  }

  static func destroy(_ pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) {
    var index = 0
    while let cString = pointer[index] {
      free(cString)
      index += 1
    }
    pointer.deallocate()
  }
}

@MainActor
final class TunDeviceDriver: TunnelDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "tun-device"),
    name: "TUN Device",
    kind: .tunDevice,
    supportedModes: [.tun],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.tun]
  private let logger = MihoLog.shared.logger(for: .tunnel)
  private var fileDescriptor: Int32 = -1
  private var interfaceName: String?

  func activate(
    mode: TrafficCaptureMode,
    context _: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .tun else { return }
    guard fileDescriptor == -1 else { throw TrafficCaptureDriverError.processAlreadyRunning }

    var allocated: (fd: Int32, name: String)?
    for index in 0..<16 {
      let path = "/dev/tun\(index)"
      let fd = open(path, O_RDWR)
      if fd >= 0 {
        allocated = (fd, "tun\(index)")
        break
      }
    }

    guard let allocation = allocated else { throw TrafficCaptureDriverError.tunDeviceUnavailable }
    fileDescriptor = allocation.fd
    interfaceName = allocation.name

    try configureInterface(name: allocation.name)
    logger.info("TUN interface configured", metadata: ["interface": allocation.name])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .tun else { return }
    if let interfaceName {
      do {
        _ = try TrafficCaptureCommandRunner.run(
          executable: "/sbin/ifconfig",
          arguments: [interfaceName, "down"],
        )
      } catch {
        logger.error(
          "Failed to bring TUN interface down",
          metadata: ["interface": interfaceName],
          error: error,
        )
      }
    }
    if fileDescriptor >= 0 {
      close(fileDescriptor)
    }
    fileDescriptor = -1
    interfaceName = nil
    logger.info("TUN interface released")
  }

  func status(for _: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    let active = fileDescriptor >= 0
    return TrafficCaptureDriverStatus(
      isActive: active,
      summary: active ? "TUN active" : "Idle",
      diagnostics: interfaceName,
    )
  }

  private func configureInterface(name: String) throws {
    let local = "198.18.0.1"
    let remote = "198.18.0.2"
    _ = try TrafficCaptureCommandRunner.run(
      executable: "/sbin/ifconfig",
      arguments: [name, "inet", local, remote, "up"],
    )

    _ = try TrafficCaptureCommandRunner.run(
      executable: "/sbin/route",
      arguments: ["add", "-net", "198.18.0.0/15", "-interface", name],
    )
  }
}

@MainActor
final class PfTransparentProxyDriver: TunnelDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "pf-transparent"),
    name: "PF Transparent Proxy",
    kind: .pf,
    supportedModes: [.tun],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.tun]
  private let logger = MihoLog.shared.logger(for: .tunnel)
  private var anchorName = "miho/proxy"
  private var rulesFileURL: URL?

  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 2 }

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .tun else { return }

    let interface = NetworkDomain.shared.getPrimaryInterfaceName() ?? "en0"
    let rules = """
    rdr-anchor "miho"
    rdr pass on \(interface) inet proto tcp from any to any -> 127.0.0.1 port \(context.httpPort)
    rdr pass on \(interface) inet proto udp from any to any -> 127.0.0.1 port \(context.socksPort)
    """

    let fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("miho_pf_\(UUID().uuidString).conf")

    try rules.write(to: fileURL, atomically: true, encoding: .utf8)

    do {
      _ = try TrafficCaptureCommandRunner.run(
        executable: "/sbin/pfctl",
        arguments: ["-a", anchorName, "-f", fileURL.path],
      )
      _ = try TrafficCaptureCommandRunner.run(executable: "/sbin/pfctl", arguments: ["-e"])
    } catch {
      throw TrafficCaptureDriverError.pfConfigurationFailed(error.localizedDescription)
    }

    rulesFileURL = fileURL
    logger.info("PF transparent proxy rules loaded", metadata: ["anchor": anchorName])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .tun else { return }

    do {
      _ = try TrafficCaptureCommandRunner.run(
        executable: "/sbin/pfctl",
        arguments: ["-a", anchorName, "-F", "all"],
      )
    } catch {
      logger.error("Failed to flush PF anchor", error: error)
    }

    if let fileURL = rulesFileURL {
      try? FileManager.default.removeItem(at: fileURL)
    }

    logger.info("PF transparent proxy rules removed")
  }

  func status(for _: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    let active = rulesFileURL != nil
    return TrafficCaptureDriverStatus(
      isActive: active,
      summary: active ? "PF anchor loaded" : "Idle",
      diagnostics: anchorName,
    )
  }
}

@MainActor
final class DivertSocketDriver: TunnelDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "divert"),
    name: "Divert Socket",
    kind: .divert,
    supportedModes: [.tun],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.tun]
  private let logger = MihoLog.shared.logger(for: .tunnel)
  private var ruleNumber: Int?

  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 3 }

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .tun else { return }

    let rule = Int.random(in: 50000...60000)
    do {
      _ = try TrafficCaptureCommandRunner.run(
        executable: "/usr/sbin/ipfw",
        arguments: [
          "add",
          "\(rule)",
          "divert",
          "\(context.socksPort)",
          "all",
          "from",
          "any",
          "to",
          "any",
        ],
      )
    } catch {
      throw TrafficCaptureDriverError.divertConfigurationFailed(error.localizedDescription)
    }

    ruleNumber = rule
    logger.info("Divert socket rule installed", metadata: ["rule": "\(rule)"])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .tun else { return }
    if let ruleNumber {
      do {
        _ = try TrafficCaptureCommandRunner.run(
          executable: "/usr/sbin/ipfw",
          arguments: ["delete", "\(ruleNumber)"],
        )
      } catch {
        logger.error("Failed to delete divert rule", metadata: ["rule": "\(ruleNumber)"])
      }
    }
    ruleNumber = nil
    logger.info("Divert socket rule removed")
  }

  func status(for _: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    let active = ruleNumber != nil
    return TrafficCaptureDriverStatus(
      isActive: active,
      summary: active ? "Divert rule active" : "Idle",
      diagnostics: ruleNumber.map { "Rule \($0)" },
    )
  }
}

@MainActor
final class RoutingRuleDriver: TunnelDriver {
  let descriptor = TrafficCaptureDriverDescriptor(
    id: TrafficCaptureDriverID(rawValue: "routing"),
    name: "Transparent Routing",
    kind: .transparentRouting,
    supportedModes: [.tun],
    requiresPrivileges: true,
  )

  let supportedModes: Set<TrafficCaptureMode> = [.tun]
  private let logger = MihoLog.shared.logger(for: .tunnel)
  private var routes: [String] = []

  func fallbackPriority(for _: TrafficCaptureMode) -> Int { 4 }

  func activate(
    mode: TrafficCaptureMode,
    context: TrafficCaptureActivationContext,
  ) async throws {
    guard mode == .tun else { return }

    let cidrs = context.environment["MIHOMO_REDIRECT_CIDRS"]?
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) } ?? [
        "0.0.0.0/1",
        "128.0.0.0/1",
      ]
    for cidr in cidrs {
      do {
        _ = try TrafficCaptureCommandRunner.run(
          executable: "/sbin/route",
          arguments: ["add", "-net", cidr, "127.0.0.1"],
        )
        routes.append(cidr)
      } catch {
        throw TrafficCaptureDriverError.routingConfigurationFailed(error.localizedDescription)
      }
    }

    logger.info("Transparent routing rules installed", metadata: ["routes": "\(routes.count)"])
  }

  func deactivate(mode: TrafficCaptureMode) async throws {
    guard mode == .tun else { return }
    for cidr in routes {
      do {
        _ = try TrafficCaptureCommandRunner.run(
          executable: "/sbin/route",
          arguments: ["delete", "-net", cidr],
        )
      } catch {
        logger.error("Failed to delete route", metadata: ["cidr": cidr])
      }
    }
    routes.removeAll()
    logger.info("Transparent routing rules removed")
  }

  func status(for _: TrafficCaptureMode) async -> TrafficCaptureDriverStatus {
    let active = !routes.isEmpty
    return TrafficCaptureDriverStatus(
      isActive: active,
      summary: active ? "Routing overrides active" : "Idle",
      diagnostics: routes.joined(separator: ", "),
    )
  }
}

// swiftlint:enable conditional_returns_on_newline
