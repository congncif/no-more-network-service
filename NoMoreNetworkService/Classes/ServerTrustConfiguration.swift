//
//  ServerTrustConfiguration.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 21/07/2022.
//

import Foundation
import Security

struct CertificateEvaluator: ServerTrustEvaluating {
    let certificate: SecCertificate

    func evaluate(secTrust: SecTrust) -> Bool {
        let certArray = [certificate] as CFArray
        SecTrustSetAnchorCertificates(secTrust, certArray)

        var result = SecTrustResultType.invalid
        SecTrustEvaluate(secTrust, &result)
        let isValid = (result == .unspecified || result == .proceed)

        guard let serverCertificate = secTrust.certificates.first else {
            return false
        }

        let serverCertificateData = SecCertificateCopyData(serverCertificate) as Data
        let localCertificateData = SecCertificateCopyData(certificate) as Data

        return isValid && serverCertificateData == localCertificateData
    }
}

struct SecKeyEvaluator: ServerTrustEvaluating {
    let secKey: SecKey

    func evaluate(secTrust: SecTrust) -> Bool {
        var result: SecTrustResultType = .invalid
        SecTrustEvaluate(secTrust, &result)

        let isServerTrusted = result == .proceed || result == .unspecified

        guard isServerTrusted else {
            return false
        }

        for serverPublicKey in secTrust.certificates.compactMap({ $0.publicKey }) {
            if serverPublicKey == secKey {
                return true
            }
        }
        return false
    }
}

protocol ServerTrustEvaluating {
    func evaluate(secTrust: SecTrust) -> Bool
}

public struct TrustFile {
    public init(name: String, type: String = "cer", bundle: Bundle = .main) {
        self.name = name
        self.type = type
        self.bundle = bundle
    }

    let name: String
    let type: String
    let bundle: Bundle

    public static func cer(name: String, bundle: Bundle = .main) -> TrustFile {
        TrustFile(name: name, type: "cer", bundle: bundle)
    }
}

public struct TrustBundle {
    public init(types: [String], bundle: Bundle = .main) {
        self.bundle = bundle
        self.types = types
    }

    let bundle: Bundle
    let types: [String]

    public static func commonCertificatesBundle(_ bundle: Bundle = .main) -> TrustBundle {
        TrustBundle(types: [".cer", ".CER", ".crt", ".CRT", ".der", ".DER"], bundle: bundle)
    }

    public static func commonPublicKeysBundle(_ bundle: Bundle = .main) -> TrustBundle {
        TrustBundle(types: ["pem", "PEM"], bundle: bundle)
    }
}

public final class ServerTrustConfiguration {
    var evaluations: [String: [ServerTrustEvaluating]] = [:]

    public static let `default` = ServerTrustConfiguration()

    public func withCertificates(of file: TrustFile, forHost host: String) -> Self {
        let evaluators = CertificatesLookUp.certificates(with: [file.name], ofType: file.type, from: file.bundle)
            .map { CertificateEvaluator(certificate: $0) }
        return appending(evaluators: evaluators, forHost: host)
    }

    public func withCertificates(in trustBundle: TrustBundle, forHost host: String) -> Self {
        let evaluators = CertificatesLookUp.certificates(ofTypes: trustBundle.types, from: trustBundle.bundle)
            .map { CertificateEvaluator(certificate: $0) }
        return appending(evaluators: evaluators, forHost: host)
    }

    public func withCertificates(from urls: [URL], forHost host: String) -> Self {
        let evaluators = CertificatesLookUp.certificates(from: urls)
            .map { CertificateEvaluator(certificate: $0) }
        return appending(evaluators: evaluators, forHost: host)
    }

    public func withPublicKeys(in trustBundle: TrustBundle, forHost host: String) -> Self {
        let evaluators = CertificatesLookUp.secKeys(ofTypes: trustBundle.types, from: trustBundle.bundle)
            .map { SecKeyEvaluator(secKey: $0) }
        return appending(evaluators: evaluators, forHost: host)
    }

    public func withPublicKeys(from urls: [URL], forHost host: String) -> Self {
        let evaluators = CertificatesLookUp.secKeys(from: urls)
            .map { SecKeyEvaluator(secKey: $0) }
        return appending(evaluators: evaluators, forHost: host)
    }

    public func withPublicKey(_ publicKey: String, forHost host: String) -> Self {
        guard let secKey = publicKey.secKey else { return self }
        return appending(evaluators: [SecKeyEvaluator(secKey: secKey)], forHost: host)
    }

    func appending(evaluators: [ServerTrustEvaluating], forHost host: String) -> Self {
        if var certs = evaluations[host] {
            certs.append(contentsOf: evaluators)
            evaluations[host] = certs
        } else {
            evaluations[host] = evaluators
        }
        return self
    }
}

extension SecTrust {
    var certificates: [SecCertificate] {
        if #available(iOS 15, macOS 12, tvOS 15, watchOS 8, *) {
            return (SecTrustCopyCertificateChain(self) as? [SecCertificate]) ?? []
        } else {
            return (0 ..< SecTrustGetCertificateCount(self)).compactMap { index in
                SecTrustGetCertificateAtIndex(self, index)
            }
        }
    }
}

extension SecCertificate {
    var publicKey: SecKey? {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        let trustCreationStatus = SecTrustCreateWithCertificates(self, policy, &trust)

        guard let createdTrust = trust, trustCreationStatus == errSecSuccess else { return nil }

        if #available(iOS 14, macOS 11, tvOS 14, watchOS 7, *) {
            return SecTrustCopyKey(createdTrust)
        } else {
            return SecTrustCopyPublicKey(createdTrust)
        }
    }
}

extension String {
    var secKey: SecKey? {
        let rawKey = replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
            .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
        guard let data = Data(base64Encoded: rawKey) else { return nil }
        let attributes = [kSecAttrKeyType: kSecAttrKeyTypeRSA,
                          kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary
        guard let key = SecKeyCreateWithData(data as CFData, attributes, nil) else { return nil }
        return key
    }
}

enum CertificatesLookUp {
    static func certificates(with names: [String], ofType type: String, from bundle: Bundle) -> [SecCertificate] {
        names.lazy.map {
            guard let file = bundle.url(forResource: $0, withExtension: type),
                  let data = try? Data(contentsOf: file),
                  let cert = SecCertificateCreateWithData(nil, data as CFData) else {
                return nil
            }
            return cert
        }.compactMap { $0 }
    }

    static func certificates(ofTypes types: [String], from bundle: Bundle) -> [SecCertificate] {
        [String](Set(types.flatMap { bundle.paths(forResourcesOfType: $0, inDirectory: nil) })).compactMap { path in
            guard
                let certificateData = try? Data(contentsOf: URL(fileURLWithPath: path)) as CFData,
                let certificate = SecCertificateCreateWithData(nil, certificateData) else { return nil }

            return certificate
        }
    }

    static func certificates(from urls: [URL]) -> [SecCertificate] {
        urls.compactMap { try? Data(contentsOf: $0) }
            .compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
    }

    static func secKeys(ofTypes types: [String], from bundle: Bundle) -> [SecKey] {
        Set(types).compactMap { bundle.urls(forResourcesWithExtension: $0, subdirectory: nil) }
            .flatMap { $0 }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .compactMap { $0.secKey }
    }

    static func secKeys(from urls: [URL]) -> [SecKey] {
        urls.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .compactMap { $0.secKey }
    }
}
