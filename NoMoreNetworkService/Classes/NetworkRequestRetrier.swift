//
//  NetworkRequestRetrier.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 22/07/2022.
//

import Foundation

public enum RetryPlan {
    case retryNow
    case doNotRetry
}

public protocol NetworkRequestRetrier {
    func retry(dueTo error: Error, completion: @escaping (RetryPlan) -> Void)
}

final class NoRetrier: NetworkRequestRetrier {
    func retry(dueTo _: Error, completion: @escaping (RetryPlan) -> Void) {
        completion(.doNotRetry)
    }
}

final class RetryBarrier: NetworkRequestRetrier {
    init(retrier: NetworkRequestRetrier) {
        self.retrier = retrier
    }

    let retrier: NetworkRequestRetrier

    private let lock = NSRecursiveLock()

    private var _pendingCompletions: [(RetryPlan) -> Void] = []
    private var pendingCompletions: [(RetryPlan) -> Void] {
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

    func retry(dueTo error: Error, completion: @escaping (RetryPlan) -> Void) {
        if isProcessing {
            pendingCompletions.append(completion)
        } else {
            isProcessing = true
            retrier.retry(dueTo: error) { [weak self] shouldRetry in
                completion(shouldRetry)
                self?.complete(shouldRetry)
            }
        }
    }

    private func complete(_ shouldRetry: RetryPlan) {
        pendingCompletions.forEach { completion in
            completion(shouldRetry)
        }
        pendingCompletions.removeAll()
        isProcessing = false
    }
}

public extension NetworkRequestRetrier {
    var withBarrier: NetworkRequestRetrier {
        RetryBarrier(retrier: self)
    }
}

public final class FunnelRequestRetrier: NetworkRequestRetrier {
    public let retriers: [NetworkRequestRetrier]

    public init(retriers: [NetworkRequestRetrier]) {
        self.retriers = retriers
    }

    public func retry(dueTo error: Error, completion: @escaping (RetryPlan) -> Void) {
        retry(dueTo: error, using: retriers, completion: completion)
    }

    private func retry(dueTo error: Error,
                       using retriers: [NetworkRequestRetrier],
                       completion: @escaping (RetryPlan) -> Void) {
        var pendingRetriers = retriers

        guard !pendingRetriers.isEmpty else {
            completion(.doNotRetry)
            return
        }

        let retrier = pendingRetriers.removeFirst()

        retrier.retry(dueTo: error) { [weak self] plan in
            switch plan {
            case .doNotRetry:
                self?.retry(dueTo: error, using: pendingRetriers, completion: completion)
            case .retryNow:
                completion(plan)
            }
        }
    }
}
