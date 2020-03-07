//
//  VDLGCDHelpers
//  ConcurrentResultsGenerator.swift
//
//
//  Created by Valeriano Della Longa on 05/03/2020.
//  Copyright © 2020 Valeriano Della Longa. All rights reserved.
//
import Foundation

/// Convenience typealis for functional type representing a generator of *seed* of type `V` from another base *seed* of type `U` and an `Int`.
///
/// The generated *seed* is calculated over a base given *seed* of type `U` applying to it a
///  given `Int`.
public typealias SeedGenerator<U, V> = (U, Int) throws -> V

/// Convenience typealias for functional type representing a generator of *element* of type`T`.
///
/// This functional type takes a *seed* of type `V` and tries to generate an *element* of
///  type `T`.
public typealias ElementGenerator<T, V> = (V) throws -> T

/// Error thrown by the `concurrentResultsGenerator(countOfIterations:startingSeed:IterationSeeder:IterationGenerator:queue:completion:)` function.
public enum ConcurrentResultsGeneratorError: Error
{
    /// Signals an error happened during one or more iterations. Its associated value contains an
    ///  array of  all errors occurred for the failied iteration indexes.
    case iterationsFailures([(iterationIndex: Int, iterationError: Swift.Error)])
    
    /// Signals that some iterations were not performed internally.
    case someIterationsNotPerformed
}

/// Computes concurrently results from a generator which could be seeded by a value obtained
///  by an incrementing `Int` value and a base *seed* value, then delivers such results via completion closure.
///
/// Some for-in computations on a positive `Int` range of values are done in order to compute
///  a *seed* value which is then feeded to a generator of *element*. In such situations,
///  and when each *seed* computation is independent from each other, this work could be
///  done concurrently.
/// - Parameter countOfIterations: The number of iterations to do.
///  **Must** be positive.
/// - Parameter startingSeed: The starting *seed* value of type `U` from which each iteration's *seed* value is derived.
/// - Parameter iterationSeeder: A `SeedGenerator<U, V>` closure used to
/// generate a *seed* value of type `V` on each iteration.
/// - Parameter iterationGenerator: An `ElementGenerator<T, V>` closure used
///  to generate an *element* on each iteration.
/// - Parameter shouldNotCalculateMoreOnFirstError: Signals wheter the
/// computations should stop or continue as soon as an error is thrown by either the
/// `iterationSeeder` or the `iterationGenerator`. Defaults to `true`.
/// - Parameter queue: The `DispatchQueue` scheduler where to execute the given
/// completion closure. Can be omitted, in which case the completion gets executed on the same
/// thread were the callee was done.
/// - Parameter completion: A completion closure to execute with the result.
public func concurrentResultsGenerator<T, U, V>(
    countOfIterations: Int,
    startingSeed: U,
    iterationSeeder: @escaping SeedGenerator<U, V>,
    iterationGenerator: @escaping ElementGenerator<T, V>,
    shouldNotCalculateMoreOnFirstError: Bool = true,
    queue: DispatchQueue? = nil,
    completion: @escaping (Result<[T], Swift.Error>) -> Void
)
    -> Void
{
    // Check wheter the countOfIterations is negative.
    guard
        !(countOfIterations < 0)
        else {
            fatalError("Cannot perform a negative number of iterations!")
    }
    
    // The final result var.
    var result: Result<[T], Swift.Error>!
    
    // Check wheter the work has to get done or not:
    guard
        countOfIterations > 0
        else
    {
        // No iterations have to be performed, hence result is an empty
        // array.
        result = .success([])
        dispatchResultCompletion(result: result, queue: queue, completion: completion)
        return
    }
    
    // Setup some stuff before diving into the concurrent perform:
    // The results for each iteration: at every index of this array
    // we store the result of the corresponding iteration, hence
    // it has to be initilaized with the same count of the iterations
    // to perform with nil values
    var results = [Result<T, Swift.Error>?](repeating: nil, count: countOfIterations)
    // let's have a flag which also signlas if the whole operation
    // must be aborted
    var operationFailed = false
    // A reader-writer queue for writing and reading the shared
    // resources
    let readerWriter = DispatchQueue(label: "com.vdl.concurrent-calculator", attributes: .concurrent)
    // the dispatch group for the iterations
    let operationGroup = DispatchGroup()
    
    let _ = DispatchQueue.global(qos: .userInitiated)
    DispatchQueue.concurrentPerform(iterations: countOfIterations)
    { index in
        // An iteration began, hence we enter the group
        operationGroup.enter()
        // flag wheter this iteration should continue or not
        var iterationFailed = false
        if shouldNotCalculateMoreOnFirstError {
            // In case we ought stop when one operation failed,
            // then we ought check the shared flag:
            readerWriter.sync {
                iterationFailed = operationFailed
            }
        }
        
        guard
            !iterationFailed
            else {
                // In case the whole operation has to be aborted,
                // we signal the dispatch group and return
                operationGroup.leave()
                return
        }
        
        // Let's calculate this iteration result
        var iterationResult: Result<T, Swift.Error>!
        do {
            let iterationSeed = try iterationSeeder(startingSeed, index)
            let iterationValue = try iterationGenerator(iterationSeed)
            iterationResult = .success(iterationValue)
        } catch {
            iterationResult = .failure(error)
            iterationFailed = true
        }
        // We can now store it in the shared resources:
        readerWriter.async(flags: .barrier) {
            if (shouldNotCalculateMoreOnFirstError && iterationFailed && operationFailed == false),
                case .failure(let iterationError) = iterationResult
            {
                // we've got an error while calculating the iteration
                // result, and we're told to stop as we get one, hence
                // we set the oepration flag, set the final result.
                operationFailed = true
                result = .failure(ConcurrentResultsGeneratorError.iterationsFailures([(index, iterationError)]))
            } else {
                // Otherwise store the iteration result in the shared
                // container
                results[index] = iterationResult
            }
            // done, we can signal the dispatch group to leave.
            operationGroup.leave()
        }
    }
    
    // let's wait for all operations to perform
    operationGroup.wait()
    
    // let's get rid of the optionality for the iteration results:
    let allResults = results.compactMap { $0 }
    guard
        allResults.count == results.count
        else {
            // We didn't get the same number of non-nil results as the
            // iteration numbers.
            // This could have happened because we've stopped writing
            // iteration results because of an error during a
            // calculation and we had to stop on first error…
            //
            if !shouldNotCalculateMoreOnFirstError {
                // …or in case something went awry with the concurrent
                // perform mechanism, hence we set that kind of error
                // as final result.
                // This code branch should never execute.
                result = .failure(ConcurrentResultsGeneratorError.someIterationsNotPerformed)
            }
            
            // We can deliver the final result via given completion
            dispatchResultCompletion(result: result, queue: queue, completion: completion)
            return
    }
    
    // Let's get all values from the results:
    let allValues: [T] = allResults.compactMap { iterationResult in
        guard
            case .success(let value) = iterationResult
            else { return nil }
        return value
    }
    if allValues.count == allResults.count {
        // We've got all values for each iteration, the final result is
        // succesful though
        result = .success(allValues)
    } else {
        // We've gotten some iteration result as a failure result, let's
        // prepare the error for the final result…
        var idx = 0
        let allErrors: [(Int, Swift.Error)] = allResults.compactMap { iterationResult in
            defer { idx += 1 }
            guard
                case .failure(let error) = iterationResult
                else { return nil }
            return (idx, error)
        }
        // …and set it as the final result:
        result = .failure(ConcurrentResultsGeneratorError.iterationsFailures(allErrors))
    }
    
    // …Let's deliver the final result via given completion
    dispatchResultCompletion(result: result, queue: queue, completion: completion)
}
