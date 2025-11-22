import Foundation
import OSLog

enum MihomoTaskError: Error, LocalizedError {
  case alreadyRunning
  case failedToStart
  case invalidPath

  var userFriendlyMessage: String {
    errorDescription ?? "Mihomo task error"
  }

  var errorDescription: String? {
    switch self {
    case .alreadyRunning:
      "The Mihomo core process is already running."

    case .failedToStart:
      "Unable to start the Mihomo core process."

    case .invalidPath:
      "Invalid path to the Mihomo executable binary."
    }
  }
}

@MainActor
final class TaskProxyDaemon {
  static let shared = TaskProxyDaemon()

  private var task: Process?
  private let logger = Logger(subsystem: "com.swift.miho.daemon", category: "task")

  private init() {}

  func start(executablePath: String, configPath: String, configFilePath: String, configJSON: String)
    throws
  {
    if task?.isRunning == true {
      throw MihomoTaskError.alreadyRunning
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executablePath)
    process.arguments = ["-d", configPath, "-f", configFilePath]

    var environment = ProcessInfo.processInfo.environment
    if !configJSON.isEmpty {
      environment["MIHOMO_CONFIG"] = configJSON
    }
    process.environment = environment

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        self?.logger.debug("miho: \(output)")
      }
    }

    errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      if let output = String(data: data, encoding: .utf8), !output.isEmpty {
        self?.logger.error("Mihomo core stderr: \(output)")
      }
    }

    do {
      try process.run()
      task = process
      logger.info("Mihomo core process started")
    } catch {
      logger.error("Failed to start Mihomo core process: \(error.localizedDescription)")
      throw MihomoTaskError.failedToStart
    }
  }

  func stop() {
    guard let task = task, task.isRunning else {
      logger.debug("No active Mihomo core process to stop")
      return
    }

    task.terminate()
    task.waitUntilExit()
    self.task = nil
    logger.info("Mihomo core process stopped")
  }

  func getUsedPorts() -> String? {
    guard task?.isRunning == true else {
      return nil
    }
    return "Mihomo core process is running"
  }
}
