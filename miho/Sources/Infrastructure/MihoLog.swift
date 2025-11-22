import Foundation
import OSLog

enum MihoLogLevel: String, Codable, Comparable {
  case debug
  case info
  case notice
  case error
  case fault

  case warning
  case silent

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.priority < rhs.priority
  }

  private var canonical: Self {
    switch self {
    case .warning: .notice
    case .silent: .fault
    default: self
    }
  }

  var priority: Int {
    switch canonical {
    case .debug: 0
    case .info: 1
    case .notice, .warning: 2
    case .error: 3
    case .fault, .silent: 4
    }
  }

  var osLogType: OSLogType {
    switch canonical {
    case .debug: .debug
    case .info: .info
    case .notice, .warning: .default
    case .error: .error
    case .fault, .silent: .fault
    }
  }
}

enum LogCategory: String, CaseIterable {
  case app
  case core
  case network
  case config
  case proxy
  case daemon
  case ui
  case api
  case tunnel
  case dns
  case task
  case networkextension
  case unifiedProxy = "unified-proxy"
  case proxySettings = "proxy-settings"
  case service
}

typealias LogMetadata = [String: String]

struct CategoryLogger: @unchecked Sendable {
  private let logger: Logger

  init(logger: Logger) {
    self.logger = logger
  }

  func log(
    level: MihoLogLevel,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
    message: @autoclosure () -> String,
  ) {
    var resolvedMetadata = metadata

    if let error {
      var enriched = resolvedMetadata ?? LogMetadata()
      enriched["error"] = error.mihoMessage
      resolvedMetadata = enriched
    }

    let logMessage = message()

    if let resolvedMetadata, !resolvedMetadata.isEmpty {
      let metadataDescription = Self.describeMetadata(resolvedMetadata)
      logger.log(
        level: level.osLogType,
        "\(logMessage, privacy: .public) [metadata: \(metadataDescription, privacy: .public)]",
      )
    } else {
      logger.log(level: level.osLogType, "\(logMessage, privacy: .public)")
    }
  }

  func trace(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .debug, metadata: metadata, error: error, message: message())
  }

  func debug(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .debug, metadata: metadata, error: error, message: message())
  }

  func info(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .info, metadata: metadata, error: error, message: message())
  }

  func notice(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .notice, metadata: metadata, error: error, message: message())
  }

  func warning(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .warning, metadata: metadata, error: error, message: message())
  }

  func error(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .error, metadata: metadata, error: error, message: message())
  }

  func fault(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .fault, metadata: metadata, error: error, message: message())
  }

  func critical(
    _ message: @autoclosure () -> String,
    metadata: LogMetadata? = nil,
    error: (any Error)? = nil,
  ) {
    log(level: .fault, metadata: metadata, error: error, message: message())
  }

  private static func describeMetadata(_ metadata: LogMetadata) -> String {
    metadata
      .sorted(by: { $0.key < $1.key })
      .map { key, value in "\(key)=\(String(describing: value))" }
      .joined(separator: ", ")
  }
}

final class MihoLog: Sendable {
  private static let mainSubsystem = "com.swift.miho"
  private static let daemonSubsystem = "com.swift.miho.daemon"
  private static let networkExtensionSubsystem = "com.swift.miho.networkextension"

  static let shared = MihoLog()

  private let loggers: [LogCategory: Logger]

  private init() {
    var loggers: [LogCategory: Logger] = [:]

    for category in LogCategory.allCases {
      let subsystem: String =
        switch category {
        case .service, .task, .dns, .proxySettings:
          Self.daemonSubsystem

        case .tunnel:
          Self.networkExtensionSubsystem

        default:
          Self.mainSubsystem
        }

      loggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
    }

    self.loggers = loggers
  }

  func logger(for category: LogCategory) -> CategoryLogger {
    guard let logger = loggers[category] else {
      let fallback = Logger(subsystem: Self.mainSubsystem, category: "unconfigured")
      fallback.error("Logger requested for unconfigured category \(category.rawValue)")
      return CategoryLogger(logger: fallback)
    }
    return CategoryLogger(logger: logger)
  }

  func log(
    _ message: String,
    level: MihoLogLevel = .info,
    category: LogCategory = .app,
  ) {
    let categoryLogger = logger(for: category)
    categoryLogger.log(level: level, message: message)
  }

  func debug(_ message: String, category: LogCategory = .app) {
    log(message, level: .debug, category: category)
  }

  func info(_ message: String, category: LogCategory = .app) {
    log(message, level: .info, category: category)
  }

  func notice(_ message: String, category: LogCategory = .app) {
    log(message, level: .notice, category: category)
  }

  func warning(_ message: String, category: LogCategory = .app) {
    log(message, level: .warning, category: category)
  }

  func error(_ message: String, category: LogCategory = .app) {
    log(message, level: .error, category: category)
  }

  func fault(_ message: String, category: LogCategory = .app) {
    log(message, level: .fault, category: category)
  }
}

enum Log {
  static func logger(for category: LogCategory) -> CategoryLogger {
    MihoLog.shared.logger(for: category)
  }

  static func debug(
    _ message: @autoclosure () -> String,
    category: LogCategory = .app,
    metadata: @autoclosure () -> LogMetadata? = { nil }(),
    error: @autoclosure () -> (any Error)? = { nil }(),
  ) {
    logger(for: category).debug(message(), metadata: metadata(), error: error())
  }

  static func info(
    _ message: @autoclosure () -> String,
    category: LogCategory = .app,
    metadata: @autoclosure () -> LogMetadata? = { nil }(),
    error: @autoclosure () -> (any Error)? = { nil }(),
  ) {
    logger(for: category).info(message(), metadata: metadata(), error: error())
  }

  static func notice(
    _ message: @autoclosure () -> String,
    category: LogCategory = .app,
    metadata: @autoclosure () -> LogMetadata? = { nil }(),
    error: @autoclosure () -> (any Error)? = { nil }(),
  ) {
    logger(for: category).notice(message(), metadata: metadata(), error: error())
  }

  static func warning(
    _ message: @autoclosure () -> String,
    category: LogCategory = .app,
    metadata: @autoclosure () -> LogMetadata? = { nil }(),
    error: @autoclosure () -> (any Error)? = { nil }(),
  ) {
    logger(for: category).warning(message(), metadata: metadata(), error: error())
  }

  static func error(
    _ message: @autoclosure () -> String,
    category: LogCategory = .app,
    metadata: @autoclosure () -> LogMetadata? = { nil }(),
    error: @autoclosure () -> (any Error)? = { nil }(),
  ) {
    logger(for: category).error(message(), metadata: metadata(), error: error())
  }

  static func fault(
    _ message: @autoclosure () -> String,
    category: LogCategory = .app,
    metadata: @autoclosure () -> LogMetadata? = { nil }(),
    error: @autoclosure () -> (any Error)? = { nil }(),
  ) {
    logger(for: category).fault(message(), metadata: metadata(), error: error())
  }
}
