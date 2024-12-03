import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    @Published var isAuthorized = false
    
    private init() {
        // Check saved authorization state
        isAuthorized = UserDefaults.standard.bool(forKey: "healthKitAuthorized")
        
        // Verify actual HealthKit status
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            isAuthorized = HKHealthStore().authorizationStatus(for: stepType) == .sharingAuthorized
        }
    }
    
    func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
        UserDefaults.standard.set(authorized, forKey: "healthKitAuthorized")
    }
}
