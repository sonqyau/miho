import ErrorKit
import Foundation
import OSLog
import Yams

enum ConfigValidationError: LocalizedError, Throwable {
  case executableNotFound
  case executionFailed(any Error)

  var userFriendlyMessage: String {
    errorDescription ?? "Configuration validation failed"
  }

  var errorDescription: String? {
    switch self {
    case .executableNotFound:
      "Required Mihomo executable is missing from the application bundle"

    case let .executionFailed(error):
      "Configuration validation process failed: \(error.localizedDescription)"
    }
  }

  var recoverySuggestion: String? {
    switch self {
    case .executableNotFound:
      "Reinstall the application to restore the bundled Mihomo executable."

    case .executionFailed:
      "Verify file permissions and configuration path, then run validation again."
    }
  }
}

enum ValidationResult {
  case success
  case failure(String)

  var isValid: Bool {
    if case .success = self {
      return true
    }
    return false
  }

  var errorMessage: String? {
    if case let .failure(message) = self {
      return message
    }
    return nil
  }
}

@MainActor
final class ConfigValidation {
  static let shared = ConfigValidation()

  private let logger = MihoLog.shared.logger(for: .core)

  private init() { }

  func validate(configPath: String, workingDirectory: String? = nil) async throws
  -> ValidationResult {
    guard
      let exec = Bundle.main.url(
        forResource: "miho", withExtension: nil, subdirectory: "Resources",
      )?.path
    else {
      throw ConfigValidationError.executableNotFound
    }

    let workDir = workingDirectory ?? ResourceDomain.shared.configDirectory.path

    guard FileManager.default.fileExists(atPath: configPath) else {
      return .failure("Configuration file not found at the specified path")
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: exec)
    proc.arguments = ["-t", "-d", workDir, "-f", configPath]
    proc.environment = ["PATH": "/usr/bin:/bin"]

    let outPipe = Pipe()
    let errPipe = Pipe()
    proc.standardOutput = outPipe
    proc.standardError = errPipe

    try proc.run()
    proc.waitUntilExit()

    let out =
      String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err =
      String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let combined = out + err

    return proc.terminationStatus == 0 ? .success : .failure(extractErrorMessage(from: combined))
  }

  func validateContent(_ content: String) async throws -> ValidationResult {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
      "cfg_\(UUID().uuidString).yaml",
    )
    defer { try? FileManager.default.removeItem(at: tmp) }

    try content.write(to: tmp, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
    return try await validate(configPath: tmp.path)
  }

  func quickValidate(configPath: String) throws -> ValidationResult {
    guard let data = FileManager.default.contents(atPath: configPath) else {
      return .failure("Unable to read configuration file")
    }

    guard let content = String(data: data, encoding: .utf8) else {
      return .failure("Configuration file is not valid UTF-8")
    }

    if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .failure("Configuration file is empty")
    }

    do {
      _ = try YAMLDecoder().decode(ProxyModel.self, from: data)
      return .success
    } catch {
      guard let yaml = try? Yams.load(yaml: content) as? [String: Any] else {
        return .failure("Configuration file is not valid YAML")
      }

      let hasPort = yaml["port"] != nil || yaml["mixed-port"] != nil || yaml["socks-port"] != nil
      let hasProxies = yaml["proxies"] != nil || yaml["proxy-providers"] != nil

      return (hasPort || hasProxies)
        ? .success
        : .failure("Configuration is missing required port or proxy definitions")
    }
  }

  private func extractErrorMessage(from output: String) -> String {
    let lines = output.split(separator: "\n").map(String.init)

    for line in lines {
      if line.contains("level=error") || line.contains("level=fatal") {
        if let range = line.range(of: "msg=") {
          return String(line[range.upperBound...]).trimmingCharacters(
            in: CharacterSet(charactersIn: "\""),
          )
        }
      }

      if line.contains("test failed") || line.lowercased().contains("error:") {
        return line
      }
    }

    return lines.reversed().first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      ?? "Configuration validation failed with an unknown error"
  }
}
