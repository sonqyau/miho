import ErrorKit
import Foundation

public enum MihoErrorCategory {
  case database
  case file
  case network
  case validation
  case state
  case operation
  case permission
  case parsing
  case generic
}

public struct MihoError {
  public let error: any Error
  public let message: String
  public let recoverySuggestion: String?
  public let category: MihoErrorCategory

  public init(error: any Error) {
    self.error = error
    message = error.mihoMessage
    recoverySuggestion = error.mihoRecoverySuggestion
    category = MihoErrorCategory.from(error)
  }
}

public extension MihoErrorCategory {
  var displayName: String {
    switch self {
    case .database:
      "Database"

    case .file:
      "File"

    case .network:
      "Network"

    case .validation:
      "Validation"

    case .state:
      "State"

    case .operation:
      "Operation"

    case .permission:
      "Permission"

    case .parsing:
      "Parsing"

    case .generic:
      "Error"
    }
  }

  static func from(_ error: any Error) -> MihoErrorCategory {
    switch error {
    case is PersistenceError, is NetworkError, is APIError, is URLError:
      return .network

    case is ResourceError:
      return .file

    case is InputValidationError, is ConfigValidationError:
      return .validation

    case is SettingsError:
      return .state

    case is DaemonError, is LaunchAtLoginError, is KeychainError:
      return .permission

    case is TrafficCaptureDomainError, is TrafficCaptureDriverError:
      return .operation

    case is YAMLDecoder.YAMLDecodingError, is ByteProcessor.ByteProcessingError, is DecodingError:
      return .parsing

    default:
      let nsError = error as NSError

      if nsError.domain == NSCocoaErrorDomain {
        return .file
      }

      if nsError.domain == NSURLErrorDomain {
        return .network
      }

      return .generic
    }
  }
}

public extension Error {
  var mihoMessage: String {
    ErrorKit.userFriendlyMessage(for: self)
  }

  var mihoRecoverySuggestion: String? {
    (self as? any LocalizedError)?.recoverySuggestion
  }
}
