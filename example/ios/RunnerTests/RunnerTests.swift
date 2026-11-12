import Flutter
import UIKit
import XCTest

// If your plugin has been explicitly set to "type: .dynamic" in the Package.swift,
// you will need to add your plugin as a dependency of RunnerTests within Xcode.

@testable import system_llm

/// Calls that need neither the language model nor the microphone.
@MainActor
class RunnerTests: XCTestCase {

  private func call(_ method: String, _ arguments: Any? = nil) -> Any? {
    let plugin = SystemLlmPlugin()
    var answer: Any?
    let answered = expectation(description: "\(method) answers")
    plugin.handle(FlutterMethodCall(methodName: method, arguments: arguments)) { result in
      answer = result
      answered.fulfill()
    }
    wait(for: [answered], timeout: 5)
    return answer
  }

  func testUnknownMethodIsNotImplemented() {
    XCTAssertTrue(call("getPlatformVersion") as AnyObject === FlutterMethodNotImplemented)
  }

  func testAvailabilityAnswersAKnownStatus() {
    let status = call("availability", ["locale": "en"]) as? String
    let known = ["available", "unsupported_language", "disabled", "model_not_ready", "unsupported"]
    XCTAssertTrue(known.contains(status ?? ""), "unexpected status \(String(describing: status))")
  }

  func testEnvironmentRejectsAPathAsDirectoryName() {
    let error = call("environment", ["directories": ["a/b"]]) as? FlutterError
    XCTAssertEqual(error?.code, "storage_error")
    XCTAssertNil(error?.message)
  }

  func testEnvironmentReportsCreatedDirectories() {
    let answer = call("environment", ["directories": ["runner_tests"]]) as? [String: Any]
    XCTAssertEqual(answer?["supported"] as? Bool, true)
    let paths = answer?["directories"] as? [String: String]
    XCTAssertNotNil(paths?["runner_tests"])
  }
}
