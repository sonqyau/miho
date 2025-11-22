import Foundation

struct SnapshotModels { }

struct MihomoSnapshot {
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

  init(_ state: MihomoDomain.State) {
    trafficHistory = state.trafficHistory
    currentTraffic = state.currentTraffic
    connections = state.connections
    memoryUsage = state.memoryUsage
    version = state.version
    logs = state.logs
    proxies = state.proxies
    groups = state.groups
    rules = state.rules
    proxyProviders = state.proxyProviders
    ruleProviders = state.ruleProviders
    config = state.config
    isConnected = state.isConnected
  }
}

struct ProxySnapshot {
  var isSystemProxyEnabled: Bool
  var isTunModeEnabled: Bool
  var currentMode: ProxyMode
  var allowLAN: Bool
  var httpPort: Int
  var socksPort: Int
  var mixedPort: Int?
  var statusSummary: String

  init(_ state: ProxyDomain.State) {
    isSystemProxyEnabled = state.isSystemProxyEnabled
    isTunModeEnabled = state.isTunModeEnabled
    currentMode = state.currentMode
    allowLAN = state.allowLAN
    httpPort = state.httpPort
    socksPort = state.socksPort
    mixedPort = state.mixedPort
    statusSummary = state.statusSummary
  }
}

struct TrafficCaptureSnapshot {
  var selectedMode: TrafficCaptureMode
  var activeDriver: TrafficCaptureDriverID?
  var preferredDrivers: [TrafficCaptureMode: TrafficCaptureDriverID]
  var autoFallbackEnabled: Bool
  var isActivating: Bool
  var isActive: Bool
  var availableDrivers: [TrafficCaptureMode: [TrafficCaptureDriverDescriptor]]
  var lastErrorDescription: String?

  init(_ state: TrafficCaptureDomain.State) {
    selectedMode = state.selectedMode
    activeDriver = state.activeDriver
    preferredDrivers = state.preferredDrivers
    autoFallbackEnabled = state.autoFallbackEnabled
    isActivating = state.isActivating
    isActive = state.isActive
    availableDrivers = state.availableDrivers
    lastErrorDescription = state.lastErrorDescription
  }
}

struct DaemonSnapshot: Equatable {
  var isRegistered: Bool
  var requiresApproval: Bool

  init(_ state: DaemonDomain.State) {
    isRegistered = state.isRegistered
    requiresApproval = state.requiresApproval
  }
}

struct LaunchSnapshot {
  var isEnabled: Bool
  var requiresApproval: Bool

  init(_ state: LaunchAtLoginManager.State) {
    isEnabled = state.isEnabled
    requiresApproval = state.requiresApproval
  }
}
