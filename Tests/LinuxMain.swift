import XCTest

import DispatchResultCompletionTests

var tests = [XCTestCaseEntry]()
tests += DispatchResultCompletionTests.allTests()
tests += ConcurrentResultsGeneratorTests.allTests()
XCTMain(tests)
