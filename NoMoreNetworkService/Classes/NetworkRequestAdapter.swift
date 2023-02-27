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

final class CompositeRequestAdapter: NetworkRequestAdapter {
    private let adapters: [NetworkRequestAdapter]

    public init(adapters: [NetworkRequestAdapter]) {
        self.adapters = adapters
    }

    func adapt(_ urlRequest: URLRequest, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        adapt(urlRequest, using: adapters, completion: completion)
    }

    private func adapt(_ urlRequest: URLRequest,
                       using adapters: [NetworkRequestAdapter],
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
