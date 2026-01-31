import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    @Published var isAuthorized = false
    
    private init() {
        // Check saved authorization state
        // Note: We rely on UserDefaults because HKHealthStore.authorizationStatus()
        // only checks write permission, not read permission. For read-only access
        // (like health export), we can't query the actual status, so we trust the
        // flag that was set after the user completed the authorization flow.
        isAuthorized = UserDefaults.standard.bool(forKey: "healthKitAuthorized")
    }
    
    func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
        UserDefaults.standard.set(authorized, forKey: "healthKitAuthorized")
    }
}
