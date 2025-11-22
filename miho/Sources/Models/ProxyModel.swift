import Foundation
import SwiftData

struct ProxyModel: Codable {
  enum CodingKeys: String, CodingKey {
    case port
    case socksPort = "socks-port"
    case mixedPort = "mixed-port"
    case allowLan = "allow-lan"
    case mode
    case logLevel = "log-level"
    case tun
  }

  var port: Int?
  var socksPort: Int?
  var mixedPort: Int?
  var allowLan: Bool
  var mode: String?
  var logLevel: String?
  var tun: TunConfig?

  var httpPort: Int {
    mixedPort ?? port ?? 7890
  }

  var effectiveSocksPort: Int {
    mixedPort ?? socksPort ?? 7891
  }

  var tunEnabled: Bool {
    tun?.enable ?? false
  }

  var tunDNS: String? {
    tun?.dnsHijack.first
  }
}

struct TunConfig: Codable {
  var enable: Bool
  var stack: String?
  var dnsHijack: [String]
  var autoRoute: Bool
  var autoDetectInterface: Bool

  enum CodingKeys: String, CodingKey {
    case enable
    case stack
    case dnsHijack = "dns-hijack"
    case autoRoute = "auto-route"
    case autoDetectInterface = "auto-detect-interface"
  }

  init(
    enable: Bool = false,
    stack: String? = nil,
    dnsHijack: [String] = [],
    autoRoute: Bool = false,
    autoDetectInterface: Bool = false,
  ) {
    self.enable = enable
    self.stack = stack
    self.dnsHijack = dnsHijack
    self.autoRoute = autoRoute
    self.autoDetectInterface = autoDetectInterface
  }
}

@Model
final class ProxyProfile {
  @Attribute(.unique)
  var id: UUID
  var name: String
  var url: String?
  var isRemote: Bool
  var lastUpdated: Date?
  var isActive: Bool

  init(name: String, url: String? = nil, isRemote: Bool = false) {
    id = UUID()
    self.name = name
    self.url = url
    self.isRemote = isRemote
    lastUpdated = Date()
    isActive = false
  }
}

@Model
final class ProxyGroup {
  @Attribute(.unique)
  var id: UUID
  var name: String
  var type: String
  var selectedProxy: String?

  init(name: String, type: String) {
    id = UUID()
    self.name = name
    self.type = type
  }
}
