//
//  VDLGCDHelpersTests
//  ConcurrentResultsGeneratorTests.swift
//  
//
//  Created by Valeriano Della Longa on 07/03/2020.
//  Copyright © 2020 Valeriano Della Longa. All rights reserved.
//
import XCTest
@testable import VDLGCDHelpers

final class ConcurrentResultsGeneratorTests: XCTestCase {
    enum TestError: Error {
        case failureOnSeedGenerator
        case failureOnElementGenerator
    }
    
    // MARK: - Given
    func givenDummySeeder(string: String, int: Int) -> CGFloat {
        return 0.0
    }
    
    func givenDummyElementGenerator(cgFloat: CGFloat) -> CGPoint {
        return CGPoint()
    }
    
    func givenSeederFromArrayOfStrings(strings: [String], index: Int) throws -> CGFloat
    {
        guard
            0..<strings.count ~= index,
            let y = Int(strings[index])
            else { throw TestError.failureOnSeedGenerator }
        
        return CGFloat(y)
    }
    
    func givenSimpleElementGeneratorFailingWhenFeedValueGraterThan30(y: CGFloat) throws -> CGPoint
    {
        let x = y * y
        guard
            x <= 900
            else { throw TestError.failureOnElementGenerator }
        
        return CGPoint(x: x, y: y)
    }
    
    func givenSimpleElementGeneratorNotFailing(y: CGFloat) -> CGPoint
    {
        let x = y * y
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - When
    
    // MARK: - Then
    func thenResultIsExpected<T>(result: Result<T, Swift.Error>, expected: Result<T, Swift.Error>)
        where T: Equatable
    {
        switch (result, expected) {
        case (.success(let concreteResult), .success(let concreteExpectedResult)):
            XCTAssertEqual(concreteResult, concreteExpectedResult)
        case (.failure(let error as ConcurrentResultsGeneratorError), .failure(let expectedError as ConcurrentResultsGeneratorError)):
            thenConcurrentResultGeneratorErrorsAreEqual(lhs: error, rhs: expectedError)
        case (.failure(let error as NSError), .failure(let expectedError as NSError)):
            XCTAssertEqual(error.domain, expectedError.domain)
            XCTAssertEqual(error.code, expectedError.code)
        default:
            XCTFail("result: \(String(describing: result)) - expectedResult: \(String(describing: expected))")
        }
    }
    
    func thenConcurrentResultGeneratorErrorsAreEqual(lhs: ConcurrentResultsGeneratorError, rhs: ConcurrentResultsGeneratorError)
    {
        let lhsNSError = lhs as NSError
        let rhsNSError = rhs as NSError
        XCTAssertEqual(lhsNSError.domain, rhsNSError.domain)
        XCTAssertEqual(lhsNSError.code, rhsNSError.code)
        if
            case ConcurrentResultsGeneratorError.iterationsFailures(let lhsIterationsErrors) = lhs,
            case ConcurrentResultsGeneratorError.iterationsFailures(let rhsIterationsErrors) = rhs
        {
            XCTAssertEqual(lhsIterationsErrors.count, rhsIterationsErrors.count)
            let lhsSorted = lhsIterationsErrors.sorted(by: { $0.0 < $1.0 })
            let rhsSorted = rhsIterationsErrors.sorted(by: { $0.0 < $1.0  })
            for idx in 0..<lhsIterationsErrors.count
            {
                XCTAssertEqual(lhsSorted[idx].iterationIndex, rhsSorted[idx].iterationIndex)
                let lhsErr = lhsSorted[idx].iterationError as NSError
                let rhsErr = rhsSorted[idx].iterationError as NSError
                XCTAssertEqual(lhsErr.domain, rhsErr.domain)
                XCTAssertEqual(lhsErr.code, rhsErr.code)
            }
        }
        
    }
    
    // MARK: - Tests
    func test_completionExecutes()
    {
        // given
        var completionExecutes = false
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 100,
                startingSeed: "Starting Seed",
                iterationSeeder: self.givenDummySeeder(string:int:),
                iterationGenerator: self.givenDummyElementGenerator(cgFloat:),
                completion: {_ in
                    completionExecutes = true
                    exp.fulfill()
            })
        }
        // then
        wait(for: [exp], timeout: 0.2)
        XCTAssertTrue(completionExecutes)
    }
    
    func test_completionExecutesOnGivenQueue() {
        // given
        var thread: Thread!
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 100,
                startingSeed: "Starting Seed",
                iterationSeeder: self.givenDummySeeder(string:int:),
                iterationGenerator: self.givenDummyElementGenerator(cgFloat:),
                queue: .main,
                completion: {_ in
                    thread = Thread.current
                    exp.fulfill()
            })
        }
        // then
        wait(for: [exp], timeout: 0.2)
        XCTAssertEqual(thread, Thread.main)
    }
    
    func test_whenCountOfIterationsIsZero_resultIsEmptyArray()
    {
        // given
        let expectedResult: Result<[CGPoint], Swift.Error> = .success([])
        var result: Result<[CGPoint], Swift.Error>!
        
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 0,
                startingSeed: "Starting Seed",
                iterationSeeder: self.givenDummySeeder(string:int:),
                iterationGenerator: self.givenDummyElementGenerator(cgFloat:),
                completion: {generatedResult in
                    result = generatedResult
                    exp.fulfill()
            })
        }
        // then
        wait(for: [exp], timeout: 0.2)
        thenResultIsExpected(result: result, expected: expectedResult)
    }
    
    func test_whenShouldStopOnFirstErrorIsTrue_resultContainsOneErrorOnly()
    {
        // given
        let alwaysFailingSeeder: (String, Int) throws -> CGFloat = { _, _ in throw TestError.failureOnSeedGenerator }
        var result: Result<[CGPoint], Swift.Error>!
        
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 1000,
                startingSeed: "Starting Seed",
                iterationSeeder: alwaysFailingSeeder,
                iterationGenerator: self.givenDummyElementGenerator(cgFloat:),
                shouldNotCalculateMoreOnFirstError: true,
                completion: { generated in
                    result = generated
                    exp.fulfill()
            })
        }
        
        // then
        wait(for: [exp], timeout: 0.2)
        guard
            case .failure(let error) = result,
            case ConcurrentResultsGeneratorError.iterationsFailures(let failures) = error
            else {
                XCTFail("result: \(String(describing: result))")
                return
        }
        
        XCTAssertEqual(failures.count, 1)
    }
    
    func test_whenShouldStopOnFirstErrorIsFalse_resultContainsMoreErrors()
    {
        // given
        let alwaysFailingSeeder: (String, Int) throws -> CGFloat = { _, _ in throw TestError.failureOnSeedGenerator }
        var result: Result<[CGPoint], Swift.Error>!
        
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 1000,
                startingSeed: "Starting Seed",
                iterationSeeder: alwaysFailingSeeder,
                iterationGenerator: self.givenDummyElementGenerator(cgFloat:),
                shouldNotCalculateMoreOnFirstError: false,
                completion: { generated in
                    result = generated
                    exp.fulfill()
            })
        }
        
        // then
        wait(for: [exp], timeout: 0.2)
        guard
            case .failure(let error) = result,
            case ConcurrentResultsGeneratorError.iterationsFailures(let failures) = error
            else {
                XCTFail("result: \(String(describing: result))")
                return
        }
        
        XCTAssertEqual(failures.count, 1000)
    }
    
    func test_whenSeedGeneratorFails_resultIsExpected() {
        // given
        let strings = [String](repeating: "10", count: 999)
        let expectedResult: Result<[CGPoint], Swift.Error> = .failure(ConcurrentResultsGeneratorError.iterationsFailures([(999, TestError.failureOnSeedGenerator)]))
        var result: Result<[CGPoint], Swift.Error>!
        
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 1000,
                startingSeed: strings,
                iterationSeeder: self.givenSeederFromArrayOfStrings(strings:index:),
                iterationGenerator: self.givenDummyElementGenerator(cgFloat:),
                completion: { generated in
                    result = generated
                    exp.fulfill()
            })
        }
        
        // then
        wait(for: [exp], timeout: 0.2)
        thenResultIsExpected(result: result, expected: expectedResult)
    }
    
    func test_whenElementGeneratorFails_resultIsExpected()
    {
        // given
        var strings = [String](repeating: "10", count: 1000)
        strings[200] = "31"
        let expectedResult: Result<[CGPoint], Swift.Error> = .failure(ConcurrentResultsGeneratorError.iterationsFailures([(200, TestError.failureOnElementGenerator)]))
        var result: Result<[CGPoint], Swift.Error>!
        
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 1000,
                startingSeed: strings,
                iterationSeeder: self.givenSeederFromArrayOfStrings(strings:index:),
                iterationGenerator: self.givenSimpleElementGeneratorFailingWhenFeedValueGraterThan30(y:),
                completion: { generated in
                    result = generated
                    exp.fulfill()
            })
        }
        
        // then
        wait(for: [exp], timeout: 0.2)
        thenResultIsExpected(result: result, expected: expectedResult)
    }
    
    func test_whenNoneFails_resultIsSuccess()
    {
        // given
        let strings = [String](repeating: "10", count: 1000)
        var result: Result<[CGPoint], Swift.Error>!
        
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 1000,
                startingSeed: strings,
                iterationSeeder: self.givenSeederFromArrayOfStrings(strings:index:),
                iterationGenerator: self.givenSimpleElementGeneratorNotFailing(y:),
                completion: { generated in
                    result = generated
                    exp.fulfill()
            })
        }
        // then
        wait(for: [exp], timeout: 0.2)
        if case .failure = result {
            XCTFail("Got .failure and not .success")
        }
    }
    
    func test_whenNoneFails_resultIsExpected()
    {
        // given
        let strings = [String](repeating: "10", count: 1000)
        let expectedResult: Result<[CGPoint], Swift.Error> = .success([CGPoint](repeating: CGPoint(x: 100, y: 10), count: 1000))
        var result: Result<[CGPoint], Swift.Error>!
        
        // when
        let exp = expectation(description: "completion executes")
        DispatchQueue.global(qos: .default).async {
            concurrentResultsGenerator(
                countOfIterations: 1000,
                startingSeed: strings,
                iterationSeeder: self.givenSeederFromArrayOfStrings(strings:index:),
                iterationGenerator: self.givenSimpleElementGeneratorNotFailing(y:),
                completion: { generated in
                    result = generated
                    exp.fulfill()
            })
        }
        // then
        wait(for: [exp], timeout: 0.2)
        thenResultIsExpected(result: result, expected: expectedResult)
    }
    
    static var allTests = [
        ("test_completionExecutes", test_completionExecutes),
        ("test_completionExecutesOnGivenQueue", test_completionExecutesOnGivenQueue),
        ("test_whenCountOfIterationsIsZero_resultIsEmptyArray", test_whenCountOfIterationsIsZero_resultIsEmptyArray),
        ("test_whenShouldStopOnFirstErrorIsTrue_resultContainsOneErrorOnly", test_whenShouldStopOnFirstErrorIsTrue_resultContainsOneErrorOnly),
        ("test_whenShouldStopOnFirstErrorIsFalse_resultContainsMoreErrors", test_whenShouldStopOnFirstErrorIsFalse_resultContainsMoreErrors),
        ("test_whenSeedGeneratorFails_resultIsExpected", test_whenSeedGeneratorFails_resultIsExpected),
        ("test_whenElementGeneratorFails_resultIsExpected", test_whenElementGeneratorFails_resultIsExpected),
        ("test_whenNoneFails_resultIsSuccess", test_whenNoneFails_resultIsSuccess),
        ("test_whenNoneFails_resultIsExpected", test_whenNoneFails_resultIsExpected),
        
    ]
    
}
