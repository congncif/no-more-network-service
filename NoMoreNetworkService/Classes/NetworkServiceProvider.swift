//
//  NetworkServiceProvider.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/05/2022.
//

import Foundation

final class NetworkServiceProvider: NetworkService {
    init(session: NetworkURLSession, requestAdapter: NetworkRequestAdapter, responseAdapter: NetworkResponseAdapter, retrier: NetworkRequestRetrier, maxRetries: Int, sessionDelegate: SessionDelegate) {
        self.session = session
        self.requestAdapter = requestAdapter
        self.responseAdapter = responseAdapter
        self.retrier = retrier
        self.maxRetries = maxRetries
        self.sessionDelegate = sessionDelegate
    }

    let session: NetworkURLSession
    let sessionDelegate: SessionDelegate
    let requestAdapter: NetworkRequestAdapter
    let responseAdapter: NetworkResponseAdapter
    let retrier: NetworkRequestRetrier
    let maxRetries: Int

    lazy var operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "no-more-network.request.operation-queue"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 3
        return queue
    }()

    func sendDataRequest(_ urlRequest: URLRequest, task: NetworkTask, progressHandler: ((Double) -> Void)?, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask {
        let operation = NetworkTaskExecutionOperation(session: session, requestAdapter: requestAdapter, responseAdapter: responseAdapter, retrier: retrier, maxRetries: maxRetries, urlRequest: urlRequest, task: task, progressHandler: progressHandler, completion: completion)
        operationQueue.addOperation(operation)
        let task = NetworkOperationTask(operation: operation)
        return task
    }

    deinit {
        operationQueue.cancelAllOperations()
    }
}

final class NetworkOperationTask: NetworkURLSessionTask {
    init(operation: NetworkTaskExecutionOperation?) {
        self.operation = operation
    }

    weak var operation: NetworkTaskExecutionOperation?

    let taskIdentifier: Int = UUID().hashValue

    func cancel() {
        operation?.cancel()
    }
}
