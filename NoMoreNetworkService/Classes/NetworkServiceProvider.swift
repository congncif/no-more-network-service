//
//  NetworkServiceProvider.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/05/2022.
//

import Foundation
import Security

final class NetworkServiceProvider: NetworkService {
    init(session: NetworkURLSession, requestAdapter: NetworkRequestAdapter, responseAdapter: NetworkResponseAdapter, retrier: NetworkRequestRetrier, sessionDelegate: SessionDelegate) {
        self.session = session
        self.requestAdapter = requestAdapter
        self.responseAdapter = responseAdapter
        self.retrier = retrier
        self.sessionDelegate = sessionDelegate
    }

    let session: NetworkURLSession
    let sessionDelegate: SessionDelegate
    let requestAdapter: NetworkRequestAdapter
    let responseAdapter: NetworkResponseAdapter
    let retrier: NetworkRequestRetrier

    func sendDataRequest(_ urlRequest: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        requestAdapter.adapt(urlRequest) { [weak self] result in
            switch result {
            case let .success(request):
                self?.performRequest(request, completion: { [weak self] responseResult in
                    self?.responseAdapter.adapt(responseResult, completion: { [weak self] newResult in
                        switch newResult {
                        case .success:
                            completion(newResult)
                        case let .failure(error):
                            self?.retrier.retry(dueTo: error, completion: { [weak self] shouldRetry in
                                switch shouldRetry {
                                case .retryNow:
                                    self?.sendDataRequest(urlRequest, completion: completion)
                                case .doNotRetry:
                                    completion(newResult)
                                }
                            })
                        }
                    })
                })
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func performRequest(_ urlRequest: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        session.performDataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
            } else {
                guard let httpResponse = response as? HTTPURLResponse else {
                    let unknownError = NSError.network(url: urlRequest.url, code: NSURLErrorUnknown, message: "Invalid HTTPURLResponse", additionalInfo: [:])
                    completion(.failure(unknownError))
                    return
                }
                let statusCode = httpResponse.statusCode
                switch statusCode {
                case 200 ..< 300 where data != nil:
                    completion(.success(data!))
                default:
                    let statusError = NSError.network(
                        url: urlRequest.url,
                        code: statusCode,
                        message: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                        additionalInfo: urlRequest.allHTTPHeaderFields
                    )
                    completion(.failure(statusError))
                }
            }
        }
    }
}

final class SessionDelegate: NSObject, URLSessionDelegate {
    let serverTrustConfiguration: ServerTrustConfiguration?

    init(serverTrustConfiguration: ServerTrustConfiguration?) {
        self.serverTrustConfiguration = serverTrustConfiguration
        super.init()
    }

    func urlSession(_: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let host = challenge.protectionSpace.host

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let evaluators = serverTrustConfiguration?.evaluations[host], !evaluators.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard challenge.previousFailureCount == 0 else {
            completionHandler(.rejectProtectionSpace, nil)
            return
        }

        // Set policy to validate domain
        let policy = SecPolicyCreateSSL(true, host as CFString)
        let policies = NSArray(object: policy)
        SecTrustSetPolicies(serverTrust, policies)

        for evaluator in evaluators {
            if evaluator.evaluate(secTrust: serverTrust) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return // exit as soon as we found a match
            }
        }

        // No valid cert available
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}
