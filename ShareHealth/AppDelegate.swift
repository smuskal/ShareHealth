import UIKit
import Foundation

class AppDelegate: UIResponder, UIApplicationDelegate {
    var receivedURL: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("\n🚀 [APPDELEGATE] Application launched")
        if let url = launchOptions?[.url] as? URL {
            print("🔗 [APPDELEGATE] Launch URL detected: \(url.absoluteString)")
            self.receivedURL = url
        }
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        print("\n🔗 [APPDELEGATE] Received URL: \(url.absoluteString)")
        self.receivedURL = url
        NotificationCenter.default.post(
            name: .handleIncomingURL,
            object: nil,
            userInfo: ["url": url]
        )
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        print("\n▶️ [APPDELEGATE] Application did become active")
        if let url = receivedURL {
            print("🔗 [APPDELEGATE] Processing pending URL: \(url.absoluteString)")
            NotificationCenter.default.post(
                name: .handleIncomingURL,
                object: nil,
                userInfo: ["url": url]
            )
            receivedURL = nil
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
        print("\n⏸️ [APPDELEGATE] Application will resign active")
    }
}
