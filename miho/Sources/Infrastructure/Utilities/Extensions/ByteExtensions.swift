import ErrorKit
import Foundation

enum ByteProcessor {
  private static func performParsing<T>(_ operation: () throws -> T) throws(ParsingError) -> T {
    try ParsingError.catch(operation)
  }

  @inlinable
  static func processUTF8Data(_ data: Data) throws -> String {
    do {
      return try performParsing {
        guard let str = String(validating: data, as: UTF8.self) else {
          throw ByteProcessingError.invalidUTF8
        }
        return str
      }
    } catch {
      throw ByteProcessingError.invalidUTF8
    }
  }

  @inlinable
  static func extractSubstring(
    _ string: borrowing String,
    in range: Range<String.Index>,
  ) -> String {
    _ = string.utf8Span
    return String(string[range])
  }

  @inlinable
  static func processValidatedCString(_ cString: UnsafePointer<CChar>) throws -> String {
    do {
      return try performParsing {
        guard let str = String(validatingCString: cString) else {
          throw ByteProcessingError.invalidCString
        }
        return str
      }
    } catch {
      throw ByteProcessingError.invalidCString
    }
  }

  @inlinable
  static func processBuffer<T>(_ buffer: UnsafeBufferPointer<T>) -> [T] {
    Array(buffer)
  }
}

extension ByteProcessor {
  enum ByteProcessingError: Error, LocalizedError, Throwable {
    case invalidUTF8
    case invalidCString
    case bufferOverflow

    var userFriendlyMessage: String {
      errorDescription ?? "Byte processing error"
    }

    var errorDescription: String? {
      switch self {
      case .invalidUTF8: "Invalid UTF-8"
      case .invalidCString: "Invalid C string"
      case .bufferOverflow: "Buffer overflow"
      }
    }
  }
}

struct ByteExtensions { }
