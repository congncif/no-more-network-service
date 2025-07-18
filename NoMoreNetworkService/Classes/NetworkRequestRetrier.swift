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
    init(retrier: any NetworkRequestRetrier) {
        self.retrier = retrier
    }

    private let retrier: any NetworkRequestRetrier
    private let lock = NSRecursiveLock()

    private var pendingCompletions: [(RetryPlan) -> Void] = []
    private var isProcessing: Bool = false

    func retry(dueTo error: Error, completion: @escaping (RetryPlan) -> Void) {
        lock.lock()

        if isProcessing {
            pendingCompletions.append(completion)
            lock.unlock()
            return
        }

        isProcessing = true
        pendingCompletions.append(completion)

        lock.unlock()

        retrier.retry(dueTo: error) { [weak self] shouldRetry in
            self?.complete(shouldRetry)
        }
    }

    deinit {
        lock.lock()
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        lock.unlock()

        for completion in completions {
            completion(.doNotRetry)
        }
    }

    private func complete(_ shouldRetry: RetryPlan) {
        lock.lock()
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        isProcessing = false
        lock.unlock()

        for completion in completions {
            completion(shouldRetry)
        }
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
            guard let self else {
                completion(.doNotRetry)
                return
            }
            switch plan {
            case .doNotRetry:
                retry(dueTo: error, using: pendingRetriers, completion: completion)
            case .retryNow:
                completion(plan)
            }
        }
    }
}
