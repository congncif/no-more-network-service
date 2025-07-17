//
//  NetworkTaskExecutionOperation.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 1/8/24.
//

import Foundation

final class NetworkTaskExecutionOperation: Operation, @unchecked Sendable {
    init(session: NetworkURLSession, requestAdapter: NetworkRequestAdapter, responseAdapter: NetworkResponseAdapter, retrier: NetworkRequestRetrier, maxRetries: Int, urlRequest: URLRequest, task: NetworkTask, progressHandler: ((Double) -> Void)?, completion: @escaping (Result<Data, Error>) -> Void) {
        self.session = session
        self.requestAdapter = requestAdapter
        self.responseAdapter = responseAdapter
        self.retrier = retrier
        self.maxRetries = maxRetries
        self.urlRequest = urlRequest
        self.task = task
        self.progressHandler = progressHandler
        self.completion = completion
    }

    let session: NetworkURLSession
    let requestAdapter: NetworkRequestAdapter
    let responseAdapter: NetworkResponseAdapter
    let retrier: NetworkRequestRetrier
    let maxRetries: Int
    let urlRequest: URLRequest
    let task: NetworkTask
    let progressHandler: ((Double) -> Void)?
    let completion: (Result<Data, Error>) -> Void

    private var pendingTask: NetworkURLSessionTask?

    enum State: String {
        case ready = "Ready"
        case executing = "Executing"
        case finished = "Finished"

        fileprivate var keyPath: String { "is" + rawValue }
    }

    /// Thread-safe computed state value
    var state: State {
        get {
            stateQueue.sync {
                stateStore
            }
        }
        set {
            let oldValue = state
            willChangeValue(forKey: state.keyPath)
            willChangeValue(forKey: newValue.keyPath)
            stateQueue.sync(flags: .barrier) {
                stateStore = newValue
            }
            didChangeValue(forKey: state.keyPath)
            didChangeValue(forKey: oldValue.keyPath)
        }
    }

    var retryCount: Int {
        get {
            counterQueue.sync {
                _retryCount
            }
        }
        set {
            counterQueue.sync(flags: .barrier) {
                _retryCount = newValue
            }
        }
    }

    private let stateQueue = DispatchQueue(label: "no-more-network.request.operation.state", attributes: .concurrent)
    private let counterQueue = DispatchQueue(label: "no-more-network.request.operation.counter", attributes: .concurrent)

    /// Non thread-safe state storage, use only with locks
    private var stateStore: State = .ready
    private var _retryCount: Int = 0

    override var isAsynchronous: Bool {
        true
    }

    override var isExecuting: Bool {
        state == .executing
    }

    override var isFinished: Bool {
        state == .finished
    }

    override var isCancelled: Bool {
        state == .finished
    }

    override func cancel() {
        pendingTask?.cancel()
        state = .finished
    }

    override func start() {
        if isCancelled {
            state = .finished
        } else {
            state = .ready
            main()
        }
    }

    override func main() {
        if isCancelled {
            state = .finished
        } else {
            state = .executing
            let task = task

//            let completion = self.completion

            requestAdapter.adapt(urlRequest) { [weak self] result in
                guard let self else {
//                    This will return cancel error
//                    completion(result)
                    return
                }
                switch result {
                case let .success(request):
                    pendingTask = performRequest(request, task: task, progressHandler: progressHandler, completion: { [weak self] responseResult in
                        guard let self else {
//                            This will return cancel error
//                            completion(responseResult)
                            return
                        }
                        responseAdapter.adapt(responseResult, completion: { [weak self] newResult in
                            guard let self else {
//                                This will return cancel error
//                                completion(newResult)
                                return
                            }
                            switch newResult {
                            case .success:
                                completion(newResult)
                                state = .finished
                            case let .failure(error):
                                attemptRetry(dueTo: error, rawResult: newResult)
                            }
                        })
                    })
                case let .failure(error):
                    completion(.failure(error))
                    state = .finished
                }
            }
        }
    }

    private func attemptRetry(dueTo error: any Error, rawResult: Result<Data, Error>) {
        let completion = completion

        guard retryCount < maxRetries else {
            completion(rawResult)
            state = .finished
            return
        }

        retryCount += 1
        retrier.retry(dueTo: error, completion: { [weak self] shouldRetry in
            guard let self else {
//                This will return cancel error
//                completion(rawResult)
                return
            }

            switch shouldRetry {
            case .retryNow:
                main()
            case .doNotRetry:
                self.completion(rawResult)
                state = .finished
            }
        })
    }

    private func performRequest(_ urlRequest: URLRequest, task: NetworkTask, progressHandler: ((Double) -> Void)?, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask {
        #if DEBUG
        if NetworkLogMonitor.isEnabled {
            print(urlRequest.cURL(pretty: true))
        }
        #endif
        return session.performDataTask(task, request: urlRequest, progressHandler: progressHandler) { data, response, error in
            #if DEBUG
            if NetworkLogMonitor.isEnabled {
                print(log(urlRequest: urlRequest, data: data, response: response, error: error))
            }
            #endif
            if let error {
                completion(.failure(error))
            } else {
                guard let httpResponse = response as? HTTPURLResponse else {
                    let unknownError = NSError.network(url: urlRequest.url, code: NSURLErrorUnknown, message: "Invalid HTTPURLResponse", additionalInfo: [:])
                    completion(.failure(unknownError))
                    return
                }

                let statusCode = httpResponse.statusCode
                switch statusCode {
                case 200 ..< 300 where data != nil:
                    completion(.success(data!))
                default:
                    let statusError = NSError.network(
                        url: urlRequest.url,
                        code: statusCode,
                        message: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                        data: data,
                        additionalInfo: urlRequest.allHTTPHeaderFields
                    )
                    completion(.failure(statusError))
                }
            }
        }
    }
}

/**
 import Foundation

 final class NetworkTaskExecutionOperation: Operation, @unchecked Sendable {
     init(session: NetworkURLSession,
          requestAdapter: NetworkRequestAdapter,
          responseAdapter: NetworkResponseAdapter,
          retrier: NetworkRequestRetrier,
          maxRetries: Int,
          urlRequest: URLRequest,
          task: NetworkTask,
          progressHandler: ((Double) -> Void)? = nil,
          completion: @escaping (Result<Data, Error>) -> Void) {
         self.session = session
         self.requestAdapter = requestAdapter
         self.responseAdapter = responseAdapter
         self.retrier = retrier
         self.maxRetries = maxRetries
         self.urlRequest = urlRequest
         self.task = task
         self.progressHandler = progressHandler
         self.completion = completion
     }

     let session: NetworkURLSession
     let requestAdapter: NetworkRequestAdapter
     let responseAdapter: NetworkResponseAdapter
     let retrier: NetworkRequestRetrier
     let maxRetries: Int
     let urlRequest: URLRequest
     let task: NetworkTask
     let progressHandler: ((Double) -> Void)?
     let completion: (Result<Data, Error>) -> Void

     private let stateQueue = DispatchQueue(label: "operation.state.queue", attributes: .concurrent)
     private let retryQueue = DispatchQueue(label: "operation.retry.queue", attributes: .concurrent)
     private let finishLock = NSLock()
     private let completionLock = NSLock()
     private let pendingTaskLock = NSLock()

     private var _retryCount: Int = 0
     private var retryCount: Int {
         get { retryQueue.sync { _retryCount } }
         set { retryQueue.sync(flags: .barrier) { _retryCount = newValue } }
     }

     private var _state: State = .ready
     private var state: State {
         get { stateQueue.sync { _state } }
         set {
             let oldValue = _state
             willChangeValue(forKey: oldValue.keyPath)
             willChangeValue(forKey: newValue.keyPath)
             stateQueue.sync(flags: .barrier) { _state = newValue }
             didChangeValue(forKey: oldValue.keyPath)
             didChangeValue(forKey: newValue.keyPath)
         }
     }

     private var _hasFinished = false
     private var _hasCompleted = false

     private var _pendingTask: NetworkURLSessionTask?
     private var pendingTask: NetworkURLSessionTask? {
         get { pendingTaskLock.lock(); defer { pendingTaskLock.unlock() }; return _pendingTask }
         set { pendingTaskLock.lock(); _pendingTask = newValue; pendingTaskLock.unlock() }
     }

     override var isAsynchronous: Bool { true }
     override var isExecuting: Bool { state == .executing }
     override var isFinished: Bool { state == .finished }
     override var isCancelled: Bool { state == .finished }

     override func cancel() {
         pendingTask?.cancel()
         markFinishedOnce()
     }

     override func start() {
         if isCancelled {
             markFinishedOnce()
             return
         }
         state = .ready
         executeRequest()
     }

     private func executeRequest() {
         if isCancelled {
             markFinishedOnce()
             return
         }
         state = .executing

         requestAdapter.adapt(urlRequest) { [weak self] result in
             guard let self else { return }
             switch result {
             case let .success(adaptedRequest):
                 self.pendingTask = self.performRequest(adaptedRequest)
             case let .failure(error):
                 self.callCompletionOnce(.failure(error))
                 self.markFinishedOnce()
             }
         }
     }

     private func performRequest(_ request: URLRequest) -> NetworkURLSessionTask {
         session.performDataTask(task, request: request, progressHandler: progressHandler) { [weak self] data, response, error in
             guard let self else { return }

             if let error {
                 self.handleResponse(.failure(error))
             } else {
                 guard let httpResponse = response as? HTTPURLResponse else {
                     let unknownError = NSError(domain: "Network", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                     self.handleResponse(.failure(unknownError))
                     return
                 }

                 let statusCode = httpResponse.statusCode
                 if (200..<300).contains(statusCode), let data {
                     self.handleResponse(.success(data))
                 } else {
                     let error = NSError(domain: "Network", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
                     self.handleResponse(.failure(error))
                 }
             }
         }
     }

     private func handleResponse(_ result: Result<Data, Error>) {
         responseAdapter.adapt(result) { [weak self] adaptedResult in
             guard let self else { return }

             switch adaptedResult {
             case .success:
                 self.callCompletionOnce(adaptedResult)
                 self.markFinishedOnce()
             case let .failure(error):
                 self.attemptRetry(dueTo: error, result: adaptedResult)
             }
         }
     }

     private func attemptRetry(dueTo error: Error, result: Result<Data, Error>) {
         guard retryCount < maxRetries else {
             callCompletionOnce(result)
             markFinishedOnce()
             return
         }

         retryCount += 1
         retrier.retry(dueTo: error) { [weak self] plan in
             guard let self else { return }
             switch plan {
             case .retryNow:
                 self.executeRequest()
             case .doNotRetry:
                 self.callCompletionOnce(result)
                 self.markFinishedOnce()
             }
         }
     }

     private func callCompletionOnce(_ result: Result<Data, Error>) {
         completionLock.lock()
         defer { completionLock.unlock() }
         guard !_hasCompleted else { return }
         _hasCompleted = true
         completion(result)
     }

     private func markFinishedOnce() {
         finishLock.lock()
         defer { finishLock.unlock() }
         guard !_hasFinished else { return }
         _hasFinished = true
         state = .finished
     }

     enum State: String {
         case ready = "Ready"
         case executing = "Executing"
         case finished = "Finished"

         var keyPath: String { "is" + rawValue }
     }
 }
 */
