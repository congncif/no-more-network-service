//
//  AppDelegate.swift
//  NoMoreNetworkService
//
//  Created by congncif on 02/27/2023.
//  Copyright (c) 2023 congncif. All rights reserved.
//

import NoMoreNetworkService
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    let networkMonitor = NetworkConnectionMonitor()

    // Stop monitoring when appropriate, such as when the app goes into the background
    // networkMonitor.stopMonitoring()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        // Example usage: Start monitoring with an optional ping test server URL and configurable response time threshold
//        let serverURL = URL(string: "https://apple.com")!
//
//        networkMonitor.startMonitoring(detectionType: .pingServerBased(serverURL: serverURL)) { result in
//            switch result {
//            case .good:
//                print("Connection is good")
//            case let .poor(pingResult):
//                print("Connection is poor: \(pingResult.description)")
//            case .noConnection:
//                print("No network connection")
//            case .moderate:
//                print("Connection is moderate")
//            case let .unpredictable(reason):
//                print("Connection is unpredictable: \(reason)")
//            }
//        }
        
        networkMonitor.startMonitoring(detectionType: .networkTypeBased) { result in
            switch result {
            case .good:
                print("Connection is good")
            case let .poor(pingResult):
                print("Connection is poor: \(pingResult.description)")
            case .noConnection:
                print("No network connection")
            case .moderate:
                print("Connection is moderate")
            case let .unpredictable(reason):
                print("Connection is unpredictable: \(reason)")
            }
        }
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
}
