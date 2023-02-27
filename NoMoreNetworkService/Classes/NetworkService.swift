//
//  NetworkService.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 18/04/2022.
//

import Foundation

public protocol NetworkService {
    func sendDataRequest(_ urlRequest: URLRequest, completion: @escaping (Result<Data, Error>) -> Void)
}

public extension NetworkService {
    func sendDataRequest<ResponseModel: Decodable>(_ urlRequest: URLRequest, completion: @escaping (Result<ResponseModel, Error>) -> Void) {
        sendDataRequest(urlRequest) { (result: Result<Data, Error>) in
            switch result {
            case let .success(data):
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                do {
                    let model = try decoder.decode(ResponseModel.self, from: data)
                    completion(.success(model))
                } catch let decodingError {
                    #if DEBUG
                        print("‼️ Decoding error: \(decodingError)")
                    #endif
                    completion(.failure(decodingError))
                    return
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }
}

public extension NSError {
    static func network(url: URL?, code: Int, message: String, additionalInfo: [String: Any]? = nil) -> NSError {
        var userInfo: [String: Any] = additionalInfo ?? [:]
        userInfo[NSLocalizedFailureErrorKey] = message
        userInfo[NSURLErrorKey] = url

        return NSError(domain: "platform.service.network", code: code, userInfo: userInfo)
    }
}
