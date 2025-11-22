import Factory

struct ServiceDependencies { }

extension Container {
  var mihomoService: Factory<MihomoService> {
    self { @MainActor in APIDomainMihomoServiceAdapter() }.shared
  }

  var proxyService: Factory<ProxyService> {
    self { @MainActor in ProxyConfigDomainServiceAdapter() }.shared
  }

  var trafficCaptureService: Factory<TrafficCaptureService> {
    self { @MainActor in TrafficCaptureDomainServiceAdapter() }.shared
  }

  var daemonService: Factory<DaemonService> {
    self { @MainActor in DaemonDomainServiceAdapter() }.shared
  }

  var launchAtLoginService: Factory<LaunchAtLoginService> {
    self { @MainActor in LaunchAtLoginManagerServiceAdapter() }.shared
  }

  var settingsService: Factory<SettingsService> {
    self { @MainActor in SettingsManagerServiceAdapter() }.shared
  }

  var persistenceService: Factory<PersistenceService> {
    self { @MainActor in RemoteConfigPersistenceServiceAdapter() }.shared
  }

  var resourceService: Factory<ResourceService> {
    self { @MainActor in ResourceDomainServiceAdapter() }.shared
  }

  var networkService: Factory<NetworkService> {
    self { @MainActor in NetworkDomainServiceAdapter() }.shared
  }
}
