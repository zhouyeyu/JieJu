import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data?
    public let timeout: TimeInterval

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil, timeout: TimeInterval = 30) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let data: Data
    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

public struct HTTPDataStream: Sendable {
    public let statusCode: Int
    public let lines: AsyncThrowingStream<Data, Error>

    public init(statusCode: Int, lines: AsyncThrowingStream<Data, Error>) {
        self.statusCode = statusCode
        self.lines = lines
    }
}

public protocol StreamingHTTPClient: HTTPClient {
    func stream(_ request: HTTPRequest) async throws -> HTTPDataStream
}

public struct URLSessionHTTPClient: StreamingHTTPClient {
    public init() {}
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let urlRequest = request.urlRequest
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw ReadingAIError.transport("non-HTTP response")
            }
            return HTTPResponse(statusCode: http.statusCode, data: data)
        } catch let error as URLError where error.code == .timedOut {
            throw ReadingAIError.timeout
        } catch let error as ReadingAIError {
            throw error
        } catch {
            throw ReadingAIError.transport(error.localizedDescription)
        }
    }

    public func stream(_ request: HTTPRequest) async throws -> HTTPDataStream {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request.urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw ReadingAIError.transport("non-HTTP response")
            }
            let lines = AsyncThrowingStream<Data, Error> { continuation in
                let task = Task {
                    do {
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            continuation.yield(Data(line.utf8))
                        }
                        continuation.finish()
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                    } catch let error as URLError where error.code == .timedOut {
                        continuation.finish(throwing: ReadingAIError.timeout)
                    } catch let error as ReadingAIError {
                        continuation.finish(throwing: error)
                    } catch {
                        continuation.finish(throwing: ReadingAIError.transport(error.localizedDescription))
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
            return HTTPDataStream(statusCode: http.statusCode, lines: lines)
        } catch let error as URLError where error.code == .timedOut {
            throw ReadingAIError.timeout
        } catch let error as ReadingAIError {
            throw error
        } catch {
            throw ReadingAIError.transport(error.localizedDescription)
        }
    }
}

private extension HTTPRequest {
    var urlRequest: URLRequest {
        var result = URLRequest(url: url, timeoutInterval: timeout)
        result.httpMethod = method
        result.httpBody = body
        headers.forEach { result.setValue($1, forHTTPHeaderField: $0) }
        return result
    }
}
