import Foundation

struct Streaming { }

struct TrafficDataStream: AsyncSequence {
  typealias Element = TrafficSnapshot

  private let task: URLSessionWebSocketTask

  init(task: URLSessionWebSocketTask) {
    self.task = task
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(task: task)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
      self.task = task
    }

    mutating func next() async throws -> TrafficSnapshot? {
      let message = try await task.receive()

      switch message {
      case let .string(text):
        guard let data = text.data(using: .utf8) else {
          return nil
        }
        return try JSONDecoder().decode(TrafficSnapshot.self, from: data)

      case let .data(data):
        return try JSONDecoder().decode(TrafficSnapshot.self, from: data)

      @unknown default:
        return nil
      }
    }
  }
}

struct WebSocketMessageStream: AsyncSequence {
  typealias Element = String

  private let task: URLSessionWebSocketTask

  init(task: URLSessionWebSocketTask) {
    self.task = task
  }

  func makeAsyncIterator() -> AsyncIterator {
    AsyncIterator(task: task)
  }

  struct AsyncIterator: AsyncIteratorProtocol {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
      self.task = task
    }

    mutating func next() async throws -> String? {
      let message = try await task.receive()

      switch message {
      case let .string(text):
        return text

      case let .data(data):
        return String(data: data, encoding: .utf8)

      @unknown default:
        return nil
      }
    }
  }
}
