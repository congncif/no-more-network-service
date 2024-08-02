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
    case download(destinationURL: (_ suggestedFilename: String?) -> URL?)

    public static func download(destinationURL: URL? = nil) -> NetworkTask {
        return .download(destinationURL: { _ in destinationURL })
    }
}

public protocol NetworkService {
    @discardableResult
    func sendDataRequest(_ urlRequest: URLRequest, task: NetworkTask, progressHandler: ((Double) -> Void)?, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask
}

public extension NetworkService {
    @discardableResult
    func sendDataRequest(_ urlRequest: URLRequest, task: NetworkTask, completion: @escaping (Result<Data, Error>) -> Void) -> NetworkURLSessionTask {
        sendDataRequest(urlRequest, task: task, progressHandler: nil, completion: completion)
    }

    @discardableResult
    func sendDataRequest<ResponseModel: Decodable>(
        _ urlRequest: URLRequest,
        task: NetworkTask = .data,
        decoder: JSONDecoder = {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }(),
        progressHandler: ((Double) -> Void)? = nil,
        completion: @escaping (Result<ResponseModel, Error>) -> Void) -> NetworkURLSessionTask {
        sendDataRequest(urlRequest, task: task, progressHandler: progressHandler) { (result: Result<Data, Error>) in
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
        progressHandler: ((Double) -> Void)? = nil,
        completion: @escaping (Result<ResponseModel, Error>) -> Void) -> NetworkURLSessionTask {
        let urlRequest = requestModel.buildURLRequest()
        return sendDataRequest(urlRequest, task: requestModel.task, progressHandler: progressHandler) { (result: Result<Data, Error>) in
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

    var additionalHeaders: [String: String] {
        ["Content-Type": "application/json"]
    }
}

public protocol URLEncodedFormNetworkRequestModel: EncodableNetworkRequestModel {}

public extension URLEncodedFormNetworkRequestModel {
    var body: Data? {
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                var urlComponents = URLComponents()
                let parameters = convertToStringDictionary(json)
                urlComponents.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }

                if let query = urlComponents.percentEncodedQuery {
                    return query.data(using: .utf8)
                } else {
                    return nil
                }
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    var additionalHeaders: [String: String] {
        ["Content-Type": "application/x-www-form-urlencoded"]
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
            return token.appendingPrefixIfNeeded("Bearer")
        case let .basic(token):
            return token.appendingPrefixIfNeeded("Basic")
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
