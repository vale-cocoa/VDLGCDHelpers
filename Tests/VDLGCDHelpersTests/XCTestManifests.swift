import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(DispatchResultCompletionTests.allTests),
        testCase(ConcurrentResultsGeneratorTests.allTests),
        
    ]
}
#endif
