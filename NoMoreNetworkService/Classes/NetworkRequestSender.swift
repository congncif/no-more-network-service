//
//  NetworkRequestSender.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 2/8/24.
//

import Foundation

public final class NetworkRequestSender {
    let networkService: any NetworkService
    let urlRequest: URLRequest

    init(networkService: any NetworkService, urlRequest: URLRequest) {
        self.networkService = networkService
        self.urlRequest = urlRequest
    }

    var task: NetworkTask = .data

    var progressHandler: ((Double) -> Void)?

    var completionHandler: (Result<Data, any Error>) -> Void = { _ in }
}

public extension NetworkRequestSender {
    func forTask(_ task: NetworkTask) -> Self {
        self.task = task
        return self
    }

    func onProgress(handler: ((Double) -> Void)?) -> Self {
        progressHandler = handler
        return self
    }

    func onCompleted(handler: @escaping (Result<Data, any Error>) -> Void) -> Self {
        completionHandler = handler
        return self
    }

    @discardableResult
    func send(queue: DispatchQueue? = nil) -> NetworkURLSessionTask {
        if let queue {
            let task = CancellableSessionTaskProxy()
            queue.async {
                let underlyingTask = self.networkService.sendDataRequest(self.urlRequest, task: self.task, progressHandler: self.progressHandler, completion: self.completionHandler)
                task.underlyingTask = underlyingTask
            }
            return task
        } else {
            return networkService.sendDataRequest(urlRequest, task: task, progressHandler: progressHandler, completion: completionHandler)
        }
    }
}

final class CancellableSessionTaskProxy: NetworkURLSessionTask {
    weak var underlyingTask: NetworkURLSessionTask?

    let taskIdentifier: Int = UUID().hashValue

    func cancel() {
        underlyingTask?.cancel()
    }
}

// MARK: - Decode response model

public extension NetworkRequestSender {
    func decodeResponse<ResponseModel: DecodableNetworkResponseModel>(to modelType: ResponseModel.Type) -> DecodableNetworkRequestSenderProxy<ResponseModel> {
        DecodableNetworkRequestSenderProxy<ResponseModel>(sender: self)
    }
}

public final class DecodableNetworkRequestSenderProxy<ResponseModel: DecodableNetworkResponseModel> {
    let sender: NetworkRequestSender

    init(sender: NetworkRequestSender) {
        self.sender = sender
    }
}

public extension DecodableNetworkRequestSenderProxy {
    func onCompleted(handler: @escaping (Result<ResponseModel, any Error>) -> Void) -> NetworkRequestSender {
        return sender.onCompleted { result in
            switch result {
            case let .success(data):
                do {
                    let model = try ResponseModel.decodeFromData(data)
                    handler(.success(model))
                } catch let decodingError {
                    #if DEBUG
                        print("‼️ Decoding error: \(decodingError)")
                    #endif

                    handler(.failure(decodingError))
                    return
                }
            case let .failure(error):
                handler(.failure(error))
            }
        }
    }
}

// MARK: - Weak Target

public final class WeakTargetNetworkRequestSenderProxy<Target: AnyObject> {
    init(sender: NetworkRequestSender, target: Target?) {
        self.sender = sender
        self.target = target
    }

    let sender: NetworkRequestSender

    weak var target: Target?
}

public extension WeakTargetNetworkRequestSenderProxy {
    func decodeResponse<ResponseModel: DecodableNetworkResponseModel>(to modelType: ResponseModel.Type) -> DecodableWeakTargetNetworkRequestSenderProxy<Target, ResponseModel> {
        DecodableWeakTargetNetworkRequestSenderProxy<Target, ResponseModel>(proxy: self)
    }

    func onProgress(handler: ((Target, Double) -> Void)?) -> Self {
        _ = sender.onProgress { [weak target] percentage in
            guard let target else { return }
            handler?(target, percentage)
        }
        return self
    }

    func onCompleted(handler: @escaping (Target, Result<Data, any Error>) -> Void) -> NetworkRequestSender {
        sender.onCompleted(handler: { [weak target] result in
            guard let target else { return }
            handler(target, result)
        })
    }
}

public extension NetworkRequestSender {
    func weakTarget<Target: AnyObject>(_ target: Target) -> WeakTargetNetworkRequestSenderProxy<Target> {
        WeakTargetNetworkRequestSenderProxy(sender: self, target: target)
    }
}

// MARK: - Weak Target & decode response

public final class DecodableWeakTargetNetworkRequestSenderProxy<Target: AnyObject, ResponseModel: DecodableNetworkResponseModel> {
    let proxy: WeakTargetNetworkRequestSenderProxy<Target>

    init(proxy: WeakTargetNetworkRequestSenderProxy<Target>) {
        self.proxy = proxy
    }

    var target: Target? { proxy.target }

    var sender: NetworkRequestSender {
        proxy.sender
    }
}

public extension DecodableWeakTargetNetworkRequestSenderProxy {
    func onCompleted(handler: @escaping (Target, Result<ResponseModel, any Error>) -> Void) -> NetworkRequestSender {
        func performHandler(_ handler: @escaping (Target, Result<ResponseModel, any Error>) -> Void, with result: Result<ResponseModel, any Error>) {
            guard let target else { return }
            handler(target, result)
        }

        return sender.onCompleted { result in
            switch result {
            case let .success(data):
                do {
                    let model = try ResponseModel.decodeFromData(data)
                    performHandler(handler, with: .success(model))
                } catch let decodingError {
                    #if DEBUG
                        print("‼️ Decoding error: \(decodingError)")
                    #endif
                    performHandler(handler, with: .failure(decodingError))
                    return
                }
            case let .failure(error):
                performHandler(handler, with: .failure(error))
            }
        }
    }
}

// MARK: - Init sender

public extension NetworkService {
    func prepare(urlRequest: URLRequest) -> NetworkRequestSender {
        NetworkRequestSender(networkService: self, urlRequest: urlRequest)
    }

    func prepare(requestWith model: any NetworkRequestBaseModel) -> NetworkRequestSender {
        let urlRequest = model.buildURLRequest()
        return prepare(urlRequest: urlRequest)
    }
}
