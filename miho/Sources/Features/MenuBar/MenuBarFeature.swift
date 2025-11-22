@preconcurrency import Combine
import ComposableArchitecture
import Foundation

@MainActor
struct MenuBarFeature: @preconcurrency Reducer {
  @ObservableState
  struct State {
    struct ActiveFeatures: Equatable {
      var systemProxy: Bool = false
      var tunMode: Bool = false
    }

    struct Alerts: Equatable {
      var errorMessage: String?
    }

    struct ProxySelectorGroup: Identifiable {
      var id: String
      var info: GroupInfo
    }

    var statusDescription: String = "Disabled"
    var statusSubtitle: String = "Inactive"
    var isSystemProxyEnabled: Bool = false
    var isTunModeEnabled: Bool = false
    var currentMode: ProxyMode = .rule
    var captureMode: TrafficCaptureMode = .manual
    var isTrafficCaptureActive: Bool = false
    var isTrafficCaptureActivating: Bool = false
    var activeTrafficDriverName: String?
    var availableTrafficDrivers: [TrafficCaptureDriverDescriptor] = []
    var preferredTrafficDriverID: TrafficCaptureDriverID?
    var autoFallbackEnabled: Bool = true
    var trafficCaptureError: String?
    var downloadSpeed: String = "--"
    var uploadSpeed: String = "--"
    var selectorGroups: [ProxySelectorGroup] = []
    var proxies: [String: ProxyInfo] = [:]
    var activeFeatures: ActiveFeatures = .init()
    var networkInterface: String?
    var ipAddress: String?
    var alerts: Alerts = .init()
  }

  @CasePathable
  enum Action {
    case onAppear
    case onDisappear
    case toggleSystemProxy
    case toggleTunMode
    case toggleTrafficCapture
    case selectTrafficCaptureMode(TrafficCaptureMode)
    case setPreferredTrafficDriver(TrafficCaptureDriverID?)
    case toggleTrafficFallback(Bool)
    case switchMode(ProxyMode)
    case reloadConfig
    case selectProxy(group: String, proxy: String)
    case refreshNetworkInfo
    case mihomoSnapshotUpdated(MihomoSnapshot)
    case proxySnapshotUpdated(ProxySnapshot)
    case captureSnapshotUpdated(TrafficCaptureSnapshot)
    case selectProxyFinished(error: String?)
    case operationFinished(String?)
    case dismissError
  }

  private enum CancelID {
    case mihomoStream
    case proxyStream
    case captureStream
  }

  @Dependency(\.mihomoService)
  var mihomoService

  @Dependency(\.proxyService)
  var proxyService

  @Dependency(\.trafficCaptureService)
  var trafficCaptureService

  @Dependency(\.networkService)
  var networkService

  @Dependency(\.resourceService)
  var resourceService

  init() { }

  var body: some ReducerOf<Self> {
    Reduce(reduce(into:action:))
  }

  // swiftlint:disable cyclomatic_complexity
  func reduce(into state: inout State, action: Action) -> Effect<Action> {
    switch action {
    case .onAppear:
      return onAppearEffect(state: &state)

    case .onDisappear:
      return onDisappearEffect()

    case .dismissError:
      state.alerts.errorMessage = nil
      return .none

    case .refreshNetworkInfo:
      state.networkInterface = networkService.getPrimaryInterfaceName()
      state.ipAddress = networkService.getPrimaryIPAddress(allowIPv6: false)
      return .none

    case let .mihomoSnapshotUpdated(snapshot):
      state.downloadSpeed = Self.formatSpeed(snapshot.currentTraffic?.downloadSpeed)
      state.uploadSpeed = Self.formatSpeed(snapshot.currentTraffic?.uploadSpeed)
      state.selectorGroups = Self.buildSelectorGroups(from: snapshot.groups)
      state.proxies = snapshot.proxies
      return .none

    case let .proxySnapshotUpdated(snapshot):
      let captureSnapshot = TrafficCaptureSnapshot(trafficCaptureService.currentState())
      updateState(from: snapshot, capture: captureSnapshot, into: &state)
      return .none

    case let .captureSnapshotUpdated(snapshot):
      let proxySnapshot = ProxySnapshot(proxyService.currentState())
      updateState(from: proxySnapshot, capture: snapshot, into: &state)
      return .none

    case .toggleSystemProxy:
      return toggleSystemProxyEffect()

    case .toggleTunMode:
      return toggleTunModeEffect()

    case .reloadConfig:
      return reloadConfigEffect()

    case let .switchMode(mode):
      return switchModeEffect(mode: mode)

    case .toggleTrafficCapture:
      return toggleTrafficCaptureEffect()

    case let .selectTrafficCaptureMode(mode):
      return selectTrafficCaptureModeEffect(mode: mode)

    case let .setPreferredTrafficDriver(driverID):
      trafficCaptureService.setPreferredDriver(
        driverID,
        for: TrafficCaptureSnapshot(trafficCaptureService.currentState()).selectedMode,
      )
      return .none

    case let .toggleTrafficFallback(isEnabled):
      trafficCaptureService.autoFallbackEnabled = isEnabled
      return .none

    case let .selectProxy(group, proxy):
      return selectProxyEffect(group: group, proxy: proxy)

    case let .selectProxyFinished(error):
      if let error {
        state.alerts.errorMessage = error
      }
      return .none

    case let .operationFinished(errorMessage):
      state.alerts.errorMessage = errorMessage

      let proxySnapshot = ProxySnapshot(proxyService.currentState())
      let captureSnapshot = TrafficCaptureSnapshot(trafficCaptureService.currentState())
      updateState(from: proxySnapshot, capture: captureSnapshot, into: &state)
      return .none
    }
  }

  // swiftlint:enable cyclomatic_complexity

  private func onAppearEffect(state: inout State) -> Effect<Action> {
    let mihomo = mihomoService
    let proxy = proxyService
    let capture = trafficCaptureService
    let network = networkService

    let mihomoEffect: Effect<Action> = .run { @MainActor send in
      mihomo.connect()
      for await domainState in mihomo.statePublisher.values {
        let snapshot = MihomoSnapshot(domainState)
        send(.mihomoSnapshotUpdated(snapshot))
      }
    }
    .cancellable(id: CancelID.mihomoStream, cancelInFlight: true)

    let proxyEffect: Effect<Action> = .run { @MainActor send in
      for await proxyState in proxy.statePublisher.values {
        let snapshot = ProxySnapshot(proxyState)
        send(.proxySnapshotUpdated(snapshot))
      }
    }
    .cancellable(id: CancelID.proxyStream, cancelInFlight: true)

    let captureEffect: Effect<Action> = .run { @MainActor send in
      for await captureState in capture.statePublisher.values {
        let snapshot = TrafficCaptureSnapshot(captureState)
        send(.captureSnapshotUpdated(snapshot))
      }
    }
    .cancellable(id: CancelID.captureStream, cancelInFlight: true)

    state.networkInterface = network.getPrimaryInterfaceName()
    state.ipAddress = network.getPrimaryIPAddress(allowIPv6: false)

    let proxySnapshot = ProxySnapshot(proxy.currentState())
    let captureSnapshot = TrafficCaptureSnapshot(capture.currentState())
    updateState(from: proxySnapshot, capture: captureSnapshot, into: &state)

    return .merge(mihomoEffect, proxyEffect, captureEffect)
  }

  private func onDisappearEffect() -> Effect<Action> {
    .merge(
      .cancel(id: CancelID.mihomoStream),
      .cancel(id: CancelID.proxyStream),
      .cancel(id: CancelID.captureStream),
    )
  }

  private func toggleSystemProxyEffect() -> Effect<Action> {
    let proxyContainer = ProxyServiceDependency(service: proxyService)
    return runOperation(containerDescription: "toggleSystemProxy") {
      try await proxyContainer.service.toggleSystemProxy()
    }
  }

  private func toggleTunModeEffect() -> Effect<Action> {
    let proxyContainer = ProxyServiceDependency(service: proxyService)
    return runOperation(containerDescription: "toggleTunMode") {
      try await proxyContainer.service.toggleTunMode()
    }
  }

  private func reloadConfigEffect() -> Effect<Action> {
    let proxyContainer = ProxyServiceDependency(service: proxyService)
    return runOperation(containerDescription: "reloadConfig") {
      try await proxyContainer.service.reloadConfig()
    }
  }

  private func switchModeEffect(mode: ProxyMode) -> Effect<Action> {
    let proxyContainer = ProxyServiceDependency(service: proxyService)
    return runOperation(containerDescription: "switchMode") {
      try await proxyContainer.service.switchMode(mode)
    }
  }

  private func toggleTrafficCaptureEffect() -> Effect<Action> {
    let captureSnapshot = TrafficCaptureSnapshot(trafficCaptureService.currentState())
    let captureContainer = TrafficCaptureServiceDependency(service: trafficCaptureService)
    let proxySnapshot = ProxySnapshot(proxyService.currentState())
    let mode = captureSnapshot.selectedMode
    let context = makeCaptureContext(mode: mode, proxy: proxySnapshot)

    return .run { @MainActor send in
      do {
        if captureSnapshot.isActive {
          await captureContainer.service.deactivateCurrentMode()
        } else {
          try await captureContainer.service.activate(mode: mode, context: context)
        }
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func selectTrafficCaptureModeEffect(mode: TrafficCaptureMode) -> Effect<Action> {
    let captureSnapshot = TrafficCaptureSnapshot(trafficCaptureService.currentState())
    guard captureSnapshot.selectedMode != mode else {
      return .none
    }

    let captureContainer = TrafficCaptureServiceDependency(service: trafficCaptureService)
    let proxySnapshot = ProxySnapshot(proxyService.currentState())
    let context = makeCaptureContext(mode: mode, proxy: proxySnapshot)

    return .run { @MainActor send in
      do {
        try await captureContainer.service.activate(mode: mode, context: context)
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func selectProxyEffect(group: String, proxy: String) -> Effect<Action> {
    let service = mihomoService
    return .run { @MainActor send in
      do {
        try await service.selectProxy(group: group, proxy: proxy)
        send(.selectProxyFinished(error: nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.selectProxyFinished(error: message))
      }
    }
  }

  private func runOperation(
    containerDescription _: String,
    work: @escaping () async throws -> Void,
  ) -> Effect<Action> {
    .run { @MainActor send in
      do {
        try await work()
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func updateState(
    from proxy: ProxySnapshot,
    capture: TrafficCaptureSnapshot,
    into state: inout State,
  ) {
    state.statusDescription = Self.composeMenuBarStatus(proxyState: proxy, captureState: capture)
    state.statusSubtitle = Self.makeMenuSubtitle(
      systemProxy: proxy.isSystemProxyEnabled,
      tunMode: proxy.isTunModeEnabled,
    )
    state.isSystemProxyEnabled = proxy.isSystemProxyEnabled
    state.isTunModeEnabled = proxy.isTunModeEnabled
    state.currentMode = proxy.currentMode
    state.captureMode = capture.selectedMode
    state.isTrafficCaptureActive = capture.isActive
    state.isTrafficCaptureActivating = capture.isActivating
    state.activeTrafficDriverName = Self.driverName(from: capture)
    state.availableTrafficDrivers = capture.availableDrivers[capture.selectedMode] ?? []
    state.preferredTrafficDriverID = capture.preferredDrivers[capture.selectedMode]
    state.autoFallbackEnabled = capture.autoFallbackEnabled
    state.trafficCaptureError = capture.lastErrorDescription
    state.activeFeatures = .init(
      systemProxy: proxy.isSystemProxyEnabled,
      tunMode: proxy.isTunModeEnabled,
    )
  }

  private static func formatSpeed(_ value: String?) -> String {
    value ?? "0 B/s"
  }

  private static func composeMenuBarStatus(
    proxyState: ProxySnapshot,
    captureState: TrafficCaptureSnapshot,
  ) -> String {
    let captureDescription: String = {
      if captureState.isActive {
        if let driver = driverName(from: captureState) {
          "Traffic capture: \(driver)"
        } else {
          "Traffic capture: \(captureState.selectedMode.displayName)"
        }
      } else {
        "Traffic capture: idle"
      }
    }()

    if proxyState.statusSummary == "Disabled" {
      return captureDescription
    }

    return "\(captureDescription) • Core routing: \(proxyState.statusSummary)"
  }

  private static func driverName(from captureState: TrafficCaptureSnapshot) -> String? {
    guard let id = captureState.activeDriver else {
      return nil
    }
    return captureState.availableDrivers.values
      .flatMap { $0 }
      .first(where: { $0.id == id })?.name
  }

  private static func makeMenuSubtitle(systemProxy: Bool, tunMode: Bool) -> String {
    switch (systemProxy, tunMode) {
    case (true, true): "System proxy and TUN active"
    case (true, false): "System proxy active"
    case (false, true): "TUN mode active"
    default: "Inactive"
    }
  }

  private static func buildSelectorGroups(
    from groups: [String: GroupInfo],
  ) -> [State.ProxySelectorGroup] {
    groups
      .filter { $0.value.type.lowercased() == "selector" }
      .sorted { $0.key < $1.key }
      .map { key, info in
        State.ProxySelectorGroup(id: key, info: info)
      }
  }

  private func makeCaptureContext(
    mode: TrafficCaptureMode,
    proxy: ProxySnapshot,
  ) -> TrafficCaptureActivationContext {
    TrafficCaptureActivationContext(
      httpPort: proxy.httpPort,
      socksPort: proxy.socksPort,
      pacURL: mode == .pac
        ? resourceService.configDirectory.appendingPathComponent("auto.pac")
        : nil,
      configurationDirectory: resourceService.configDirectory,
      environment: mode == .manual ? ProcessInfo.processInfo.environment : [:],
    )
  }
}
