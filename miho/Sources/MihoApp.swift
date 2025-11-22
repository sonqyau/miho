import ComposableArchitecture
import SwiftData
import SwiftUI
import UserNotifications

extension NSNotification.Name {
  static let openDashboardWindow = NSNotification.Name("openDashboardWindow")
  static let openSettingsWindow = NSNotification.Name("openSettingsWindow")
}

@main
struct MihoApp: App {
  private let appFeatureStore: StoreOf<AppFeature>
  private let menuBarStore: StoreOf<MenuBarFeature>
  private let persistenceStore: StoreOf<PersistenceFeature>

  @NSApplicationDelegateAdaptor(AppDelegate.self)
  var appDelegate

  init() {
    let appFeatureStore = Store(
      initialState: AppFeature.State(),
      reducer: { AppFeature() },
    )
    self.appFeatureStore = appFeatureStore
    AppDelegate.appFeatureStore = appFeatureStore
    menuBarStore = appFeatureStore.scope(state: \.menuBar, action: \.menuBar)
    persistenceStore = appFeatureStore.scope(state: \.persistence, action: \.persistence)
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(store: menuBarStore)
    } label: {
      MenuBarIconView(store: menuBarStore)
    }
    .menuBarExtraStyle(.window)

    Window("Dashboard", id: "dashboardWindow") {
      AppView(store: appFeatureStore)
        .frame(minWidth: 1000, minHeight: 700)
    }
    .defaultSize(width: 1200, height: 800)
    .keyboardShortcut("d", modifiers: [.command])

    Window("Preferences", id: "settingsWindow") {
      SettingsView(
        store: appFeatureStore.scope(state: \.settings, action: \.settings),
        persistenceStore: persistenceStore,
      )
      .frame(minWidth: 600, minHeight: 500)
    }
    .defaultSize(width: 700, height: 600)
    .keyboardShortcut(",", modifiers: [.command])
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = MihoLog.shared.logger(for: .app)
  static var appFeatureStore: StoreOf<AppFeature>?

  func applicationDidFinishLaunching(_: Notification) {
    NSApp.setActivationPolicy(.accessory)
    Self.appFeatureStore?.send(.lifecycle(.initialize))
  }

  func applicationWillTerminate(_: Notification) {
    Self.appFeatureStore?.send(.lifecycle(.shutdown))
    logger.info("Application terminated")
  }

  @MainActor
  func openWindow(id: String) {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == id }) {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  }
}
