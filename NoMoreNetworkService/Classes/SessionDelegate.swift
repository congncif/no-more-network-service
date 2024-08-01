//
//  SessionDelegate.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 1/8/24.
//

import Foundation
import Security

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
