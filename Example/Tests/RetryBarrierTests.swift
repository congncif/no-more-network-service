//
//  Untitled.swift
//  NoMoreNetworkService
//
//  Created by NGUYEN CHI CONG on 17/7/25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

@testable import NoMoreNetworkService
import XCTest

final class RetryBarrierTests: XCTestCase {
    func testRetryBarrier_RaceCondition_ShouldCallUnderlyingRetrierOnceAndAllCompletionsCalled() {
        // Given
        let mockRetrier = MockRetrier()
        let barrier = RetryBarrier(retrier: mockRetrier)
        let numberOfConcurrentCalls = 100
        let expectation = XCTestExpectation(description: "All retry completions should be called")
        expectation.expectedFulfillmentCount = numberOfConcurrentCalls

        var results: [RetryPlan] = []
        let resultsLock = NSLock()

        // When
        DispatchQueue.concurrentPerform(iterations: numberOfConcurrentCalls) { _ in
            barrier.retry(dueTo: TestError.sample) { plan in
                resultsLock.lock()
                results.append(plan)
                resultsLock.unlock()
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 5)

        // Then
        XCTAssertEqual(mockRetrier.callCount, 1, "Underlying retrier should only be called once")
        XCTAssertEqual(results.count, numberOfConcurrentCalls, "All completions must be called")
        XCTAssertTrue(results.allSatisfy { $0 == .retryNow }, "All completions should receive the same retry plan")
    }

    func test_RetryBarrier_ThreadSafety() {
        let expectation = XCTestExpectation(description: "All completions called")
        expectation.expectedFulfillmentCount = 100

        let retrier = SimpleRetrier(plan: .retryNow)
        let barrier = RetryBarrier(retrier: retrier)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            barrier.retry(dueTo: TestError.sample) { _ in
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }
}

// MARK: - Mock & Helper

final class SimpleRetrier: NetworkRequestRetrier {
    private let plan: RetryPlan

    init(plan: RetryPlan) {
        self.plan = plan
    }

    func retry(dueTo error: Error, completion: @escaping (RetryPlan) -> Void) {
        completion(plan)
    }
}

final class MockRetrier: NetworkRequestRetrier {
    private(set) var callCount = 0
    private let lock = NSLock()

    func retry(dueTo error: Error, completion: @escaping (RetryPlan) -> Void) {
        lock.lock()
        callCount += 1
        lock.unlock()

        // Simulate async behavior
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) {
            completion(.retryNow)
        }
    }
}

enum TestError: Error {
    case sample
}
