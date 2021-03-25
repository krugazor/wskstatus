import XCTest

import wskstatusTests

var tests = [XCTestCaseEntry]()
tests += wskstatusTests.allTests()
XCTMain(tests)
