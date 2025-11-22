import ErrorKit
import Foundation
import Yams

struct YAMLDecoder {
  enum YAMLDecodingError: Error, LocalizedError, Throwable {
    case invalidUTF8
    case malformedYAML(String)

    var userFriendlyMessage: String {
      errorDescription ?? "YAML decoding error"
    }

    var errorDescription: String? {
      switch self {
      case .invalidUTF8: "Invalid UTF-8"
      case let .malformedYAML(details): "Malformed YAML: \(details)"
      }
    }
  }

  private func performParsing<T>(_ operation: () throws -> T) throws(ParsingError) -> T {
    try ParsingError.catch(operation)
  }

  func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
    let str = try ByteProcessor.processUTF8Data(data)
    let decoder = Yams.YAMLDecoder()
    do {
      return try performParsing {
        try decoder.decode(T.self, from: str)
      }
    } catch {
      throw YAMLDecodingError.malformedYAML(error.localizedDescription)
    }
  }

  func decode<T: Decodable>(_: T.Type, from string: String) throws -> T {
    _ = string.utf8Span
    let decoder = Yams.YAMLDecoder()
    do {
      return try performParsing {
        try decoder.decode(T.self, from: string)
      }
    } catch {
      throw YAMLDecodingError.malformedYAML(error.localizedDescription)
    }
  }
}

extension YAMLDecoder { }

enum YAMLExtensions { }
