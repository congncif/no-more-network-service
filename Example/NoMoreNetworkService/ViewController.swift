//
//  ViewController.swift
//  NoMoreNetworkService
//
//  Created by congncif on 02/27/2023.
//  Copyright (c) 2023 congncif. All rights reserved.
//

import NoMoreNetworkService
import UIKit

final class TestRetrier: NetworkRequestRetrier {
    func retry(dueTo error: any Error, completion: @escaping (RetryPlan) -> Void) {
        completion(.retryNow)
    }
}

class ViewController: UIViewController {
    lazy var service: NetworkService = NetworkServiceBuilder.default
        .appending(retrier: TestRetrier())
        .build()
        .withDefaultCacheStorage()

    override func viewDidLoad() {
        super.viewDidLoad()

//        task.cancel()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction private func requestButtonTapped() {
        let request = EmployeeRequest()
        let task = service.sendDataRequest(requestModel: request, responseModel: Response<[Employee]>.self) { result in
            print(result)
        }
    }

    @IBAction private func renewServiceButtonTapped() {
//        service = NetworkServiceBuilder.default
//            .build()
//            .withDefaultCacheStorage()
    }
}

struct EmployeeRequest: NetworkRequestModel {
    var host: String = "dummy.restapiexample.com"

    var path: String = "/api/v1/employees-x"

    var method: String = "GET"

    var additionalHeaders: [String: String] {
        ["XXX": "YYY"]
    }
}

struct Response<Model: Decodable>: DecodableNetworkResponseModel {
    let status: String
    let data: Model?
}

struct Employee: Decodable {
    let id: Int
    let employeeName: String
    let employeeSalary: Int
    let employeeAge: Int
}
