//
//  NetworkService.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 18/04/2022.
//

import Foundation

public enum NetworkTask {
    case data
    case uploadData(_ data: Data)
    case uploadFile(_ fileURL: URL)
}

public protocol NetworkService {
    func sendDataRequest(_ urlRequest: URLRequest, task: NetworkTask, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask
}

public extension NetworkService {
    func sendDataRequest(_ urlRequest: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask {
        sendDataRequest(urlRequest, task: .data, completion: completion)
    }
}

public extension NetworkService {
    @discardableResult
    func sendDataRequest<ResponseModel: Decodable>(
        _ urlRequest: URLRequest,
        task: NetworkTask,
        decoder: JSONDecoder = {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }(),
        completion: @escaping (Result<ResponseModel, Error>) -> Void) -> NetworkURLSessionTask {
        sendDataRequest(urlRequest, task: task) { (result: Result<Data, Error>) in
            switch result {
            case let .success(data):
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

    @discardableResult
    func sendDataRequest<RequestModel: NetworkRequestBaseModel, ResponseModel: DecodableNetworkResponseModel>(
        requestModel: RequestModel,
        responseModel: ResponseModel.Type = ResponseModel.self,
        completion: @escaping (Result<ResponseModel, Error>) -> Void) -> NetworkURLSessionTask {
        let urlRequest = requestModel.buildURLRequest()
        return sendDataRequest(urlRequest, task: requestModel.task) { (result: Result<Data, Error>) in
            switch result {
            case let .success(data):
                do {
                    let model = try ResponseModel.decodeFromData(data)
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

private let httpError = "HTTP Error"

public extension NSError {
    static func network(url: URL?, code: Int, message: String, data: Data? = nil, additionalInfo: [String: Any]? = nil) -> NSError {
        var userInfo: [String: Any] = additionalInfo ?? [:]
        userInfo[NSLocalizedFailureErrorKey] = message
        userInfo[NSURLErrorKey] = url
        userInfo[NSLocalizedFailureReasonErrorKey] = httpError
        userInfo["data"] = data

        return NSError(domain: "no-more-network.error", code: code, userInfo: userInfo)
    }

    var isHTTPError: Bool {
        userInfo[NSLocalizedFailureReasonErrorKey] as? String == httpError
    }

    var data: Data? {
        userInfo["data"] as? Data
    }
}

public protocol NetworkRequestBaseModel {
    var endpointURL: URL { get }
    var urlParameters: [String: String]? { get }

    var headerFields: [String: String] { get }

    var method: String { get }
    var body: Data? { get }

    var task: NetworkTask { get }

    func customURLRequest(_ initialRequest: URLRequest) -> URLRequest
}

public extension NetworkRequestBaseModel {
    var body: Data? { nil }

    var task: NetworkTask { .data }

    var urlParameters: [String: String]? { nil }

    func customURLRequest(_ initialRequest: URLRequest) -> URLRequest {
        return initialRequest
    }

    func buildURLRequest() -> URLRequest {
        var request = URLRequest(url: endpointURL)

        for (key, value) in headerFields {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpMethod = method
        request.httpBody = body

        return customURLRequest(request)
    }
}

public protocol NetworkRequestModel: NetworkRequestBaseModel {
    var scheme: String { get }
    var host: String { get }
    var path: String { get }

    var authorization: Authorization { get }
    var additionalHeaders: [String: String] { get }
}

public extension NetworkRequestModel {
    var scheme: String { "https" }

    var endpointURL: URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path

        if let urlParameters {
            var items: [URLQueryItem] = []
            for (key, value) in urlParameters {
                let newItem = URLQueryItem(name: key, value: value)
                items.append(newItem)
            }
            components.queryItems = items
        }
        guard let url = components.url else {
            fatalError()
        }
        return url
    }

    var headerFields: [String: String] {
        var header: [String: String] = [:]
        if let token = authorization.authorizationToken {
            header = ["Authorization": token]
        }
        return additionalHeaders.merging(header) { $1 }
    }

    var authorization: Authorization { .none }

    var additionalHeaders: [String: String] { [:] }
}

public protocol RequestModelEncoder {
    func encode<Model>(_ value: Model) throws -> Data where Model: Encodable
}

extension JSONEncoder: RequestModelEncoder {}

public protocol EncodableNetworkRequestModel: NetworkRequestModel, Encodable {
    var encoder: RequestModelEncoder { get }
}

public extension EncodableNetworkRequestModel {
    var encoder: RequestModelEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    var body: Data? {
        try? encoder.encode(self)
    }
}

public enum Authorization {
    case bearer(_ token: String)
    case basic(_ token: String)
    case raw(_ token: String)
    case none

    public var authorizationToken: String? {
        switch self {
        case let .bearer(token):
            return "Bearer \(token)"
        case let .basic(token):
            return "Basic \(token)"
        case let .raw(token):
            return token
        case .none:
            return nil
        }
    }
}

public protocol ResponseModelDecoder {
    func decode<Model: Decodable>(_ type: Model.Type, from data: Data) throws -> Model
}

extension JSONDecoder: ResponseModelDecoder {}

public protocol DecodableNetworkResponseModel: Decodable {
    static var decoder: ResponseModelDecoder { get }

    static func decodeFromData(_ data: Data) throws -> Self
}

public extension DecodableNetworkResponseModel {
    static var decoder: ResponseModelDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func decodeFromData(_ data: Data) throws -> Self {
        try decoder.decode(Self.self, from: data)
    }
}
