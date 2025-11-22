import AppKit
@preconcurrency import Combine
import ErrorKit
import Foundation
import OSLog
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginManager {
  struct State: Equatable {
    var isEnabled: Bool
    var requiresApproval: Bool
  }

  static let shared = LaunchAtLoginManager()

  private let logger = MihoLog.shared.logger(for: .service)
  private let stateSubject = CurrentValueSubject<State, Never>(State(
    isEnabled: false,
    requiresApproval: false,
  ))

  private(set) var isEnabled = false {
    didSet {
      if isEnabled != oldValue {
        emitState()
      }
    }
  }

  private(set) var requiresApproval = false {
    didSet {
      if requiresApproval != oldValue {
        emitState()
      }
    }
  }

  var state: State {
    State(isEnabled: isEnabled, requiresApproval: requiresApproval)
  }

  private init() {
    updateStatus()
  }

  func updateStatus() {
    let status = SMAppService.mainApp.status

    switch status {
    case .enabled:
      isEnabled = true
      requiresApproval = false
      logger.info("Launch at login enabled")

    case .requiresApproval:
      isEnabled = false
      requiresApproval = true
      logger.notice("Launch at login requires authorization in System Settings")

    case .notRegistered, .notFound:
      isEnabled = false
      requiresApproval = false
      logger.info("Launch at login not registered")

    @unknown default:
      isEnabled = false
      requiresApproval = false
      logger.notice("Launch at login status is unknown")
    }
  }

  func enable() throws {
    guard !isEnabled else {
      logger.info("Launch at login is already enabled")
      return
    }

    do {
      try SMAppService.mainApp.register()
      logger.info("Launch at login enabled successfully")
      updateStatus()
    } catch {
      logger.error("Unable to enable launch at login", error: error)
      throw LaunchAtLoginError.registrationFailed(error)
    }
  }

  func disable() throws {
    guard isEnabled else {
      logger.info("Launch at login is already disabled")
      return
    }

    do {
      try SMAppService.mainApp.unregister()
      logger.info("Launch at login disabled successfully")
      updateStatus()
    } catch {
      logger.error("Unable to disable launch at login", error: error)
      throw LaunchAtLoginError.unregistrationFailed(error)
    }
  }

  func toggle() throws {
    if isEnabled {
      try disable()
    } else {
      try enable()
    }
  }

  func openSystemSettings() {
    guard let url =
      URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    else {
      return
    }
    AppKit.NSWorkspace.shared.open(url)
  }

  func statePublisher() -> AnyPublisher<State, Never> {
    stateSubject.receive(on: RunLoop.main).eraseToAnyPublisher()
  }

  private func emitState() {
    stateSubject.send(state)
  }
}

enum LaunchAtLoginError: LocalizedError, Throwable {
  case registrationFailed(any Error)
  case unregistrationFailed(any Error)

  var userFriendlyMessage: String {
    errorDescription ?? "Launch at login operation failed"
  }

  var errorDescription: String? {
    switch self {
    case let .registrationFailed(error):
      "Unable to enable launch at login: \(error.localizedDescription)"

    case let .unregistrationFailed(error):
      "Unable to disable launch at login: \(error.localizedDescription)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .registrationFailed, .unregistrationFailed:
      "Grant permission in System Settings > General > Login Items, then try again."
    }
  }
}

enum LaunchAtLogin { }
