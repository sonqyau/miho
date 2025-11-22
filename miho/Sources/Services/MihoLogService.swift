import Foundation

protocol MihoLogService {
  func logger(for category: LogCategory) -> CategoryLogger
  func log(_ message: String, level: MihoLogLevel, category: LogCategory)
}

struct MihoMihoLogServiceAdapter: MihoLogService {
  private let logging: MihoLog

  init(logging: MihoLog = .shared) {
    self.logging = logging
  }

  func logger(for category: LogCategory) -> CategoryLogger {
    logging.logger(for: category)
  }

  func log(_ message: String, level: MihoLogLevel, category: LogCategory) {
    logging.log(message, level: level, category: category)
  }
}
