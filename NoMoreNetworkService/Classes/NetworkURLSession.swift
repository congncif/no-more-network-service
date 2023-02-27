//
//  NetworkURLSession.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/05/2022.
//

import Foundation

public protocol NetworkURLSession {
    func performDataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void)
}

extension URLSession: NetworkURLSession {
    public func performDataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) {
        dataTask(with: request, completionHandler: completionHandler).resume()
    }
}
