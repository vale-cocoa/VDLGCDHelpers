//
//  VDLGCDHelpersTests
//  DispatchResultCompletionTests.swift
//
//
//  Created by Valeriano Della Longa on 07/03/2020.
//  Copyright © 2020 Valeriano Della Longa. All rights reserved.
//
import XCTest
@testable import VDLGCDHelpers

final class DispatchResultCompletionTests: XCTestCase {
    var result: Result<Int, Error>!
    
    var expectedResult: Result<Int, Error>!
    
    override func setUp() {
        super.setUp()
        
    }
    
    override func tearDown() {
        result = nil
        expectedResult = nil
        
        super.tearDown()
    }
    
    // MARK: - Then
    func thenResultIsExpected()
    {
        switch (result, expectedResult) {
        case (nil, nil), (nil, _), (_, nil):
            fatalError("Not set both result and expectedResult")
        case (.success(let concreteResult), .success(let concreteExpectedResult)):
            XCTAssertEqual(concreteResult, concreteExpectedResult)
        case (.failure(let resultError as NSError), .failure(let expectedError as NSError)):
            XCTAssertEqual(resultError.domain, expectedError.domain)
            XCTAssertEqual(resultError.code, expectedError.code)
        default:
            XCTFail("result: \(String(describing: result)) - expectedResult: \(String(describing: expectedResult))")
        }
    }
    
    // MARK: - Tests
    func test_executesCompletionWithGivenResult()
    {
        // given
        expectedResult = .success(Int.random(in: 1...100))
        
        // when
        let exp = expectation(description: "closure executes")
        DispatchQueue.global(qos: .default).async {
            dispatchResultCompletion(result: self.expectedResult, completion: {
                self.result = $0
                exp.fulfill()
            })
        }
        wait(for: [exp], timeout: 0.25)
        
        // then
        thenResultIsExpected()
    }
    
    func test_whenExecutedOnOtherThreadAndQueueIsNil_DoesntDispatchesOnMainThread()
    {
        // given
        let resultToDeliver: Result<Int, Error> = .success(10)
        let exp = expectation(description: "completion executes")
        var thread: Thread!
        
        // when
        DispatchQueue.global(qos: .default).async {
            dispatchResultCompletion(result: resultToDeliver, completion: {_ in
                thread = Thread.current
                exp.fulfill()
            })
        }
        wait(for: [exp], timeout: 0.25)
        
        // then
        XCTAssertFalse(thread.isMainThread)
    }
    
    func test_whenExecutedOnOtherThreadAndQueueIsMain_dispatchesOnMainThread()
    {
        // given
        let resultToDeliver: Result<Int, Error> = .success(10)
        let exp = expectation(description: "completion executes")
        var thread: Thread!
        
        // when
        DispatchQueue.global(qos: .default).async {
            dispatchResultCompletion(result: resultToDeliver, queue: DispatchQueue.main, completion: {_ in
                thread = Thread.current
                exp.fulfill()
            })
        }
        wait(for: [exp], timeout: 0.25)
        
        // then
        XCTAssertTrue(thread.isMainThread)
    }
    
    static var allTests = [
        ("test_executesCompletionWithGivenResult", test_executesCompletionWithGivenResult),
        ("test_whenExecutedOnOtherThreadAndQueueIsNil_DoesntDispatchesOnMainThread", test_whenExecutedOnOtherThreadAndQueueIsNil_DoesntDispatchesOnMainThread),
        
    ]
}
