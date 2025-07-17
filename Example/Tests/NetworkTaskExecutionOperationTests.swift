//
//  NetworkTaskExecutionOperationTests.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/7/25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

@testable import NoMoreNetworkService
import XCTest

final class NetworkTaskExecutionOperationTests: XCTestCase {
    func testCompletionOnlyCalledOnce_whenMultipleRetries() {
        let adapter = ImmediateAdapter()
        let responseAdapter = AlwaysFailAdapter()
        let retrier = CountingRetrier(maxRetries: 3)
        let session = FakeSession()

        let expectation = expectation(description: "Completion called once")
        var completionCount = 0
        let completion: (Result<Data, Error>) -> Void = { _ in
            completionCount += 1
            expectation.fulfill()
        }

        let op = NetworkTaskExecutionOperation(
            session: session,
            requestAdapter: adapter,
            responseAdapter: responseAdapter,
            retrier: retrier,
            maxRetries: 3,
            urlRequest: URLRequest(url: URL(string: "https://example.com")!),
            task: .data,
            progressHandler: nil,
            completion: completion
        )

        let queue = OperationQueue()
        queue.addOperation(op)

        waitForExpectations(timeout: 3)
        XCTAssertEqual(completionCount, 1)
        XCTAssertEqual(retrier.callCount, 3)
    }

    func testCancelBeforeStart_shouldNotRunRequest() {
        let adapter = ImmediateAdapter()
        let responseAdapter = AlwaysFailAdapter()
        let retrier = CountingRetrier(maxRetries: 1)
        let session = FakeSession()

        let expectation = expectation(description: "Should not call completion when cancelled early")
        expectation.isInverted = true

        let op = NetworkTaskExecutionOperation(
            session: session,
            requestAdapter: adapter,
            responseAdapter: responseAdapter,
            retrier: retrier,
            maxRetries: 1,
            urlRequest: URLRequest(url: URL(string: "https://example.com")!),
            task: .data,
            progressHandler: nil
        ) { _ in
            expectation.fulfill()
        }

        let queue = OperationQueue()
        queue.addOperation(op)

        // Cancel right after enqueue
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.001) {
            op.cancel()
        }

        wait(for: [expectation], timeout: 1)
        XCTAssertTrue(op.isFinished)
    }

    func testCancelImmediately_shouldNotStartExecution() {
        let adapter = TrackingAdapter()
        let responseAdapter = AlwaysFailAdapter()
        let retrier = CountingRetrier(maxRetries: 1)
        let session = TrackingSession()

        let completionCalled = XCTestExpectation(description: "Completion should not be called")
        completionCalled.isInverted = true

        let op = NetworkTaskExecutionOperation(
            session: session,
            requestAdapter: adapter,
            responseAdapter: responseAdapter,
            retrier: retrier,
            maxRetries: 1,
            urlRequest: URLRequest(url: URL(string: "https://example.com")!),
            task: .data,
            progressHandler: nil
        ) { _ in
            completionCalled.fulfill()
        }

        let queue = OperationQueue()
        queue.isSuspended = true // 👈 ngăn không cho start() chạy ngay
        queue.addOperation(op)
        op.cancel()
        queue.isSuspended = false // 👈 lúc này mới cho nó chạy

        wait(for: [completionCalled], timeout: 1)

        XCTAssertTrue(op.isFinished)
        XCTAssertFalse(adapter.wasCalled, "Adapter should not be called after cancel")
        XCTAssertFalse(session.wasCalled, "Session should not be called after cancel")
    }
}

final class ImmediateAdapter: NetworkRequestAdapter {
    func adapt(_ request: URLRequest, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        completion(.success(request))
    }
}

final class AlwaysFailAdapter: NetworkResponseAdapter {
    func adapt(_ response: Result<Data, Error>, completion: @escaping (Result<Data, Error>) -> Void) {
        completion(.failure(NSError(domain: "Test", code: -1)))
    }
}

final class CountingRetrier: NetworkRequestRetrier {
    private(set) var callCount = 0
    private let maxRetries: Int

    init(maxRetries: Int) {
        self.maxRetries = maxRetries
    }

    func retry(dueTo error: Error, completion: @escaping (RetryPlan) -> Void) {
        callCount += 1
        if callCount <= maxRetries {
            completion(.retryNow)
        } else {
            completion(.doNotRetry)
        }
    }
}

final class FakeTask: NetworkURLSessionTask {
    var taskIdentifier: Int = UUID().hashValue

    func cancel() {}
}

final class FakeSession: NetworkURLSession {
    func performDataTask(_ task: NetworkTask, request: URLRequest, progressHandler: ((Double) -> Void)?, completionHandler completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> NetworkURLSessionTask {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            completion(nil, nil, NSError(domain: "Network", code: 500))
        }
        return FakeTask()
    }
}

final class TrackingAdapter: NetworkRequestAdapter {
    private(set) var wasCalled = false
    func adapt(_ request: URLRequest, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        wasCalled = true
        completion(.success(request))
    }
}

final class TrackingSession: NetworkURLSession {
    private(set) var wasCalled = false
    func performDataTask(_ task: NetworkTask, request: URLRequest, progressHandler: ((Double) -> Void)?, completionHandler completion: @escaping (Data?, URLResponse?, Error?) -> Void) -> NetworkURLSessionTask {
        wasCalled = true
        return FakeTask()
    }
}
