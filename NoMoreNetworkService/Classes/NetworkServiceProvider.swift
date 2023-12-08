//
//  NetworkServiceProvider.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/05/2022.
//

import Foundation
import Security

final class NetworkServiceProvider: NetworkService {
    init(session: NetworkURLSession, requestAdapter: NetworkRequestAdapter, responseAdapter: NetworkResponseAdapter, retrier: NetworkRequestRetrier, sessionDelegate: SessionDelegate) {
        self.session = session
        self.requestAdapter = requestAdapter
        self.responseAdapter = responseAdapter
        self.retrier = retrier
        self.sessionDelegate = sessionDelegate
    }

    let session: NetworkURLSession
    let sessionDelegate: SessionDelegate
    let requestAdapter: NetworkRequestAdapter
    let responseAdapter: NetworkResponseAdapter
    let retrier: NetworkRequestRetrier

    lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "no-more-network.request.operation-queue"
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 3
        return queue
    }()

    func sendDataRequest(_ urlRequest: URLRequest, task: NetworkTask, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask {
        let operation = NetworkTaskExecutionOperation(session: session, requestAdapter: requestAdapter, responseAdapter: responseAdapter, retrier: retrier, urlRequest: urlRequest, task: task, completion: completion)
        operationQueue.addOperation(operation)

        let task = NetworkOperationTask(operation: operation)
        return task
    }
}

final class SessionDelegate: NSObject, URLSessionDelegate {
    let serverTrustConfiguration: ServerTrustConfiguration?

    init(serverTrustConfiguration: ServerTrustConfiguration?) {
        self.serverTrustConfiguration = serverTrustConfiguration
        super.init()
    }

    func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let host = challenge.protectionSpace.host

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let evaluators = serverTrustConfiguration?.evaluations[host], !evaluators.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard challenge.previousFailureCount == 0 else {
            completionHandler(.rejectProtectionSpace, nil)
            return
        }

        // Set policy to validate domain
        let policy = SecPolicyCreateSSL(true, host as CFString)
        let policies = NSArray(object: policy)
        SecTrustSetPolicies(serverTrust, policies)

        for evaluator in evaluators {
            if evaluator.evaluate(secTrust: serverTrust) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return // exit as soon as we found a match
            }
        }

        // No valid cert available
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

final class NetworkTaskExecutionOperation: Operation {
    init(session: NetworkURLSession, requestAdapter: NetworkRequestAdapter, responseAdapter: NetworkResponseAdapter, retrier: NetworkRequestRetrier, urlRequest: URLRequest, task: NetworkTask, completion: @escaping (Result<Data, Error>) -> Void) {
        self.session = session
        self.requestAdapter = requestAdapter
        self.responseAdapter = responseAdapter
        self.retrier = retrier
        self.urlRequest = urlRequest
        self.task = task
        self.completion = completion
    }

    let session: NetworkURLSession
    let requestAdapter: NetworkRequestAdapter
    let responseAdapter: NetworkResponseAdapter
    let retrier: NetworkRequestRetrier
    let urlRequest: URLRequest
    let task: NetworkTask
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

    private let stateQueue = DispatchQueue(label: "no-more-network.request.operation", attributes: .concurrent)

    /// Non thread-safe state storage, use only with locks
    private var stateStore: State = .ready

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
                    self?.pendingTask = self?.performRequest(request, task: task, completion: { [weak self] responseResult in
                        self?.responseAdapter.adapt(responseResult, completion: { [weak self] newResult in
                            switch newResult {
                            case .success:
                                self?.completion(newResult)
                                self?.state = .finished
                            case let .failure(error):
                                self?.retrier.retry(dueTo: error, completion: { [weak self] shouldRetry in
                                    switch shouldRetry {
                                    case .retryNow:
                                        self?.main()
                                    case .doNotRetry:
                                        self?.completion(newResult)
                                        self?.state = .finished
                                    }
                                })
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

    private func performRequest(_ urlRequest: URLRequest, task: NetworkTask, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask {
        #if DEBUG
        if NetworkLogMonitor.isEnabled {
            print(urlRequest.cURL(pretty: true))
        }
        #endif
        return session.performDataTask(task, request: urlRequest) { data, response, error in
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

struct NetworkOperationTask: NetworkURLSessionTask {
    weak var operation: NetworkTaskExecutionOperation?

    let taskIdentifier: Int = UUID().hashValue

    func cancel() {
        operation?.cancel()
    }
}
