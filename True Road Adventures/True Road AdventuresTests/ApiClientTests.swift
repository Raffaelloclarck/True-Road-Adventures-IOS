#if canImport(XCTest)
import XCTest
@testable import Rider

final class ApiClientTests: XCTestCase {
    func testConfigDefaults() {
        let config = AppConfig.load()
        XCTAssertFalse(config.apiBaseURL.absoluteString.isEmpty)
    }
}
#endif
