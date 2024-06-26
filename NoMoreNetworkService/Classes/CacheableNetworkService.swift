//
//  CacheableNetworkService.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 26/6/24.
//

import Foundation

public protocol CacheStorage {
    func read() throws -> Data
    func write(_ data: Data?) throws
}

public protocol CacheStorageProvider {
    func cacheStorage(forRequest urlRequest: URLRequest) -> CacheStorage?
}

public final class CacheableNetworkService: NetworkService {
    let cacheStorageProvider: CacheStorageProvider
    let underlyingService: NetworkService

    public init(cacheStorageProvider: CacheStorageProvider, underlyingService: NetworkService) {
        self.cacheStorageProvider = cacheStorageProvider
        self.underlyingService = underlyingService
    }

    public func sendDataRequest(_ urlRequest: URLRequest, task: NetworkTask, completion: @escaping (Result<Data, any Error>) -> Void) -> any NetworkURLSessionTask {
        var finalCompletion = completion

        if let cacheStorage = cacheStorageProvider.cacheStorage(forRequest: urlRequest) {
            finalCompletion = { [weak self] result in
                switch result {
                case let .success(data):
                    self?.cacheQueue.async {
                        do {
                            try cacheStorage.write(data)
                        } catch {
                            #if DEBUG
                            print("⚠️ [NoMoreNetworkService] [\(Self.self)] Error while writing cache for request \(urlRequest) 👉 \(error)")
                            #endif
                        }
                    }
                default:
                    break
                }
                completion(result)
            }

            cacheQueue.async {
                do {
                    let data = try cacheStorage.read()
                    if !data.isEmpty {
                        completion(.success(data))
                    }
                } catch {
                    #if DEBUG
                    print("⚠️ [NoMoreNetworkService] [\(Self.self)] Error while reading cache for request \(urlRequest) 👉 \(error)")
                    #endif
                }
            }
        }

        return underlyingService.sendDataRequest(urlRequest, task: task, completion: finalCompletion)
    }

    private let cacheQueue = DispatchQueue(label: "no-more-network-service.cache", attributes: .concurrent)
}
