//
//  NetworkLogMonitor.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 08/12/2023.
//

import Foundation

extension URLRequest {
    func cURL(pretty: Bool = false) -> String {
        let newLine = pretty ? "\\\n" : ""
        let method = (pretty ? "--request " : "-X ") + "\(self.httpMethod ?? "GET") \(newLine)"
        let url: String = (pretty ? "--url " : "") + "\'\(self.url?.absoluteString ?? "")\' \(newLine)"
        var cURL = "curl "
        var header = ""
        var data = ""
        if let httpHeaders = self.allHTTPHeaderFields, httpHeaders.keys.count > 0 {
            for (key, value) in httpHeaders {
                header += (pretty ? "--header " : "-H ") + "\'\(key): \(value)\' \(newLine)"
            }
        }
        if let bodyData = self.httpBody, let bodyString = String(data: bodyData, encoding: .utf8), !bodyString.isEmpty {
            data = "--data '\(bodyString)'"
        }
        cURL += method + url + header + data

        if cURL.hasSuffix(newLine) {
            cURL = String(cURL.dropLast(newLine.count))
        }
        return "\n🚦 [Request] \(self.url?.absoluteString ?? "")\n" + cURL
    }
}

func log(urlRequest: URLRequest, data: Data?, response: URLResponse?, error: Error?) -> String {
    var result = ""

    if let response = response as? HTTPURLResponse {
        let statusCode = response.statusCode
        let title = "\n🏁 [Response] [\(statusCode)] "
        let url = response.url?.absoluteString ?? ""

        result.append(title + url + "\n")

        let headerFields = response.allHeaderFields
        for (key, value) in headerFields {
            result.append("  -H \(key): \(value) \n")
        }
    } else {
        let title = "\n🏁 [Response] "
        let url = urlRequest.url?.absoluteString ?? ""
        result.append(title + url + "\n")
    }

    if let data {
        let payload = NSString(string: String(data: data, encoding: .utf8) ?? "")
        result.append("  --data: \n\(payload)\n")
    }

    if let error {
        let desc = error.localizedDescription
        result.append("  --error: \(desc)")
    }

    return result
}

#if DEBUG
public enum NetworkLogMonitor {
    public static var isEnabled: Bool = true
}
#endif
