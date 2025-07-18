//
//  NetworkResponseAdapter.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 26/07/2022.
//

import Foundation

public protocol NetworkResponseAdapter {
    func adapt(_ responseResult: Result<Data, Error>, completion: @escaping (Result<Data, Error>) -> Void)
}

public final class CompositeResponseAdapter: NetworkResponseAdapter {
    public let adapters: [any NetworkResponseAdapter]

    public init(adapters: [any NetworkResponseAdapter]) {
        self.adapters = adapters
    }

    public func adapt(_ responseResult: Result<Data, Error>, completion: @escaping (Result<Data, Error>) -> Void) {
        adapt(responseResult, using: adapters, completion: completion)
    }

    private func adapt(_ responseResult: Result<Data, Error>,
                       using adapters: [any NetworkResponseAdapter],
                       completion: @escaping (Result<Data, Error>) -> Void) {
        var pendingAdapters = adapters

        guard !pendingAdapters.isEmpty else {
            completion(responseResult)
            return
        }

        switch responseResult {
        case .failure:
            completion(responseResult)
            return
        case .success:
            break
        }

        let adapter = pendingAdapters.removeFirst()

        adapter.adapt(responseResult) { [weak self] result in
            guard let self else {
                completion(.failure(NSError(domain: "NoMoreNetworkService.CompositeResponseAdapter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Adapter has been deallocated"])))
                return
            }
            switch result {
            case .success:
                adapt(result, using: pendingAdapters, completion: completion)
            case .failure:
                completion(result)
            }
        }
    }
}
