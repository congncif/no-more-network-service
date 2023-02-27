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

final class CompositeResponseAdapter: NetworkResponseAdapter {
    private let adapters: [NetworkResponseAdapter]

    public init(adapters: [NetworkResponseAdapter]) {
        self.adapters = adapters
    }

    func adapt(_ responseResult: Result<Data, Error>, completion: @escaping (Result<Data, Error>) -> Void) {
        adapt(responseResult, using: adapters, completion: completion)
    }

    private func adapt(_ responseResult: Result<Data, Error>,
                       using adapters: [NetworkResponseAdapter],
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
            switch result {
            case .success:
                self?.adapt(result, using: pendingAdapters, completion: completion)
            case .failure:
                completion(result)
            }
        }
    }
}
