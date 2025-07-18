//
//  NetworkRequestAdapter.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 21/07/2022.
//

import Foundation

public protocol NetworkRequestAdapter {
    func adapt(_ urlRequest: URLRequest, completion: @escaping (Result<URLRequest, Error>) -> Void)
}

public final class CompositeRequestAdapter: NetworkRequestAdapter {
    public let adapters: [any NetworkRequestAdapter]

    public init(adapters: [any NetworkRequestAdapter]) {
        self.adapters = adapters
    }

    public func adapt(_ urlRequest: URLRequest, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, using: adapters, completion: completion)
    }

    private func adapt(_ urlRequest: URLRequest,
                       using adapters: [any NetworkRequestAdapter],
                       completion: @escaping (Result<URLRequest, Error>) -> Void) {
        var pendingAdapters = adapters

        guard !pendingAdapters.isEmpty else {
            completion(.success(urlRequest))
            return
        }

        let adapter = pendingAdapters.removeFirst()

        adapter.adapt(urlRequest) { [weak self] result in
            guard let self else {
                completion(.failure(NSError(domain: "NoMoreNetworkService.CompositeRequestAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Adapter has been deallocated"])))
                return
            }
            switch result {
            case let .success(newRequest):
                adapt(newRequest, using: pendingAdapters, completion: completion)
            case .failure:
                completion(result)
            }
        }
    }
}

public extension NetworkRequestAdapter {
    var withBarrier: NetworkRequestAdapter {
        RequestAdapterBarrier(adapter: self)
    }
}

final class RequestAdapterBarrier: NetworkRequestAdapter {
    init(adapter: NetworkRequestAdapter) {
        self.adapter = adapter
    }

    private let adapter: NetworkRequestAdapter
    private let lock = NSRecursiveLock()
    private var requestQueue: [(request: URLRequest, completion: (Result<URLRequest, Error>) -> Void)] = []
    private var isProcessing = false

    func adapt(_ urlRequest: URLRequest, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        lock.lock()

        requestQueue.append((urlRequest, completion))

        if isProcessing {
            lock.unlock()
            return
        }

        isProcessing = true
        let currentRequest = requestQueue.first!
        lock.unlock()

        adapter.adapt(currentRequest.request) { [weak self] result in
            self?.handleCompletion(result: result)
        }
    }

    deinit {
        lock.lock()
        let currentQueue = requestQueue
        requestQueue.removeAll()
        isProcessing = false
        lock.unlock()

        for (_, completion) in currentQueue {
            completion(.failure(NSError(domain: "RequestAdapterBarrier", code: -1, userInfo: [NSLocalizedDescriptionKey: "Adapter has been deallocated"])))
        }
    }

    private func handleCompletion(result: Result<URLRequest, any Error>) {
        lock.lock()

        guard !requestQueue.isEmpty else {
            isProcessing = false
            lock.unlock()
            return
        }

        let (_, completion) = requestQueue.removeFirst()
        completion(result)

        if let nextRequest = requestQueue.first {
            lock.unlock()
            adapter.adapt(nextRequest.request) { [weak self] result in
                self?.handleCompletion(result: result)
            }
        } else {
            isProcessing = false
            lock.unlock()
        }
    }
}
