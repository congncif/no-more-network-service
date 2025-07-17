import XCTest
@testable import NoMoreNetworkService

final class RequestAdapterBarrierTests: XCTestCase {

    final class MockAdapter: NetworkRequestAdapter {
        var callCount = 0
        var onAdapt: ((URLRequest, @escaping (Result<URLRequest, Error>) -> Void) -> Void)?

        func adapt(_ urlRequest: URLRequest, completion: @escaping (Result<URLRequest, Error>) -> Void) {
            callCount += 1
            onAdapt?(urlRequest, completion)
        }
    }

    func testMultipleAdaptCalls_ShouldOnlyCallUnderlyingAdapterOnce() {
        let mockAdapter = MockAdapter()
        let barrier = RequestAdapterBarrier(adapter: mockAdapter)

        let expectation1 = expectation(description: "Completion 1")
        let expectation2 = expectation(description: "Completion 2")
        let expectation3 = expectation(description: "Completion 3")

        var completionsCalled = 0

        let request = URLRequest(url: URL(string: "https://example.com")!)

        mockAdapter.onAdapt = { req, completion in
            // Simulate async delay
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                completion(.success(req))
            }
        }

        // Simulate 3 requests calling adapt almost at the same time
        DispatchQueue.global().async {
            barrier.adapt(request) { _ in
                completionsCalled += 1
                expectation1.fulfill()
            }
        }

        DispatchQueue.global().async {
            barrier.adapt(request) { _ in
                completionsCalled += 1
                expectation2.fulfill()
            }
        }

        DispatchQueue.global().async {
            barrier.adapt(request) { _ in
                completionsCalled += 1
                expectation3.fulfill()
            }
        }

        wait(for: [expectation1, expectation2, expectation3], timeout: 2.0)

        XCTAssertEqual(mockAdapter.callCount, 1, "Underlying adapter.adapt should only be called once")
        XCTAssertEqual(completionsCalled, 3, "All completions should be called")
    }
}
