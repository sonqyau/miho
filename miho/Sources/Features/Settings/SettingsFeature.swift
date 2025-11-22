import ComposableArchitecture
import Foundation
import Perception

@MainActor
struct SettingsFeature: @preconcurrency Reducer {
  @ObservableState
  struct State: Equatable {
    struct StatusOverview: Equatable {
      var indicatorIsActive: Bool = false
      var summary: String = "Disabled"
      var hint: String? = "Select and enable a traffic capture mode to start routing traffic."
    }

    struct SystemProxy: Equatable {
      var isEnabled: Bool = false
      var httpPort: Int = 7890
      var socksPort: Int = 7891
      var mixedPort: Int?
    }

    struct TunMode: Equatable {
      var isEnabled: Bool = false
      var requiresHelperApproval: Bool = false
      var isHelperRegistered: Bool = false
    }

    struct TrafficCapture: Equatable {
      var mode: TrafficCaptureMode
      var isActive: Bool
      var isActivating: Bool
      var autoFallbackEnabled: Bool
      var activeDriverID: TrafficCaptureDriverID?
      var activeDriverName: String?
      var preferredDriverID: TrafficCaptureDriverID?
      var driversByMode: [TrafficCaptureMode: [TrafficCaptureDriverDescriptor]]
      var lastErrorDescription: String?
    }

    struct ProxyModeState: Equatable {
      var selection: ProxyMode
      var description: String
    }

    struct LaunchAtLogin: Equatable {
      var isEnabled: Bool = false
      var requiresApproval: Bool = false
    }

    struct Alerts: Equatable {
      var errorMessage: String?
    }

    var statusOverview: StatusOverview = .init()
    var systemProxy: SystemProxy = .init()
    var tunMode: TunMode = .init()
    var trafficCapture: TrafficCapture = .init(
      mode: .manual,
      isActive: false,
      isActivating: false,
      autoFallbackEnabled: true,
      activeDriverID: nil,
      activeDriverName: nil,
      preferredDriverID: nil,
      driversByMode: [:],
      lastErrorDescription: nil,
    )
    var proxyMode: ProxyModeState = .init(selection: .rule, description: "")
    var launchAtLogin: LaunchAtLogin = .init()
    var allowLan: Bool = false
    var alerts: Alerts = .init()
    var isProcessing: Bool = false
  }

  enum Action: Equatable {
    case onAppear
    case dismissError
    case toggleSystemProxy
    case toggleTunMode
    case installHelper
    case openSystemSettings
    case checkHelperStatus
    case confirmLaunchAtLogin
    case toggleLaunchAtLogin
    case selectTrafficCaptureMode(TrafficCaptureMode)
    case toggleTrafficCaptureActivation
    case setTrafficCapturePreferredDriver(TrafficCaptureMode, TrafficCaptureDriverID?)
    case toggleTrafficCaptureFallback(Bool)
    case selectProxyMode(ProxyMode)
    case reloadConfig
    case flushDNS
    case toggleAllowLAN(Bool)
    case operationFinished(String?)
  }

  @Dependency(\.proxyService)
  var proxyService

  @Dependency(\.trafficCaptureService)
  var trafficCaptureService

  @Dependency(\.daemonService)
  var daemonService

  @Dependency(\.launchService)
  var launchService

  @Dependency(\.settingsService)
  var settingsService

  @Dependency(\.resourceService)
  var resourceService

  init() { }
  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .onAppear:
        return onAppearEffect(state: &state)

      case .dismissError:
        state.alerts.errorMessage = nil
        return .none

      case .reloadConfig:
        return reloadConfigEffect(state: &state)

      case let .operationFinished(errorMessage):
        return operationFinishedEffect(state: &state, errorMessage: errorMessage)

      case .checkHelperStatus:
        daemonService.checkStatus()
        return .none

      case .confirmLaunchAtLogin:
        launchService.updateStatus()
        return .none

      case let .setTrafficCapturePreferredDriver(mode, driverID):
        trafficCaptureService.setPreferredDriver(driverID, for: mode)
        return .none

      case let .toggleTrafficCaptureFallback(isEnabled):
        trafficCaptureService.autoFallbackEnabled = isEnabled
        return .none

      case .toggleSystemProxy:
        return toggleSystemProxyEffect(state: &state)

      case .toggleTunMode:
        return toggleTunModeEffect(state: &state)

      case let .toggleAllowLAN(isEnabled):
        return toggleAllowLANEffect(state: &state, isEnabled: isEnabled)

      case let .selectProxyMode(mode):
        return selectProxyModeEffect(state: &state, mode: mode)

      case let .selectTrafficCaptureMode(mode):
        return selectTrafficCaptureModeEffect(state: &state, mode: mode)

      case .toggleTrafficCaptureActivation:
        return toggleTrafficCaptureActivationEffect(state: &state)

      case .flushDNS:
        return flushDNSEffect(state: &state)

      case .installHelper:
        return installHelperEffect(state: &state)

      case .toggleLaunchAtLogin:
        return toggleLaunchAtLoginEffect(state: &state)

      case .openSystemSettings:
        daemonService.openSystemSettings()
        launchService.openSystemSettings()
        return .none
      }
    }
  }

  private func onAppearEffect(state: inout State) -> Effect<Action> {
    let snapshots = SettingsSnapshots(
      proxy: ProxySnapshot(proxyService.currentState()),
      capture: TrafficCaptureSnapshot(trafficCaptureService.currentState()),
      daemon: DaemonSnapshot(daemonService.currentState()),
      launch: LaunchSnapshot(launchService.currentState()),
    )
    Self.mapState(from: snapshots, into: &state)
    return .none
  }

  private func reloadConfigEffect(state: inout State) -> Effect<Action> {
    guard !state.isProcessing else {
      return .none
    }

    state.isProcessing = true
    state.alerts.errorMessage = nil

    let proxyContainer = ProxyServiceDependency(service: proxyService)

    return .run { @MainActor send in
      do {
        try await proxyContainer.service.reloadConfig()
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func operationFinishedEffect(
    state: inout State,
    errorMessage: String?,
  ) -> Effect<Action> {
    state.isProcessing = false
    state.alerts.errorMessage = errorMessage

    let snapshots = SettingsSnapshots(
      proxy: ProxySnapshot(proxyService.currentState()),
      capture: TrafficCaptureSnapshot(trafficCaptureService.currentState()),
      daemon: DaemonSnapshot(daemonService.currentState()),
      launch: LaunchSnapshot(launchService.currentState()),
    )
    Self.mapState(from: snapshots, into: &state)
    return .none
  }

  private func toggleSystemProxyEffect(state: inout State) -> Effect<Action> {
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let proxyContainer = ProxyServiceDependency(service: proxyService)

    return .run { @MainActor send in
      do {
        try await proxyContainer.service.toggleSystemProxy()
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func toggleTunModeEffect(state: inout State) -> Effect<Action> {
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let proxyContainer = ProxyServiceDependency(service: proxyService)

    return .run { @MainActor send in
      do {
        try await proxyContainer.service.toggleTunMode()
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func toggleAllowLANEffect(
    state: inout State,
    isEnabled: Bool,
  ) -> Effect<Action> {
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let proxyContainer = ProxyServiceDependency(service: proxyService)
    let settingsContainer = SettingsServiceDependency(service: settingsService)

    return .run { @MainActor send in
      do {
        try await proxyContainer.service.setAllowLAN(isEnabled)
        settingsContainer.service.allowLAN = isEnabled
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func selectProxyModeEffect(
    state: inout State,
    mode: ProxyMode,
  ) -> Effect<Action> {
    guard state.proxyMode.selection != mode else {
      return .none
    }
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let proxyContainer = ProxyServiceDependency(service: proxyService)

    return .run { @MainActor send in
      do {
        try await proxyContainer.service.switchMode(mode)
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func selectTrafficCaptureModeEffect(
    state: inout State,
    mode: TrafficCaptureMode,
  ) -> Effect<Action> {
    let captureSnapshot = TrafficCaptureSnapshot(trafficCaptureService.currentState())
    guard captureSnapshot.selectedMode != mode else {
      return .none
    }
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let captureContainer = TrafficCaptureServiceDependency(service: trafficCaptureService)
    let proxySnapshot = ProxySnapshot(proxyService.currentState())
    let context = Self.makeCaptureContext(
      mode: mode,
      proxy: proxySnapshot,
      resourceService: resourceService,
    )

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

  private func toggleTrafficCaptureActivationEffect(
    state: inout State,
  ) -> Effect<Action> {
    let captureSnapshot = TrafficCaptureSnapshot(trafficCaptureService.currentState())
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let captureContainer = TrafficCaptureServiceDependency(service: trafficCaptureService)
    let proxySnapshot = ProxySnapshot(proxyService.currentState())
    let mode = captureSnapshot.selectedMode
    let context = Self.makeCaptureContext(
      mode: mode,
      proxy: proxySnapshot,
      resourceService: resourceService,
    )

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

  private func flushDNSEffect(state: inout State) -> Effect<Action> {
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let daemonContainer = DaemonServiceDependency(service: daemonService)

    return .run { @MainActor send in
      do {
        try await daemonContainer.service.flushDNSCache()
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func installHelperEffect(state: inout State) -> Effect<Action> {
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let daemonContainer = DaemonServiceDependency(service: daemonService)

    return .run { @MainActor send in
      do {
        try await daemonContainer.service.register()
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }

  private func toggleLaunchAtLoginEffect(state: inout State) -> Effect<Action> {
    guard !state.isProcessing else {
      return .none
    }
    state.isProcessing = true
    state.alerts.errorMessage = nil

    let launchContainer = LaunchAtLoginServiceDependency(service: launchService)
    let settingsContainer = SettingsServiceDependency(service: settingsService)

    return .run { @MainActor send in
      do {
        try launchContainer.service.toggle()
        let enabled = launchContainer.service.currentState().isEnabled
        settingsContainer.service.launchAtLogin = enabled
        send(.operationFinished(nil))
      } catch {
        let message = (error as NSError).localizedDescription
        send(.operationFinished(message))
      }
    }
  }
}

extension SettingsFeature {
  static func mapState(from snapshots: SettingsSnapshots, into state: inout State) {
    let proxyState = snapshots.proxy
    let captureState = snapshots.capture
    let daemonState = snapshots.daemon
    let launchState = snapshots.launch

    state.statusOverview = .init(
      indicatorIsActive: proxyState.isSystemProxyEnabled
        || proxyState.isTunModeEnabled
        || captureState.isActive,
      summary: composeStatusSummary(proxyState: proxyState, captureState: captureState),
      hint: captureState.isActive
        || proxyState.isSystemProxyEnabled
        || proxyState.isTunModeEnabled
        ? nil
        : "Select and enable a traffic capture mode to start routing traffic.",
    )

    state.systemProxy = .init(
      isEnabled: proxyState.isSystemProxyEnabled,
      httpPort: proxyState.httpPort,
      socksPort: proxyState.socksPort,
      mixedPort: proxyState.mixedPort,
    )

    state.tunMode = .init(
      isEnabled: proxyState.isTunModeEnabled,
      requiresHelperApproval: daemonState.requiresApproval,
      isHelperRegistered: daemonState.isRegistered,
    )

    state.trafficCapture = .init(
      mode: captureState.selectedMode,
      isActive: captureState.isActive,
      isActivating: captureState.isActivating,
      autoFallbackEnabled: captureState.autoFallbackEnabled,
      activeDriverID: captureState.activeDriver,
      activeDriverName: driverName(from: captureState),
      preferredDriverID: captureState.preferredDrivers[captureState.selectedMode],
      driversByMode: captureState.availableDrivers,
      lastErrorDescription: captureState.lastErrorDescription,
    )

    state.proxyMode = .init(
      selection: proxyState.currentMode,
      description: describeProxyMode(proxyState.currentMode),
    )

    state.launchAtLogin = .init(
      isEnabled: launchState.isEnabled,
      requiresApproval: launchState.requiresApproval,
    )

    state.allowLan = proxyState.allowLAN
  }

  private static func composeStatusSummary(
    proxyState: ProxySnapshot,
    captureState: TrafficCaptureSnapshot,
  ) -> String {
    if captureState.isActive {
      return "Traffic capture enabled"
    }
    if proxyState.isSystemProxyEnabled || proxyState.isTunModeEnabled {
      return "Proxy routing enabled"
    }
    return "Disabled"
  }

  private static func describeProxyMode(_ mode: ProxyMode) -> String {
    switch mode {
    case .rule:
      "Rule-based routing"

    case .global:
      "Global proxy"

    case .direct:
      "Direct connection"
    }
  }

  private static func driverName(from captureState: TrafficCaptureSnapshot) -> String? {
    let descriptors = captureState.availableDrivers
    let flattened = descriptors.flatMap { $0.value }
    guard let activeID = captureState.activeDriver else {
      return nil
    }
    return flattened.first { $0.id == activeID }?.name
  }

  @MainActor
  static func makeCaptureContext(
    mode: TrafficCaptureMode,
    proxy: ProxySnapshot,
    resourceService: ResourceService,
  ) -> TrafficCaptureActivationContext {
    var context = TrafficCaptureActivationContext(
      httpPort: proxy.httpPort,
      socksPort: proxy.socksPort,
      pacURL: nil,
      configurationDirectory: resourceService.configDirectory,
      environment: [:],
    )

    switch mode {
    case .pac:
      context.pacURL = resourceService.configDirectory.appendingPathComponent("auto.pac")

    case .manual:
      context.environment = ProcessInfo.processInfo.environment

    case .global, .tun:
      break
    }

    return context
  }
}
