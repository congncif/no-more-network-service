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
            switch result {
            case let .success(newRequest):
                self?.adapt(newRequest, using: pendingAdapters, completion: completion)
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
    init(adapter: any NetworkRequestAdapter) {
        self.adapter = adapter
    }

    let adapter: any NetworkRequestAdapter

    private let lock = NSRecursiveLock()

    private var _pendingCompletions: [(Result<URLRequest, any Error>) -> Void] = []
    private var pendingCompletions: [(Result<URLRequest, any Error>) -> Void] {
        set {
            lock.lock()
            _pendingCompletions = newValue
            lock.unlock()
        }

        get {
            lock.lock()
            defer { lock.unlock() }
            return _pendingCompletions
        }
    }

    private var _isProcessing: Bool = false
    private var isProcessing: Bool {
        set {
            lock.lock()
            _isProcessing = newValue
            lock.unlock()
        }

        get {
            lock.lock()
            defer { lock.unlock() }
            return _isProcessing
        }
    }

    func adapt(_ urlRequest: URLRequest, completion: @escaping (Result<URLRequest, any Error>) -> Void) {
        if isProcessing {
            pendingCompletions.append(completion)
        } else {
            isProcessing = true
            adapter.adapt(urlRequest) { [weak self] result in
                completion(result)
                self?.complete(result)
            }
        }
    }

    private func complete(_ result: Result<URLRequest, any Error>) {
        for completion in pendingCompletions {
            completion(result)
        }
        pendingCompletions.removeAll()
        isProcessing = false
    }
}
