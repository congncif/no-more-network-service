//
//  NetworkURLSession.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/05/2022.
//

import Foundation

public protocol NetworkURLSession {
    @discardableResult
    func performDataTask(_ task: NetworkTask, request: URLRequest, progressHandler: ((Double) -> Void)?, completionHandler: @escaping (Data?, URLResponse?, (any Error)?) -> Void) -> NetworkURLSessionTask
}

extension URLSession: NetworkURLSession {
    public func performDataTask(_ task: NetworkTask, request: URLRequest, progressHandler: ((Double) -> Void)?, completionHandler: @escaping (Data?, URLResponse?, (any Error)?) -> Void) -> NetworkURLSessionTask {
        switch task {
        case .data:
            let requestTask = dataTask(with: request, completionHandler: { data, response, error in
                progressHandler?(1)
                completionHandler(data, response, error)
            })
            progressHandler?(0)
            requestTask.resume()
            return requestTask
        case let .uploadData(data):
            let uploadTask = uploadTask(with: request, from: data, completionHandler: completionHandler)
            uploadTask.observeProgress(handler: progressHandler)
            uploadTask.resume()
            return uploadTask
        case let .uploadFile(url):
            let uploadTask = uploadTask(with: request, fromFile: url, completionHandler: completionHandler)
            uploadTask.observeProgress(handler: progressHandler)
            uploadTask.resume()
            return uploadTask
        case let .download(destinationURL):
            let downloadTask = downloadTask(with: request, completionHandler: { url, response, error in
                var finalURL: URL? = url
                var finalError: Error? = error

                if let destURL = destinationURL(response?.suggestedFilename), let url {
                    let fileManager = FileManager.default
                    do {
                        if fileManager.fileExists(atPath: destURL.path) {
                            // Remove the existing file
                            try fileManager.removeItem(at: destURL)
                        }
                        try fileManager.moveItem(at: url, to: destURL)
                        finalURL = destURL
                    } catch {
                        finalURL = url
                        finalError = error
                    }
                }

                if let finalError {
                    completionHandler(nil, response, finalError)
                } else {
                    if let finalURL {
                        do {
                            let data = try Data(contentsOf: finalURL)
                            completionHandler(data, response, finalError)
                        } catch {
                            completionHandler(nil, response, error)
                        }
                    } else {
                        completionHandler(nil, response, finalError)
                    }
                }
            })
            downloadTask.observeProgress(handler: progressHandler)
            downloadTask.resume()
            return downloadTask
        }
    }
}

public protocol NetworkURLSessionTask {
    var taskIdentifier: Int { get }

    func cancel()
}

extension URLSessionDataTask: NetworkURLSessionTask {}
extension URLSessionDownloadTask: NetworkURLSessionTask {}

private var observationKey: UInt8 = 1
extension URLSessionTask {
    func setObservation(_ observation: NSKeyValueObservation) {
        objc_setAssociatedObject(self, &observationKey, observation, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

extension URLSessionUploadTask {
    func observeProgress(handler: ((Double) -> Void)?) {
        let observation = self.observe(\.countOfBytesSent, options: [.new]) { [weak self] _, _ in
            guard let uploadTask = self else { return }
            let progress = Double(uploadTask.countOfBytesSent) / Double(uploadTask.countOfBytesExpectedToSend)
            handler?(progress)
        }
        self.setObservation(observation)
    }
}

extension URLSessionDownloadTask {
    func observeProgress(handler: ((Double) -> Void)?) {
        let observation = self.observe(\.countOfBytesReceived, options: [.new]) { [weak self] _, _ in
            guard let downloadTask = self else { return }
            let progress = Double(downloadTask.countOfBytesReceived) / Double(downloadTask.countOfBytesExpectedToReceive)
            handler?(progress)
        }
        self.setObservation(observation)
    }
}
