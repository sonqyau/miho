import Foundation
import OSLog

enum DNSError: Error, LocalizedError {
  case failedToSetDNS
  case failedToFlushCache

  var userFriendlyMessage: String {
    errorDescription ?? "DNS error"
  }

  var errorDescription: String? {
    switch self {
    case .failedToSetDNS:
      "Unable to apply DNS configuration."

    case .failedToFlushCache:
      "Unable to flush the DNS cache."
    }
  }
}

final class DNSProxyDaemon {
  @MainActor static let shared = DNSProxyDaemon()

  private let logger = Logger(subsystem: "com.swift.miho.daemon", category: "dns")
  private var customDNS: String = ""

  private init() {}

  func updateTun(enabled: Bool, dnsServer: String) throws {
    customDNS = dnsServer

    if enabled {
      try hijackDNS()
    } else {
      try revertDNS()
    }

    try flushCache()
  }

  func hijackDNS() throws {
    guard !customDNS.isEmpty else { return }

    logger.info("Applying custom DNS server: \(self.customDNS)")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    task.arguments = ["-setdnsservers", "Wi-Fi", customDNS]

    do {
      try task.run()
      task.waitUntilExit()

      if task.terminationStatus != 0 {
        throw DNSError.failedToSetDNS
      }
    } catch {
      logger.error("Failed to hijack DNS: \(error.localizedDescription)")
      throw DNSError.failedToSetDNS
    }
  }

  func revertDNS() throws {
    logger.info("Restoring system DNS configuration")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
    task.arguments = ["-setdnsservers", "Wi-Fi", "Empty"]

    do {
      try task.run()
      task.waitUntilExit()

      if task.terminationStatus != 0 {
        throw DNSError.failedToSetDNS
      }
    } catch {
      logger.error("Failed to revert DNS: \(error.localizedDescription)")
      throw DNSError.failedToSetDNS
    }
  }

  func flushCache() throws {
    logger.info("Clearing DNS resolver cache")

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
    task.arguments = ["-flushcache"]

    do {
      try task.run()
      task.waitUntilExit()

      let mdnsTask = Process()
      mdnsTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
      mdnsTask.arguments = ["-HUP", "mDNSResponder"]
      try mdnsTask.run()
      mdnsTask.waitUntilExit()

    } catch {
      logger.error("DNS cache flush failed: \(error.localizedDescription)")
      throw DNSError.failedToFlushCache
    }
  }
}
