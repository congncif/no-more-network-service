//
//  NetworkURLSession.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/05/2022.
//

import Foundation

public protocol NetworkURLSession {
    @discardableResult
    func performDataTask(_ task: NetworkTask, request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> NetworkURLSessionTask
}

extension URLSession: NetworkURLSession {
    public func performDataTask(_ task: NetworkTask, request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> NetworkURLSessionTask {
        switch task {
        case .data:
            let requestTask = dataTask(with: request, completionHandler: completionHandler)
            
            requestTask.resume()
            return requestTask
        case let .uploadData(data):
            let requestTask = uploadTask(with: request, from: data, completionHandler: completionHandler)
            requestTask.resume()
            return requestTask
        case let .uploadFile(url):
            let requestTask = uploadTask(with: request, fromFile: url, completionHandler: completionHandler)
            requestTask.resume()
            return requestTask
        }
    }
}

public protocol NetworkURLSessionTask {
    var taskIdentifier: Int { get }

    func cancel()
}

extension URLSessionDataTask: NetworkURLSessionTask {}
