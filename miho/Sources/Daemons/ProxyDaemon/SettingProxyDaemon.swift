import Foundation
import OSLog
import SystemConfiguration

enum ProxySettingError: Error, LocalizedError {
  case failedToGetPreferences
  case failedToSetPreferences
  case failedToCommit

  var userFriendlyMessage: String {
    errorDescription ?? "Proxy settings error"
  }

  var errorDescription: String? {
    switch self {
    case .failedToGetPreferences:
      "Unable to read current network proxy configuration."

    case .failedToSetPreferences:
      "Unable to update network proxy configuration."

    case .failedToCommit:
      "Unable to apply network proxy changes to the system."
    }
  }
}

final class SettingProxyDaemon {
  @MainActor static let shared = SettingProxyDaemon()
  private let logger = Logger(subsystem: "com.swift.miho.daemon", category: "proxy-settings")

  private init() {}

  func enableProxy(
    httpPort: Int, socksPort: Int, pacURL: String?, filterInterface: Bool, ignoreList: [String]
  ) throws {
    logger.info("Enabling system proxy: HTTP(S)=\(httpPort), SOCKS=\(socksPort)")

    guard let prefRef = SCPreferencesCreate(nil, "miho" as CFString, nil) else {
      logger.error("Unable to create network preferences session")
      throw ProxySettingError.failedToGetPreferences
    }

    guard let sets = SCPreferencesGetValue(prefRef, kSCPrefNetworkServices) as? [String: Any] else {
      throw ProxySettingError.failedToGetPreferences
    }

    for (key, value) in sets {
      guard let service = value as? [String: Any],
        let hardware = service["Interface"] as? [String: Any],
        let deviceType = hardware["Type"] as? String
      else {
        continue
      }

      if filterInterface && !shouldConfigureInterface(deviceType) {
        continue
      }

      let servicePath = "/\(kSCPrefNetworkServices)/\(key)/\(kSCEntNetProxies)" as CFString
      guard let proxies = SCPreferencesPathGetValue(prefRef, servicePath) as? [String: Any] else {
        continue
      }

      var newProxies = proxies

      newProxies[kCFNetworkProxiesHTTPEnable as String] = 1
      newProxies[kCFNetworkProxiesHTTPProxy as String] = "127.0.0.1"
      newProxies[kCFNetworkProxiesHTTPPort as String] = httpPort

      newProxies[kCFNetworkProxiesHTTPSEnable as String] = 1
      newProxies[kCFNetworkProxiesHTTPSProxy as String] = "127.0.0.1"
      newProxies[kCFNetworkProxiesHTTPSPort as String] = httpPort

      newProxies[kCFNetworkProxiesSOCKSEnable as String] = 1
      newProxies[kCFNetworkProxiesSOCKSProxy as String] = "127.0.0.1"
      newProxies[kCFNetworkProxiesSOCKSPort as String] = socksPort

      if !ignoreList.isEmpty {
        newProxies[kCFNetworkProxiesExceptionsList as String] = ignoreList
      }

      if let pac = pacURL, !pac.isEmpty {
        newProxies[kCFNetworkProxiesProxyAutoConfigEnable as String] = 1
        newProxies[kCFNetworkProxiesProxyAutoConfigURLString as String] = pac
      }

      guard SCPreferencesPathSetValue(prefRef, servicePath, newProxies as CFDictionary) else {
        throw ProxySettingError.failedToSetPreferences
      }
    }

    guard SCPreferencesCommitChanges(prefRef),
      SCPreferencesApplyChanges(prefRef)
    else {
      logger.error("Failed to apply proxy configuration changes")
      throw ProxySettingError.failedToCommit
    }

    logger.info("System proxy configuration enabled")
  }

  func disableProxy(filterInterface: Bool) throws {
    logger.info("Disabling system proxy configuration")
    guard let prefRef = SCPreferencesCreate(nil, "miho" as CFString, nil) else {
      throw ProxySettingError.failedToGetPreferences
    }

    guard let sets = SCPreferencesGetValue(prefRef, kSCPrefNetworkServices) as? [String: Any] else {
      throw ProxySettingError.failedToGetPreferences
    }

    for (key, value) in sets {
      guard let service = value as? [String: Any],
        let hardware = service["Interface"] as? [String: Any],
        let deviceType = hardware["Type"] as? String
      else {
        continue
      }

      if filterInterface && !shouldConfigureInterface(deviceType) {
        continue
      }

      let servicePath = "/\(kSCPrefNetworkServices)/\(key)/\(kSCEntNetProxies)" as CFString
      guard let proxies = SCPreferencesPathGetValue(prefRef, servicePath) as? [String: Any] else {
        continue
      }

      var newProxies = proxies

      newProxies[kCFNetworkProxiesHTTPEnable as String] = 0
      newProxies[kCFNetworkProxiesHTTPSEnable as String] = 0
      newProxies[kCFNetworkProxiesSOCKSEnable as String] = 0
      newProxies[kCFNetworkProxiesProxyAutoConfigEnable as String] = 0

      guard SCPreferencesPathSetValue(prefRef, servicePath, newProxies as CFDictionary) else {
        throw ProxySettingError.failedToSetPreferences
      }
    }

    guard SCPreferencesCommitChanges(prefRef),
      SCPreferencesApplyChanges(prefRef)
    else {
      logger.error("Failed to apply proxy disable changes")
      throw ProxySettingError.failedToCommit
    }

    logger.info("System proxy configuration disabled")
  }

  func restoreProxy(currentPort: Int, socksPort: Int, info: [String: Any], filterInterface: Bool)
    throws
  {
    logger.info("Restoring system proxy configuration")
    try enableProxy(
      httpPort: currentPort,
      socksPort: socksPort,
      pacURL: info["PACUrl"] as? String,
      filterInterface: filterInterface,
      ignoreList: info["ExceptionsList"] as? [String] ?? []
    )
  }

  func getCurrentProxySettings() -> [String: Any] {
    guard let prefRef = SCPreferencesCreate(nil, "miho" as CFString, nil),
      let sets = SCPreferencesGetValue(prefRef, kSCPrefNetworkServices) as? [String: Any]
    else {
      return [:]
    }

    var result: [String: Any] = [:]

    for (key, value) in sets {
      guard value is [String: Any] else { continue }
      let servicePath = "/\(kSCPrefNetworkServices)/\(key)/\(kSCEntNetProxies)" as CFString
      if let proxies = SCPreferencesPathGetValue(prefRef, servicePath) as? [String: Any] {
        result = proxies
        break
      }
    }

    return result
  }

  private func shouldConfigureInterface(_ type: String) -> Bool {
    type == "Ethernet" || type == "AirPort" || type == "Wi-Fi"
  }
}
