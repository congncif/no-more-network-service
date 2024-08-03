# NoMoreNetworkService

[![Version](https://img.shields.io/cocoapods/v/NoMoreNetworkService.svg?style=flat)](https://cocoapods.org/pods/NoMoreNetworkService)
[![License](https://img.shields.io/cocoapods/l/NoMoreNetworkService.svg?style=flat)](https://cocoapods.org/pods/NoMoreNetworkService)
[![Platform](https://img.shields.io/cocoapods/p/NoMoreNetworkService.svg?style=flat)](https://cocoapods.org/pods/NoMoreNetworkService)

**NoMoreNetworkService** is designed to replace complex Network libraries with a philosophy of developing a simple and cohesive library that meets the data request, upload, and download needs of iOS applications.

Based entirely on **URLSession** and without defining new concepts, **NoMoreNetworkService** solely focuses on standardizing interface methods for consistent usage across data request, upload, and download tasks.

Furthermore, **NoMoreNetworkServic**e allows you to send data requests using a declarative syntax, enhancing the clarity and readability of your code.

## Key points

* **Simple and cohesive library**: Emphasizes the library's straightforward design and consistency.
* **Standardizing interface methods**: Highlights the focus on creating a unified way to perform network operations.
* **Declarative syntax**: Explains that data requests can be expressed in a concise and readable manner.
* **Clarity and transparency**: Points out the improved readability and maintainability of the code.

## Requirements

* **Xcode** 15 +
* **iOS** 12 +
* **Swift** 5.9 +

## Installation

NoMoreNetworkService is available through [CocoaPods](https://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'NoMoreNetworkService'
```

## Usage

### Create a NetworkSerivce

* Using `NetworkServiceBuilder` with custom configurations

```swift
NetworkServiceBuilder.default
    .with(configuration: URLSessionConfiguration.ephemeral)
    .with(options: NetworkServiceOptions(maxRetries: 3))
    .build()
```

* Enable caching for the first load before fetching data from remote

```swift
NetworkServiceBuilder.default
    .build()
    .withDefaultCacheStorage()
```

* More advanced settings

```swift
NetworkServiceBuilder.default
    .with(serverTrustConfiguration: ServerTrustConfiguration.default)  // Enable SSL cert pinning
    .appending(requestAdapter: AuthorizationRequestAdapter())          // Add request adapter interceptor
    .appending(retrier: TokenRefreshRetrier())                         // Add retrier interceptor
    .build()
```

### Request data

* Retrieves the contents of the specified URL

```swift
func fetchListOfEmployees() {
    let url = URL(string: "https://your-domain.com/api/v1/employees")!
    let urlRequest = URLRequest(url: url)

    networkService.prepare(urlRequest: urlRequest)
        .onProgress { percentage in
            if percentage < 1 {
                // Show loading view
            } else {
                // Hide loading view
            }
        }
        .decodeResponse(to: Response<[Employee]>.self)
        .onCompleted { result in
            switch result.map({ $0.data }) {
            case let .success(employees):
                // Show list employees
                print(">> Success: \(String(describing: employees))")
            case let .failure(error):
                // Show error
                print(">> Failure: \(error)")
            }
        }
        .send()
}
```

* Send request using **NetworkRequestModel** with **JSON Encoding**

*The following is payload of body request to update employee information*

```json
{
  "name": "Điện Biên Phủ",
  "year_of_birth": 1954
}
```

*Define request model with the properties corresponding to the fields in the payload*

```swift
struct EmployeeUpdateRequest: EncodableNetworkRequestModel {
    let name: String
    let yearOfBirth: Int

    /// These following conformation methods could be done by POP via protocol extensions

    var host: String { "your-domain.com" }

    var path: String { "/api/v1/employees" }

    var method: String { "POST" }
}

```

*Send request in **global** queue*

```swift
let requestModel = EmployeeUpdateRequest(name: "Điện Biên Phủ", yearOfBirth: 1954)

service.prepare(requestWith: requestModel)
    .weakTarget(self)
    .onProgress { viewController, percent in
        DispatchQueue.main.async { [weak viewController] in
            if percent < 1 {
                viewController?.activityIndicatorView.startAnimating()
                viewController?.activityIndicatorView.isHidden = false
            } else {
                viewController?.activityIndicatorView.stopAnimating()
                viewController?.activityIndicatorView.isHidden = true
            }
        }
    }
    .onCompleted { viewController, result in
        DispatchQueue.main.async { [weak viewController] in
            switch result {
            case let .success:
                viewController?.showSuccessMessage()
            case let .failure(error):
                viewController?.showError(message: error.localizedDescription)
            }
        }
    }
    .send(queue: .global())
```

### Download file

```swift
func downloadFile() {
    let url = URL(string: "https://file-examples.com/storage/file_example_PNG_3MB.png")!
    let request = URLRequest(url: url)

    networkService.prepare(urlRequest: request)
        .forTask(.download(destinationURL: { suggestedFilename in
            let fileManager = FileManager.default
            let documentsDirectory = try! fileManager.url(for: .documentDirectory, 
                                                          in: .userDomainMask,
                                                          appropriateFor: nil,
                                                          create: true)
            let url = documentsDirectory.appendingPathComponent(suggestedFilename ?? UUID().uuidString)
            return url
        }))
        .weakTarget(self)
        .onProgress(handler: { viewController, percent in
            DispatchQueue.main.async { [weak viewController] in
                if percent < 1 {
                    viewController?.progressView.isHidden = false
                } else {
                    viewController?.progressView.isHidden = true
                }
                viewController?.progressView.progress = Float(percent)
            }
        })
        .onCompleted(handler: { viewController, result in
            DispatchQueue.main.async { [weak viewController] in
                switch result {
                case let .success(data):
                    viewController?.imageView.image = UIImage(data: data)
                case let .failure(error):
                    let alert = UIAlertController(title: "Download failed", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .cancel))
                    viewController?.present(alert, animated: true)
                }
            }
        })
        .send(queue: .global())
}
```

## See more in Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Author

congncif, congnc.if@gmail.com

## License

NoMoreNetworkService is available under the MIT license. See the LICENSE file for more info.
