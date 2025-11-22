import ComposableArchitecture
import Factory

struct SettingsDependencies { }

enum ProxyServiceKey: DependencyKey {
  static let liveValue = ProxyServiceDependency(service: Container.shared.proxyService())
}

enum TrafficCaptureServiceKey: DependencyKey {
  static let liveValue = TrafficCaptureServiceDependency(service: Container.shared
    .trafficCaptureService())
}

enum DaemonServiceKey: DependencyKey {
  static let liveValue = DaemonServiceDependency(service: Container.shared.daemonService())
}

enum LaunchAtLoginServiceKey: DependencyKey {
  static let liveValue = LaunchAtLoginServiceDependency(service: Container.shared
    .launchAtLoginService())
}

enum SettingsServiceKey: DependencyKey {
  static let liveValue = SettingsServiceDependency(service: Container.shared.settingsService())
}

enum PersistenceServiceKey: DependencyKey {
  static let liveValue = PersistenceServiceDependency(service: Container.shared
    .persistenceService())
}

enum NetworkServiceKey: DependencyKey {
  static let liveValue = NetworkServiceDependency(service: Container.shared.networkService())
}

enum ResourceServiceKey: DependencyKey {
  static let liveValue = ResourceServiceDependency(service: Container.shared.resourceService())
}

enum MihomoServiceKey: DependencyKey {
  static let liveValue = MihomoServiceDependency(service: Container.shared.mihomoService())
}

extension DependencyValues {
  var proxyService: ProxyService {
    get { self[ProxyServiceKey.self].service }
    set { self[ProxyServiceKey.self] = ProxyServiceDependency(service: newValue) }
  }

  var trafficCaptureService: TrafficCaptureService {
    get { self[TrafficCaptureServiceKey.self].service }
    set { self[TrafficCaptureServiceKey.self] = TrafficCaptureServiceDependency(service: newValue) }
  }

  var daemonService: DaemonService {
    get { self[DaemonServiceKey.self].service }
    set { self[DaemonServiceKey.self] = DaemonServiceDependency(service: newValue) }
  }

  var launchService: LaunchAtLoginService {
    get { self[LaunchAtLoginServiceKey.self].service }
    set { self[LaunchAtLoginServiceKey.self] = LaunchAtLoginServiceDependency(service: newValue) }
  }

  var settingsService: SettingsService {
    get { self[SettingsServiceKey.self].service }
    set { self[SettingsServiceKey.self] = SettingsServiceDependency(service: newValue) }
  }

  var persistenceService: PersistenceService {
    get { self[PersistenceServiceKey.self].service }
    set { self[PersistenceServiceKey.self] = PersistenceServiceDependency(service: newValue) }
  }

  var networkService: NetworkService {
    get { self[NetworkServiceKey.self].service }
    set { self[NetworkServiceKey.self] = NetworkServiceDependency(service: newValue) }
  }

  var resourceService: ResourceService {
    get { self[ResourceServiceKey.self].service }
    set { self[ResourceServiceKey.self] = ResourceServiceDependency(service: newValue) }
  }

  var mihomoService: MihomoService {
    get { self[MihomoServiceKey.self].service }
    set { self[MihomoServiceKey.self] = MihomoServiceDependency(service: newValue) }
  }
}

struct ProxyServiceDependency: @unchecked Sendable {
  let service: ProxyService
}

struct TrafficCaptureServiceDependency: @unchecked Sendable {
  let service: TrafficCaptureService
}

struct DaemonServiceDependency: @unchecked Sendable {
  let service: DaemonService
}

struct LaunchAtLoginServiceDependency: @unchecked Sendable {
  let service: LaunchAtLoginService
}

struct SettingsServiceDependency: @unchecked Sendable {
  let service: SettingsService
}

struct PersistenceServiceDependency: @unchecked Sendable {
  let service: PersistenceService
}

struct NetworkServiceDependency: @unchecked Sendable {
  let service: NetworkService
}

struct ResourceServiceDependency: @unchecked Sendable {
  let service: ResourceService
}

struct MihomoServiceDependency: @unchecked Sendable {
  let service: MihomoService
}
