import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        print("\n🎬 [SCENEDELEGATE] Scene will connect")
        if let urlContext = connectionOptions.urlContexts.first {
            print("🔗 [SCENEDELEGATE] URL in connection: \(urlContext.url.absoluteString)")
            
            // Store URL but don't post notification yet - let app check HealthKit first
            (UIApplication.shared.delegate as? AppDelegate)?.receivedURL = urlContext.url
            
            // Only post notification if HealthKit is already authorized
            if HealthKitManager.shared.isAuthorized {
                print("✅ [SCENEDELEGATE] HealthKit already authorized, processing URL")
                NotificationCenter.default.post(
                    name: .handleIncomingURL,
                    object: nil,
                    userInfo: ["url": urlContext.url]
                )
            } else {
                print("⏳ [SCENEDELEGATE] Waiting for HealthKit authorization before processing URL")
            }
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        print("\n🎯 [SCENEDELEGATE] Open URL contexts called")
        for urlContext in URLContexts {
            print("🔗 [SCENEDELEGATE] Processing URL: \(urlContext.url.absoluteString)")
            
            // Store URL but don't post notification yet if HealthKit isn't ready
            (UIApplication.shared.delegate as? AppDelegate)?.receivedURL = urlContext.url
            
            // Only post notification if HealthKit is already authorized
            if HealthKitManager.shared.isAuthorized {
                print("✅ [SCENEDELEGATE] HealthKit authorized, processing URL")
                NotificationCenter.default.post(
                    name: .handleIncomingURL,
                    object: nil,
                    userInfo: ["url": urlContext.url]
                )
            } else {
                print("⏳ [SCENEDELEGATE] Waiting for HealthKit authorization before processing URL")
            }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        print("\n🔄 [SCENEDELEGATE] Shortcut action performed: \(shortcutItem.type)")
        completionHandler(true)
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        print("\n▶️ [SCENEDELEGATE] Scene did become active")
        
        // Check if we have a pending URL and HealthKit is now authorized
        if HealthKitManager.shared.isAuthorized,
           let appDelegate = UIApplication.shared.delegate as? AppDelegate,
           let url = appDelegate.receivedURL {
            print("🔄 [SCENEDELEGATE] Processing pending URL after becoming active")
            NotificationCenter.default.post(
                name: .handleIncomingURL,
                object: nil,
                userInfo: ["url": url]
            )
            appDelegate.receivedURL = nil
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        print("\n⏸️ [SCENEDELEGATE] Scene will resign active")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        print("\n⚫️ [SCENEDELEGATE] Scene did enter background")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        print("\n⚪️ [SCENEDELEGATE] Scene will enter foreground")
    }
}
