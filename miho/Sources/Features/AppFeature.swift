import ComposableArchitecture

@MainActor
struct AppFeature: @preconcurrency Reducer {
  struct State {
    var lifecycle: LifecycleFeature.State
    var dashboard: DashboardFeature.State
    var settings: SettingsFeature.State
    var menuBar: MenuBarFeature.State
    var persistence: PersistenceFeature.State
    var resource: ResourceFeature.State

    init(
      lifecycle: LifecycleFeature.State = .init(),
      dashboard: DashboardFeature.State = .init(),
      settings: SettingsFeature.State = .init(),
      menuBar: MenuBarFeature.State = .init(),
      persistence: PersistenceFeature.State = .init(),
      resource: ResourceFeature.State = .init(),
    ) {
      self.lifecycle = lifecycle
      self.dashboard = dashboard
      self.settings = settings
      self.menuBar = menuBar
      self.persistence = persistence
      self.resource = resource
    }
  }

  @CasePathable
  enum Action {
    case lifecycle(LifecycleFeature.Action)
    case dashboard(DashboardFeature.Action)
    case settings(SettingsFeature.Action)
    case menuBar(MenuBarFeature.Action)
    case persistence(PersistenceFeature.Action)
    case resource(ResourceFeature.Action)
  }

  var body: some ReducerOf<Self> {
    Scope(state: \.lifecycle, action: \.lifecycle) {
      LifecycleFeature()
    }
    Scope(state: \.dashboard, action: \.dashboard) {
      DashboardFeature()
    }
    Scope(state: \.settings, action: \.settings) {
      SettingsFeature()
    }
    Scope(state: \.menuBar, action: \.menuBar) {
      MenuBarFeature()
    }
    Scope(state: \.persistence, action: \.persistence) {
      PersistenceFeature()
    }
    Scope(state: \.resource, action: \.resource) {
      ResourceFeature()
    }
  }

  init() { }
}
