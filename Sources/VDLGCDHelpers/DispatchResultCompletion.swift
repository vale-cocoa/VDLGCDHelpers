import Foundation

/// Helper method for exectuing asynchronously a completion closure with
/// the given `Result<T, Error>` on the given `DispatchQueue`.
///
/// When the delivery of a `Result<T, Error>` value is supposed to be done asynchronously
///  via a completion closure of type `(Result<T, Error>) -> Void` it could be convenient
///  to have such closure being dispatched to a specific queue. This is true especially for cases where the closure needs to perform UI operation with the obtained result. This helper method
///  can be used in those APIs where an asynchronous method delivers its result via such
///  closures giving also the opportunity to specify on which queue such closure has to be
///  executed.
/// - Parameter result: the `Result` to feed to the given closure.
/// - Parameter queue: optional `DispatchQueue` where the completion will be
///  asynchronously dispatched.
/// - Parameter completion: The completion closure to execute.
public func dispatchResultCompletion<T>(result: Result<T, Error>, queue: DispatchQueue? = nil, completion: @escaping (Result<T, Error>) -> Void)
{
    guard
        let queue = queue
        else {
            completion(result)
            
            return
    }
    
    queue.async {
        completion(result)
    }
}
