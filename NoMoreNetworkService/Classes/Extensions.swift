//
//  String+Extensions.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 26/6/24.
//

import CommonCrypto
import Foundation

extension String {
    func sha1() -> String {
        let data = Data(self.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA1($0.baseAddress, CC_LONG(data.count), &digest)
        }
        let hexBytes = digest.map { String(format: "%02hhx", $0) }
        return hexBytes.joined()
    }

    func appendingPrefixIfNeeded(_ prefix: String, separator: String = " ") -> String {
        hasPrefix(prefix) ? self : prefix + separator + self
    }
}

func convertToStringDictionary(_ dictionary: [String: Any]) -> [String: String] {
    var stringDictionary: [String: String] = [:]

    for (key, value) in dictionary {
        if let stringValue = value as? String {
            stringDictionary[key] = stringValue
        } else if let numberValue = value as? NSNumber {
            stringDictionary[key] = numberValue.stringValue
        } else if let boolValue = value as? Bool {
            stringDictionary[key] = boolValue ? "true" : "false"
        } else if let dataValue = value as? Data, let stringFromData = String(data: dataValue, encoding: .utf8) {
            stringDictionary[key] = stringFromData
        } else {
            stringDictionary[key] = "\(value)"
        }
    }

    return stringDictionary
}
