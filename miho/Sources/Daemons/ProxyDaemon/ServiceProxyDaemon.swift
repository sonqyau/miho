import AppKit
import Foundation
import OSLog
import SystemConfiguration

final class ServiceProxyDaemon: NSObject, ProtocolProxyDaemon, NSXPCListenerDelegate {
  private let listener: NSXPCListener
  private var connections = [NSXPCConnection]()
  private let logger = Logger(subsystem: "com.swift.miho.daemon", category: "service")

  private var mihomoTask: Process?
  private let allowedBundleIdentifier = "com.swift.miho"

  override init() {
    listener = NSXPCListener(machServiceName: "com.swift.miho.daemon")
    super.init()
    listener.delegate = self
  }

  func run() {
    listener.resume()
    logger.info("Proxy daemon listener started")
    RunLoop.current.run()
  }

  func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection)
    -> Bool
  {
    guard isValidConnection(newConnection) else {
      logger.error("Rejected connection from unauthorized client process")
      return false
    }

    newConnection.exportedInterface = NSXPCInterface(with: (any ProtocolProxyDaemon).self)
    newConnection.exportedObject = self

    newConnection.invalidationHandler = { [weak self] in
      guard let self = self,
        let index = self.connections.firstIndex(of: newConnection)
      else { return }
      self.connections.remove(at: index)
      self.logger.debug("Client connection invalidated; remaining connections: \(self.connections.count)")
    }

    self.connections.append(newConnection)
    newConnection.resume()
    logger.debug("Accepted client connection; active connections: \(self.connections.count)")

    return true
  }

  private func isValidConnection(_ connection: NSXPCConnection) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: connection.processIdentifier),
      let bundleIdentifier = app.bundleIdentifier
    else {
      return false
    }
    return bundleIdentifier == allowedBundleIdentifier
  }

  func getVersion(reply: @escaping @Sendable (String) -> Void) {
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    reply(version)
  }

  nonisolated func enableProxy(
    port: Int, socksPort: Int, pac: String?, filterInterface: Bool, ignoreList: [String],
    reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Enabling system proxy: HTTP(S)=\(port), SOCKS=\(socksPort)")
    Task { @MainActor in
      do {
        try SettingProxyDaemon.shared.enableProxy(
          httpPort: port,
          socksPort: socksPort,
          pacURL: pac,
          filterInterface: filterInterface,
          ignoreList: ignoreList
        )
        reply(nil)
      } catch {
        log.error("Failed to enable proxy: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func disableProxy(
    filterInterface: Bool, reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Disabling system proxy")
    Task { @MainActor in
      do {
        try SettingProxyDaemon.shared.disableProxy(filterInterface: filterInterface)
        reply(nil)
      } catch {
        log.error("Failed to disable proxy: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func restoreProxy(
    currentPort: Int, socksPort: Int, info: [String: Any], filterInterface: Bool,
    reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Restoring system proxy configuration")
    nonisolated(unsafe) let proxyInfo = info
    Task { @MainActor in
      do {
        try SettingProxyDaemon.shared.restoreProxy(
          currentPort: currentPort,
          socksPort: socksPort,
          info: proxyInfo,
          filterInterface: filterInterface
        )
        reply(nil)
      } catch {
        log.error("Failed to restore proxy: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func getCurrentProxySetting(reply: @escaping @Sendable ([String: Any]) -> Void) {
    Task { @MainActor in
      let settings = SettingProxyDaemon.shared.getCurrentProxySettings()
      reply(settings)
    }
  }

  nonisolated func startMihomo(
    path: String, confPath: String, confFilePath: String, confJSON: String,
    reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Starting Mihomo core process")
    Task { @MainActor in
      do {
        try TaskProxyDaemon.shared.start(
          executablePath: path,
          configPath: confPath,
          configFilePath: confFilePath,
          configJSON: confJSON
        )
        reply(nil)
      } catch {
        log.error("Failed to start Mihomo: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func stopMihomo(reply: @escaping @Sendable ((any Error)?) -> Void) {
    let log = logger
    log.info("Stopping Mihomo core process")
    Task { @MainActor in
      TaskProxyDaemon.shared.stop()
      reply(nil)
    }
  }

  nonisolated func getUsedPorts(reply: @escaping @Sendable (String?) -> Void) {
    Task { @MainActor in
      let ports = TaskProxyDaemon.shared.getUsedPorts()
      reply(ports)
    }
  }

  nonisolated func updateTun(
    state: Bool, dns: String, reply: @escaping @Sendable ((any Error)?) -> Void
  ) {
    let log = logger
    log.info("Updating TUN state=\(state) dnsServer=\(dns)")
    Task { @MainActor in
      do {
        try DNSProxyDaemon.shared.updateTun(enabled: state, dnsServer: dns)
        reply(nil)
      } catch {
        log.error("Failed to update TUN: \(error.localizedDescription)")
        reply(error)
      }
    }
  }

  nonisolated func flushDnsCache(reply: @escaping @Sendable ((any Error)?) -> Void) {
    let log = logger
    log.info("Clearing DNS resolver cache")
    Task { @MainActor in
      do {
        try DNSProxyDaemon.shared.flushCache()
        reply(nil)
      } catch {
        log.error("Failed to flush DNS cache: \(error.localizedDescription)")
        reply(error)
      }
    }
  }
}
