//
//  CacheableNetworkService.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 26/6/24.
//

import Foundation

public protocol CacheStorage {
    func read() throws -> Data
    func write(_ data: Data?) throws
}

public protocol CacheStorageProvider {
    func cacheStorage(forRequest urlRequest: URLRequest) -> (any CacheStorage)?
}

final class CacheableNetworkService: NetworkService {
    let cacheStorageProvider: CacheStorageProvider
    let underlyingService: NetworkService

    init(cacheStorageProvider: CacheStorageProvider, underlyingService: NetworkService) {
        self.cacheStorageProvider = cacheStorageProvider
        self.underlyingService = underlyingService
    }

    func sendDataRequest(_ urlRequest: URLRequest, task: NetworkTask, progressHandler: ((Double) -> Void)?, completion: @escaping (Result<Data, any Error>) -> Void) -> any NetworkURLSessionTask {
        var finalCompletion = completion

        if let cacheStorage = cacheStorageProvider.cacheStorage(forRequest: urlRequest) {
            finalCompletion = { [weak self] result in
                switch result {
                case let .success(data):
                    self?.cacheQueue.async {
                        do {
                            try cacheStorage.write(data)
                            #if DEBUG
                            print("✅ [NoMoreNetworkService] [\(Self.self)] Saved cache for request '\(urlRequest)' successfully!")
                            #endif
                        } catch {
                            #if DEBUG
                            print("⚠️ [NoMoreNetworkService] [\(Self.self)] Error while writing cache for request '\(urlRequest)' 👉 '\(error)' 👉 Skip writing cache, the response data won't be saved!")
                            #endif
                        }
                    }
                default:
                    break
                }
                completion(result)
            }

            cacheQueue.async {
                do {
                    let data = try cacheStorage.read()
                    if !data.isEmpty {
                        completion(.success(data))
                        #if DEBUG
                        print("✅ [NoMoreNetworkService] [\(Self.self)] Read cache for request '\(urlRequest)' successfully!")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("⚠️ [NoMoreNetworkService] [\(Self.self)] Error while reading cache for request '\(urlRequest)' 👉 '\(error)' 👉 Skip reading cache, fetch data from remote!")
                    #endif
                }
            }
        }

        return underlyingService.sendDataRequest(urlRequest, task: task, progressHandler: progressHandler, completion: finalCompletion)
    }

    private let cacheQueue = DispatchQueue(label: "no-more-network-service.cache", attributes: .concurrent)
}

public final class DefaultCacheStorageProvider: CacheStorageProvider {
    public enum StorageType {
        case fileManager
        case userDefaults
    }

    private let cacheSpace = "no-more-network-service-caches"
    private var condition: (URLRequest) -> Bool
    private let storageType: StorageType

    public init(using storageType: StorageType,
                where condition: @escaping (URLRequest) -> Bool = { _ in true }) {
        self.storageType = storageType
        self.condition = condition
    }

    public static let `default`: DefaultCacheStorageProvider = .init(using: .fileManager)
    public static let userDefaults: DefaultCacheStorageProvider = .init(using: .userDefaults)

    public func with(condition: @escaping (URLRequest) -> Bool) -> Self {
        self.condition = condition
        return self
    }

    public func cacheStorage(forRequest urlRequest: URLRequest) -> (any CacheStorage)? {
        guard let urlString = urlRequest.url?.absoluteString else { return nil }

        guard condition(urlRequest) else {
            print("⚠️ [NoMoreNetworkService] [\(Self.self)] Cache for request '\(urlRequest)' is off!")
            return nil
        }

        let hashKey = urlString.sha1()

        switch storageType {
        case .fileManager:
            let rootDirectory = FileManager.default.applicationSupportDirectory
            let storageURL = rootDirectory
                .appendingPathComponent(cacheSpace, isDirectory: true)
                .appendingPathComponent(hashKey, isDirectory: false)
            let fileStorage = FileStorage(url: storageURL)
            return fileStorage
        case .userDefaults:
            let userDefaults = UserDefaults(suiteName: cacheSpace) ?? .standard
            return UserDefaultsStorage(defaults: userDefaults, key: hashKey)
        }
    }
}

public extension NetworkService {
    func withCacheStorage(provider: CacheStorageProvider) -> NetworkService {
        CacheableNetworkService(cacheStorageProvider: provider, underlyingService: self)
    }

    func withDefaultCacheStorage(_ provider: DefaultCacheStorageProvider = .default) -> NetworkService {
        CacheableNetworkService(cacheStorageProvider: provider, underlyingService: self)
    }
}

extension FileManager {
    var applicationSupportDirectory: URL {
        urls(for: .cachesDirectory, in: .userDomainMask).first!
    }
}

// MARK: - CacheStorage

enum StorageError: Error {
    case readError
    case writeError
}

// MARK: - FileStorage

final class FileStorage: CacheStorage {
    private let url: URL
    private let fileManager: FileManager

    /// Designated initializer.
    /// - Parameters:
    ///   - url: A file system URL for the underlying file resource.
    ///   - fileManager: A file manager. Defaults to `default` manager.
    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    /// Reads and returns the data from this object's associated file resource.
    ///
    /// - Returns: The data stored on disk.
    /// - Throws: An error if reading the contents of the file resource fails (i.e. file doesn't
    /// exist).
    func read() throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw StorageError.readError
        }
    }

    /// Writes the given data to this object's associated file resource.
    ///
    /// When the given `data` is `nil`, this object's associated file resource is emptied.
    ///
    /// - Parameter data: The `Data?` to write to this object's associated file resource.
    func write(_ data: Data?) throws {
        do {
            try createDirectories(in: url.deletingLastPathComponent())
            if let data {
                try data.write(to: url, options: .atomic)
            } else {
                let emptyData = Data()
                try emptyData.write(to: url, options: .atomic)
            }
        } catch {
            throw StorageError.writeError
        }
    }

    /// Creates all directories in the given file system URL.
    ///
    /// If the directory for the given URL already exists, the error is ignored because the directory
    /// has already been created.
    ///
    /// - Parameter url: The URL to create directories in.
    private func createDirectories(in url: URL) throws {
        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch CocoaError.fileWriteFileExists {
            // Directory already exists.
        } catch { throw error }
    }
}

// MARK: - UserDefaultsStorage

final class UserDefaultsStorage: CacheStorage {
    private let defaults: UserDefaults
    private let key: String

    /// Designated initializer.
    /// - Parameters:
    ///   - defaults: The defaults container.
    ///   - key: The key mapping to the value stored in the defaults container.
    init(defaults: UserDefaults, key: String) {
        self.defaults = defaults
        self.key = key
    }

    /// Reads and returns the data from this object's associated defaults resource.
    ///
    /// - Returns: The data stored on disk.
    /// - Throws: An error if no data has been stored to the defaults container.
    func read() throws -> Data {
        if let data = defaults.data(forKey: key) {
            return data
        } else {
            throw StorageError.readError
        }
    }

    /// Writes the given data to this object's associated defaults.
    ///
    /// When the given `data` is `nil`, the associated default is removed.
    ///
    /// - Parameter data: The `Data?` to write to this object's associated defaults.
    func write(_ data: Data?) throws {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
