//
//  NetworkTaskExecutionOperation.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 1/8/24.
//

import Foundation

final class NetworkTaskExecutionOperation: Operation {
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
            let task = self.task

            requestAdapter.adapt(urlRequest) { [weak self] result in
                switch result {
                case let .success(request):
                    self?.pendingTask = self?.performRequest(request, task: task, progressHandler: self?.progressHandler, completion: { [weak self] responseResult in
                        self?.responseAdapter.adapt(responseResult, completion: { [weak self] newResult in
                            switch newResult {
                            case .success:
                                self?.completion(newResult)
                                self?.state = .finished
                            case let .failure(error):
                                self?.attemptRetry(dueTo: error, rawResult: newResult)
                            }
                        })
                    })
                case let .failure(error):
                    self?.completion(.failure(error))
                    self?.state = .finished
                }
            }
        }
    }

    private func attemptRetry(dueTo error: any Error, rawResult: Result<Data, Error>) {
        guard retryCount < maxRetries else {
            completion(rawResult)
            state = .finished
            return
        }
        retryCount += 1
        retrier.retry(dueTo: error, completion: { [weak self] shouldRetry in
            switch shouldRetry {
            case .retryNow:
                self?.main()
            case .doNotRetry:
                self?.completion(rawResult)
                self?.state = .finished
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
            if let error = error {
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
