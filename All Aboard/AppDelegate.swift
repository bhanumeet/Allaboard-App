//
//  AppDelegate.swift
//  All Aboard
//
//  Created by Wiper on 21/07/21.
//

import UIKit
import Firebase
@main
class AppDelegate: UIResponder, UIApplicationDelegate {


    /// set orientations you want to be allowed in this property by default
    var orientationLock = UIInterfaceOrientationMask.all
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        FirebaseApp.configure()
        UMConfigure.setLogEnabled(true)
        UMConfigure.initWithAppkey("6127fb9a4bede245d9eb88ff", channel: "App Store")
        
        let defaults = UserDefaults.standard
        // Check if the default setting has not been set yet
        if defaults.object(forKey: "Upright") == nil {
            defaults.set(true, forKey: "Upright") // Set the Upright Activation to ON by default
        }
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    @available(iOS 13.0, *)
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }


}

