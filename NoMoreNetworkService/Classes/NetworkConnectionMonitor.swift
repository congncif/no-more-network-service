//
//  NetworkConnectionMonitor.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 28/8/24.
//

import CoreTelephony
import Foundation
import Network

/// Enum representing the type of detection used for network quality assessment.
public enum DetectionType {
    case networkTypeBased // Use network type to determine connection quality
    case pingServerBased(serverURL: URL, responseTimeThreshold: ResponseTimeThresholds) // Use ping server response with threshold
    
    public static func pingServerBased(serverURL: URL) -> DetectionType {
        .pingServerBased(serverURL: serverURL, responseTimeThreshold: .default)
    }
}

public struct ResponseTimeThresholds {
    public var moderateTimeInterval: TimeInterval
    public var poorTimeInterval: TimeInterval
    
    public init(moderateTimeInterval: TimeInterval, poorTimeInterval: TimeInterval) {
        self.moderateTimeInterval = moderateTimeInterval
        self.poorTimeInterval = poorTimeInterval
    }
    
    public static let `default` = ResponseTimeThresholds(moderateTimeInterval: 0.3, poorTimeInterval: 1)
}

/// Enum representing the quality of the network connection with detailed classification.
public enum ConnectionQuality {
    case good
    case moderate
    case poor(PoorReason)
    case unpredictable(String)
    case noConnection
    
    /// Enum representing the reasons for poor connection quality.
    public enum PoorReason {
        case highLatency(elapsedTime: TimeInterval, threshold: TimeInterval)
        case slowConnectionType(description: String) // For slow cellular connections
        case serverUnresponsive
        case unexpectedResponse(statusCode: Int)
        case error(String)
        
        /// Provides a human-readable description of the poor connection reason.
        public var description: String {
            switch self {
            case .highLatency(let elapsedTime, let threshold):
                return "High latency: \(elapsedTime) seconds (Threshold: \(threshold) seconds)"
            case .slowConnectionType(let description):
                return "Detected slow connection: \(description)"
            case .serverUnresponsive:
                return "Server is unresponsive."
            case .unexpectedResponse(let statusCode):
                return "Unexpected server response: HTTP \(statusCode)"
            case .error(let message):
                return "Ping test failed: \(message)"
            }
        }
    }
    
    /// A computed property to check if the connection is established.
    public var isConnected: Bool {
        switch self {
        case .good, .moderate, .poor, .unpredictable:
            return true
        case .noConnection:
            return false
        }
    }
}

/// Class responsible for monitoring network status and performing optional ping tests.
public class NetworkConnectionMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue.global(qos: .background)
    private let syncQueue = DispatchQueue(label: "NetworkConnectionMonitor.SyncQueue", attributes: .concurrent)
    private var _isMonitoring = false
    private let telephonyInfo = CTTelephonyNetworkInfo()
    
    /// Thread-safe property to track the monitoring state.
    private var isMonitoring: Bool {
        get {
            syncQueue.sync { _isMonitoring }
        }
        set {
            syncQueue.async(flags: .barrier) { self._isMonitoring = newValue }
        }
    }
    
    /// Initializes a new instance of NetworkConnectionMonitor.
    public init() {}
    
    /// Starts monitoring the network connection.
    /// - Parameters:
    ///   - detectionType: The type of detection to use for assessing network quality.
    ///   - completion: A closure that returns the connection quality.
    public func startMonitoring(
        detectionType: DetectionType,
        completion: @escaping (ConnectionQuality) -> Void
    ) {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied {
                log("Connected to the network")
                
                switch detectionType {
                case .networkTypeBased:
                    let quality = self?.classifyConnectionQualityBasedOnType(path) ?? .noConnection
                    log("Connection type classified as: \(quality)")
                    completion(quality)
                    
                case .pingServerBased(let serverURL, let responseTimeThresholds):
                    self?.performPingTest(
                        to: serverURL,
                        responseTimeThresholds: responseTimeThresholds,
                        completion: completion
                    )
                }
            } else {
                log("No network connection detected")
                completion(.noConnection)
            }
        }
        
        monitor.start(queue: queue)
    }
    
    /// Stops monitoring the network.
    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        monitor.cancel()
    }
    
    /// Perform a ping test to measure latency.
    /// - Parameters:
    ///   - url: The server URL to ping.
    ///   - responseTimeThreshold: The response time threshold to determine if the connection is poor.
    ///   - completion: A closure that returns the connection quality.
    private func performPingTest(
        to url: URL,
        responseTimeThresholds: ResponseTimeThresholds,
        completion: @escaping (ConnectionQuality) -> Void
    ) {
        let startTime = CFAbsoluteTimeGetCurrent()
            
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD" // Using HEAD to reduce data usage
        
        request.timeoutInterval = max(responseTimeThresholds.poorTimeInterval, 5)
        
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            let elapsedTime = endTime - startTime
            
            log("Ping test completed in \(elapsedTime) seconds")
            
            if let error = error {
                completion(.poor(.error(error.localizedDescription)))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200 ... 299:
                    let quality: ConnectionQuality
                    if elapsedTime > responseTimeThresholds.poorTimeInterval {
                        quality = .poor(.highLatency(elapsedTime: elapsedTime, threshold: responseTimeThresholds.poorTimeInterval))
                    } else if elapsedTime > responseTimeThresholds.moderateTimeInterval {
                        quality = .moderate
                    } else {
                        quality = .good
                    }
                    completion(quality)
                default:
                    completion(.poor(.unexpectedResponse(statusCode: httpResponse.statusCode)))
                }
            } else {
                completion(.poor(.serverUnresponsive))
            }
        }
        
        task.resume()
    }
    
    /// Classifies the connection quality based on the network type detected.
    /// - Parameter path: The NWPath object representing the current network path.
    /// - Returns: The classified connection quality.
    private func classifyConnectionQualityBasedOnType(_ path: NWPath) -> ConnectionQuality {
        if path.usesInterfaceType(.wiredEthernet) {
            log("Detected Wired Ethernet connection")
            return .good
        } else if path.usesInterfaceType(.wifi) {
            log("Detected WiFi connection")
            return .good
        } else if path.usesInterfaceType(.cellular) {
            if let radioType = getCurrentRadioAccessTechnology() {
                switch radioType {
                case CTRadioAccessTechnologyLTE:
                    log("Detected LTE (4G) connection")
                    return .moderate
                default:
                    if #available(iOS 14.1, *) {
                        if radioType == CTRadioAccessTechnologyNRNSA || radioType == CTRadioAccessTechnologyNR {
                            log("Detected 5G connection")
                            return .good
                        }
                    }
                    log("Detected slower cellular connection (\(radioType))")
                    return .poor(.slowConnectionType(description: radioType))
                }
            } else {
                log("Cellular connection type could not be determined")
                return .unpredictable("Cellular connection type could not be determined")
            }
        }
        
        log("Unknown or less reliable connection type detected")
        return .unpredictable("Unknown or less reliable connection type detected")
    }
    
    /// Gets the current radio access technology from the telephony network info.
    /// - Returns: The string representation of the radio access technology.
    private func getCurrentRadioAccessTechnology() -> String? {
        telephonyInfo.serviceCurrentRadioAccessTechnology?.values.first
    }
}

/// Utility function to log debug messages.
func log(_ message: String) {
    #if DEBUG
    print("[NetworkConnectionMonitor] \(message)")
    #endif
}
