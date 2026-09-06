import AppKit
@testable import FluidVoice
import XCTest

@MainActor
final class AppDelegateTests: XCTestCase {
    func testClosingLastWindowDoesNotTerminateApplication() {
        let delegate = AppDelegate()

        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(.shared))
    }
}
