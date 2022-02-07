import XCTest
@testable import CocoaSpice

final class CocoaSpiceTests: XCTestCase {
    func testConnect() throws {
        let connection = CSConnection(host: "127.0.0.1", port: "4444")
        connection.connect()
    }
}
