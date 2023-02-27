//
//  NetworkServiceBuilder.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 21/07/2022.
//

import Foundation

public final class NetworkServiceBuilder {
    var configuration: URLSessionConfiguration = .default
    var serverTrustConfiguration: ServerTrustConfiguration?
    var requestAdapters: [NetworkRequestAdapter] = []
    var responseAdapters: [NetworkResponseAdapter] = []
    var retriers: [NetworkRequestRetrier] = []

    public static var `default`: NetworkServiceBuilder {
        NetworkServiceBuilder()
    }

    public func with(configuration: URLSessionConfiguration) -> Self {
        self.configuration = configuration
        return self
    }

    public func with(serverTrustConfiguration: ServerTrustConfiguration) -> Self {
        self.serverTrustConfiguration = serverTrustConfiguration
        return self
    }

    public func appending(retrier: NetworkRequestRetrier) -> Self {
        retriers.append(retrier)
        return self
    }

    public func appending(retriers: [NetworkRequestRetrier]) -> Self {
        self.retriers.append(contentsOf: retriers)
        return self
    }

    public func appending(requestAdapter: NetworkRequestAdapter) -> Self {
        requestAdapters.append(requestAdapter)
        return self
    }

    public func appending(requestAdapters: [NetworkRequestAdapter]) -> Self {
        self.requestAdapters.append(contentsOf: requestAdapters)
        return self
    }

    public func appending(responseAdapter: NetworkResponseAdapter) -> Self {
        responseAdapters.append(responseAdapter)
        return self
    }

    public func appending(responseAdapters: [NetworkResponseAdapter]) -> Self {
        self.responseAdapters.append(contentsOf: responseAdapters)
        return self
    }

    public func build() -> NetworkService {
        let sessionDelegate = SessionDelegate(serverTrustConfiguration: serverTrustConfiguration)
        let session = URLSession(configuration: configuration, delegate: sessionDelegate, delegateQueue: .main)
        let requestAdapter = CompositeRequestAdapter(adapters: requestAdapters)
        let responseAdapter = CompositeResponseAdapter(adapters: responseAdapters)
        let finalRetrier: NetworkRequestRetrier = FunnelRequestRetrier(retriers: retriers)

        return NetworkServiceProvider(session: session,
                                      requestAdapter: requestAdapter,
                                      responseAdapter: responseAdapter,
                                      retrier: finalRetrier,
                                      sessionDelegate: sessionDelegate)
    }
}
