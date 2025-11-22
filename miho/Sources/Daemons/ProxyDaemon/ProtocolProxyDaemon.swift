import Foundation

@objc
public protocol ProtocolProxyDaemon {
  func getVersion(reply: @escaping @Sendable (String) -> Void)
  func enableProxy(
    port: Int,
    socksPort: Int,
    pac: String?,
    filterInterface: Bool,
    ignoreList: [String],
    reply: @escaping @Sendable ((any Error)?) -> Void
  )
  func disableProxy(filterInterface: Bool, reply: @escaping @Sendable ((any Error)?) -> Void)
  func restoreProxy(
    currentPort: Int,
    socksPort: Int,
    info: [String: Any],
    filterInterface: Bool,
    reply: @escaping @Sendable ((any Error)?) -> Void
  )
  func getCurrentProxySetting(reply: @escaping @Sendable ([String: Any]) -> Void)
  func startMihomo(
    path: String,
    confPath: String,
    confFilePath: String,
    confJSON: String,
    reply: @escaping @Sendable ((any Error)?) -> Void
  )
  func stopMihomo(reply: @escaping @Sendable ((any Error)?) -> Void)
  func getUsedPorts(reply: @escaping @Sendable (String?) -> Void)
  func updateTun(state: Bool, dns: String, reply: @escaping @Sendable ((any Error)?) -> Void)
  func flushDnsCache(reply: @escaping @Sendable ((any Error)?) -> Void)
}
