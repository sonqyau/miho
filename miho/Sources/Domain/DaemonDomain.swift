import Combine
import ErrorKit
import Foundation
import Observation
import OSLog
import ServiceManagement

@MainActor
@Observable
final class DaemonDomain {
  struct State: Equatable {
    var isRegistered: Bool
    var requiresApproval: Bool
  }

  static let shared = DaemonDomain()

  var isRegistered = false {
    didSet {
      if isRegistered != oldValue {
        emitState()
      }
    }
  }

  var requiresApproval = false {
    didSet {
      if requiresApproval != oldValue {
        emitState()
      }
    }
  }

  var state: State {
    State(isRegistered: isRegistered, requiresApproval: requiresApproval)
  }

  private let logger = MihoLog.shared.logger(for: .daemon)
  private let daemonPlistName = "com.swift.miho.daemon"
  private var connection: NSXPCConnection?
  private let stateSubject: CurrentValueSubject<State, Never>

  private init() {
    stateSubject = CurrentValueSubject(State(isRegistered: false, requiresApproval: false))
    checkStatus()
  }

  func checkStatus() {
    let status = SMAppService.daemon(plistName: daemonPlistName).status

    switch status {
    case .enabled:
      isRegistered = true
      requiresApproval = false

    case .requiresApproval:
      isRegistered = false
      requiresApproval = true

    case .notRegistered, .notFound:
      isRegistered = false
      requiresApproval = false

    @unknown default:
      isRegistered = false
      requiresApproval = false
    }

    emitState()
  }

  func register() async throws(DaemonError) {
    do {
      try SMAppService.daemon(plistName: daemonPlistName).register()
      checkStatus()
    } catch {
      throw DaemonError.registrationFailed(error)
    }
  }

  func unregister() async throws(DaemonError) {
    do {
      try await SMAppService.daemon(plistName: daemonPlistName).unregister()
      checkStatus()
    } catch {
      throw DaemonError.unregistrationFailed(error)
    }
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func getConnection() throws -> NSXPCConnection {
    if let existing = connection {
      return existing
    }

    let conn = NSXPCConnection(machServiceName: daemonPlistName, options: .privileged)
    conn.remoteObjectInterface = NSXPCInterface(with: (any ProxyDaemonProtocol).self)

    conn.invalidationHandler = { [weak self] in
      Task { @MainActor in
        self?.connection = nil
        self?.logger.debug("XPC connection invalidated")
      }
    }

    conn.interruptionHandler = { [weak self] in
      Task { @MainActor in
        self?.connection = nil
        self?.logger.notice("XPC connection interrupted")
      }
    }

    conn.resume()
    connection = conn

    return conn
  }

  private func getDaemon() throws -> any ProxyDaemonProtocol {
    let conn = try getConnection()

    guard
      let daemon = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
        Task { @MainActor in
          self?.logger.error(
            "Received XPC error", metadata: ["message": error.localizedDescription],
          )
        }
      }) as? any ProxyDaemonProtocol
    else {
      throw DaemonError.connectionFailed
    }

    return daemon
  }

  func resetConnection() {
    connection?.invalidate()
    connection = nil
    logger.debug("XPC connection reset")
  }

  func statePublisher() -> AnyPublisher<State, Never> {
    stateSubject
      .receive(on: RunLoop.main)
      .eraseToAnyPublisher()
  }

  private func emitState() {
    stateSubject.send(state)
  }

  func getVersion() async throws -> String {
    let daemon = try getDaemon()

    return try await withCheckedThrowingContinuation { continuation in
      daemon.getVersion { version in
        continuation.resume(returning: version)
      }
    }
  }

  func enableProxy(
    httpPort: Int,
    socksPort: Int,
    pacUrl: String? = nil,
    filterInterface: Bool = true,
    ignoreList: [String] = [],
  ) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      try? getDaemon().enableProxy(
        httpPort: httpPort,
        socksPort: socksPort,
        pacUrl: pacUrl,
        filterInterface: filterInterface,
        ignoreList: ignoreList,
      ) { error in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume()
        }
      }
    }
  }

  func disableProxy(filterInterface: Bool = true) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      try? getDaemon().disableProxy(filterInterface: filterInterface) { error in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume()
        }
      }
    }
  }

  func getCurrentProxySettings() async throws -> [String: Any] {
    try await withCheckedThrowingContinuation { cont in
      try? getDaemon().getCurrentProxySetting { settings in
        nonisolated(unsafe) let copy = settings
        cont.resume(returning: copy)
      }
    }
  }

  func startMihomo(
    executablePath: String,
    configPath: String,
    configFilePath: String,
    configJSON: String = "",
  ) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      try? getDaemon().startMihomo(
        executablePath: executablePath,
        configPath: configPath,
        configFilePath: configFilePath,
        configJSON: configJSON,
      ) { error in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume()
        }
      }
    }
  }

  func stopMihomo() async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      try? getDaemon().stopMihomo { error in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume()
        }
      }
    }
  }

  func getUsedPorts() async throws -> String? {
    try await withCheckedThrowingContinuation { cont in
      try? getDaemon().getUsedPorts { ports in
        let copy = ports
        cont.resume(returning: copy)
      }
    }
  }

  func updateTun(enabled: Bool, dnsServer: String) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      try? getDaemon().updateTun(enabled: enabled, dnsServer: dnsServer) { error in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume()
        }
      }
    }
  }

  func flushDnsCache() async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      try? getDaemon().flushDnsCache { error in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume()
        }
      }
    }
  }
}

// swiftlint:disable function_parameter_count
@objc
protocol ProxyDaemonProtocol {
  func getVersion(reply: @escaping @Sendable (String) -> Void)
  func enableProxy(
    httpPort: Int,
    socksPort: Int,
    pacUrl: String?,
    filterInterface: Bool,
    ignoreList: [String],
    reply: @escaping @Sendable (((any Error)?) -> Void),
  )
  func disableProxy(
    filterInterface: Bool,
    reply: @escaping @Sendable (((any Error)?) -> Void),
  )
  func restoreProxy(
    currentPort: Int,
    socksPort: Int,
    info: [String: Any],
    filterInterface: Bool,
    reply: @escaping @Sendable (((any Error)?) -> Void),
  )
  func getCurrentProxySetting(reply: @escaping @Sendable ([String: Any]) -> Void)
  func startMihomo(
    executablePath: String,
    configPath: String,
    configFilePath: String,
    configJSON: String,
    reply: @escaping @Sendable (((any Error)?) -> Void),
  )
  func stopMihomo(
    reply: @escaping @Sendable (((any Error)?) -> Void),
  )
  func getUsedPorts(reply: @escaping @Sendable (String?) -> Void)
  func updateTun(
    enabled: Bool,
    dnsServer: String,
    reply: @escaping @Sendable (((any Error)?) -> Void),
  )
  func flushDnsCache(
    reply: @escaping @Sendable (((any Error)?) -> Void),
  )
}

// swiftlint:enable function_parameter_count

enum DaemonError: Error, Throwable {
  case notRegistered
  case requiresApproval
  case notFound
  case connectionFailed
  case registrationFailed(any Error)
  case unregistrationFailed(any Error)
}

extension DaemonError: LocalizedError {
  var userFriendlyMessage: String {
    errorDescription ?? "Daemon error"
  }

  var errorDescription: String? {
    switch self {
    case .notRegistered:
      "The helper tool is not installed."

    case .requiresApproval:
      "The helper tool requires approval in System Settings."

    case .notFound:
      "Unable to locate the helper tool."

    case .connectionFailed:
      "Failed to communicate with the helper tool."

    case let .registrationFailed(error):
      "Failed to install the helper tool: \(error.localizedDescription)"

    case let .unregistrationFailed(error):
      "Failed to uninstall the helper tool: \(error.localizedDescription)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .notRegistered:
      "Select Install Helper to install the daemon, then try again."

    case .requiresApproval:
      "Open System Settings > Privacy & Security > Developer Tools, then allow \"miho\"."

    case .notFound:
      "Reinstall or register the helper tool from the Settings page."

    case .connectionFailed:
      "Restart the helper tool from Settings, or reinstall it if the issue persists."

    case .registrationFailed:
      "Approve the helper tool in System Settings, then try again."

    case .unregistrationFailed:
      "Approve the helper tool in System Settings, then try uninstalling again."
    }
  }
}
