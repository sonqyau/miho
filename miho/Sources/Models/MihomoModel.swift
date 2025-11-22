import Foundation

struct ClashConfig: Codable {
  let port: Int?
  let socksPort: Int?
  let mixedPort: Int?
  let allowLan: Bool
  let bindAddress: String?
  let mode: String?
  let logLevel: String?
  let ipv6: Bool
  let externalController: String?
  let externalUI: String?
  let secret: String?

  enum CodingKeys: String, CodingKey {
    case port
    case socksPort = "socks-port"
    case mixedPort = "mixed-port"
    case allowLan = "allow-lan"
    case bindAddress = "bind-address"
    case mode
    case logLevel = "log-level"
    case ipv6
    case externalController = "external-controller"
    case externalUI = "external-ui"
    case secret
  }

  init(
    port: Int? = nil,
    socksPort: Int? = nil,
    mixedPort: Int? = nil,
    allowLan: Bool = false,
    bindAddress: String? = nil,
    mode: String? = nil,
    logLevel: String? = nil,
    ipv6: Bool = false,
    externalController: String? = nil,
    externalUI: String? = nil,
    secret: String? = nil,
  ) {
    self.port = port
    self.socksPort = socksPort
    self.mixedPort = mixedPort
    self.allowLan = allowLan
    self.bindAddress = bindAddress
    self.mode = mode
    self.logLevel = logLevel
    self.ipv6 = ipv6
    self.externalController = externalController
    self.externalUI = externalUI
    self.secret = secret
  }
}

struct ConfigUpdateRequest: Codable {
  let path: String?
  let payload: String?
}

struct ProxiesResponse: Codable {
  let proxies: [String: ProxyInfo]
}

struct ProxyInfo: Codable {
  let name: String
  let type: String
  let udp: Bool
  let now: String?
  let all: [String]
  let history: [ProxyDelay]

  init(
    name: String,
    type: String,
    udp: Bool = false,
    now: String? = nil,
    all: [String] = [],
    history: [ProxyDelay] = [],
  ) {
    self.name = name
    self.type = type
    self.udp = udp
    self.now = now
    self.all = all
    self.history = history
  }
}

struct ProxyDelay: Codable {
  let time: Date
  let delay: Int
}

struct ProxyDelayTest: Codable {
  let delay: Int
}

struct ProxySelectRequest: Codable {
  let name: String
}

struct GroupsResponse: Codable {
  let proxies: [String: GroupInfo]
}

struct GroupInfo: Codable {
  let name: String
  let type: String
  let now: String?
  let all: [String]

  init(
    name: String,
    type: String,
    now: String? = nil,
    all: [String] = [],
  ) {
    self.name = name
    self.type = type
    self.now = now
    self.all = all
  }
}

struct RulesResponse: Codable {
  let rules: [RuleInfo]
}

struct RuleInfo: Codable {
  let type: String
  let payload: String
  let proxy: String
}

struct ProxyProvidersResponse: Codable {
  let providers: [String: ProxyProviderInfo]
}

struct ProxyProviderInfo: Codable {
  let name: String
  let type: String
  let vehicleType: String
  let proxies: [ProxyInfo]
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case name, type, proxies
    case vehicleType
    case updatedAt
  }
}

struct RuleProvidersResponse: Codable {
  let providers: [String: RuleProviderInfo]
}

struct RuleProviderInfo: Codable {
  let name: String
  let type: String
  let vehicleType: String
  let behavior: String
  let ruleCount: Int
  let updatedAt: Date?

  enum CodingKeys: String, CodingKey {
    case name, type, behavior
    case vehicleType
    case ruleCount
    case updatedAt
  }
}

struct LogMessage: Codable, Identifiable {
  let id = UUID()
  let type: String
  let payload: String

  enum CodingKeys: String, CodingKey {
    case type, payload
  }
}

struct DNSQueryRequest: Codable {
  let name: String
  let type: String
}

struct DNSQueryResponse: Codable {
  struct DNSQuestion: Codable {
    let name: String
    let qtype: Int
    let qclass: Int
  }

  struct DNSAnswer: Codable {
    let name: String
    let type: Int
    let ttl: Int
    let data: String
  }

  let status: Int
  let question: [DNSQuestion]
  let answer: [DNSAnswer]

  init(
    status: Int,
    question: [DNSQuestion],
    answer: [DNSAnswer] = [],
  ) {
    self.status = status
    self.question = question
    self.answer = answer
  }
}

struct APIError: Codable, Error {
  let message: String
}

struct MihomoModel { }
