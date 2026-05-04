import XCTest
@testable import Rider
import Network

final class ApiClientTests: XCTestCase {
    func testSendDecodesSuccessfulResponse() async throws {
        let expectation = expectation(description: "request hit")
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/ping")
            expectation.fulfill()
            let json = #"{"message":"pong"}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let client = ApiClient(
            baseURL: URL(string: "https://api.dev.trueroad.app")!,
            session: mockSession()
        )

        struct Ping: Decodable { let message: String }
        let result: Ping = try await client.send(.init(path: "/ping"))
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(result.message, "pong")
    }

    func testSendUnauthorizedThrows() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = ApiClient(
            baseURL: URL(string: "https://api.dev.trueroad.app")!,
            session: mockSession()
        )

        await XCTAssertThrowsErrorAsync(try await client.send(ApiRequest(path: "/secure"), decode: EmptyResponse.self, token: "token")) { error in
            guard case ApiError.unauthorized = error else {
                XCTFail("Expected unauthorized, got \(error)")
                return
            }
        }
    }

    func testRideServiceOfflineThrows() async {
        let rideService = RideService(
            repository: InMemoryRideRepository(),
            navigationManager: NavigationSessionManager(directionsClient: DirectionsClient(apiKey: nil)),
            networkMonitor: NetworkMonitor(mockStatus: .unsatisfied)
        )
        do {
            try await rideService.updateStatus("dummy", status: .completed)
            XCTFail("Expected offline error")
        } catch RideService.RideActionError.offline {
            // expected
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    private func mockSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private struct EmptyResponse: Decodable { }

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            fatalError("No handler set")
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (_ error: Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
