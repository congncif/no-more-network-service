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
    @IBOutlet private var imageView: UIImageView!
    @IBOutlet private var progressView: UIProgressView!
    @IBOutlet private var activityIndicatorView: UIActivityIndicatorView!

    lazy var service: NetworkService = NetworkServiceBuilder.default
        .appending(retrier: TestRetrier())
        .build()
        .withDefaultCacheStorage()

    override func viewDidLoad() {
        super.viewDidLoad()
        activityIndicatorView.isHidden = true
        progressView.isHidden = true
//        task.cancel()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction private func requestButtonTapped() {
        let request = EmployeeRequest()

        service.sendDataRequest(requestModel: request, responseModel: Response<[Employee]>.self, progressHandler: { [weak self] percent in
            DispatchQueue.main.async { [weak self] in
                if percent < 1 {
                    self?.activityIndicatorView.startAnimating()
                    self?.activityIndicatorView.isHidden = false
                } else {
                    self?.activityIndicatorView.stopAnimating()
                }
            }
        }) { [weak self] result in
            let msg: String?
            switch result {
            case let .success(response):
                msg = response.data?.debugDescription
            case let .failure(error):
                msg = error.localizedDescription
            }
            DispatchQueue.main.async { [weak self] in

                let alert = UIAlertController(title: "Result", message: msg, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                self?.present(alert, animated: true)
            }
            print(result)
        }
    }

    @IBAction private func downloadButtonTapped() {
        let request = URLRequest(url: URL(string: "https://file-examples.com/storage/fe0b24701b66ab62b997fbc/2017/10/file_example_PNG_3MB.png")!)

        service.sendDataRequest(request, task: .download(destinationURL: { suggestedFilename in
            let fileManager = FileManager.default
            let documentsDirectory = try! fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = documentsDirectory.appendingPathComponent(suggestedFilename ?? "downloadedFile")
            print(">>> DestinationURL: \(url)")
            return url
        }), progressHandler: { [weak self] percent in
            print(">>> Percent: \(percent)")
            DispatchQueue.main.async { [weak self] in
                if percent < 1 {
                    self?.progressView.isHidden = false
                } else {
                    self?.progressView.isHidden = true
                }
                self?.progressView.progress = Float(percent)
            }
        }, completion: { [weak self] result in
            print("[THREAD] \(Thread.current)")
            print("[THREAD] isMainThread: \(Thread.current.isMainThread)")

            switch result {
            case let .success(data):
                DispatchQueue.main.async { [weak self] in
                    self?.imageView.image = UIImage(data: data)
                }
                print(">>> Download completed")
            case let .failure(error):
                DispatchQueue.main.async { [weak self] in
                    let alert = UIAlertController(title: "Result", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                    self?.present(alert, animated: true)
                }
                print(">>> Download failed: \(error)")
            }
        })
    }
}

struct EmployeeRequest: NetworkRequestModel {
    var host: String { "dummy.restapiexample.com" }

    var path: String { "/api/v1/employees" }

    var method: String { "GET" }
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
