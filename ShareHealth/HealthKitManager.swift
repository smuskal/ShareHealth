import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    @Published var isAuthorized = false
    private let healthStore = HKHealthStore()

    private init() {
        // Check if user has gone through the authorization flow
        // We need to balance two cases:
        // 1. Fresh install: Show WelcomeView (status = .notDetermined)
        // 2. Reinstall after deletion: Show WelcomeView (status = .notDetermined, but UserDefaults may be true)
        // 3. Already authorized: Skip WelcomeView (status = .sharingAuthorized or .sharingDenied)

        if HKHealthStore.isHealthDataAvailable() {
            let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
            let status = healthStore.authorizationStatus(for: stepType)

            if status == .notDetermined {
                // Never asked for permission - need to show WelcomeView
                // Reset UserDefaults in case it persisted from a previous install
                isAuthorized = false
                UserDefaults.standard.set(false, forKey: "healthKitAuthorized")
            } else {
                // Permission was already requested (granted or denied)
                // User went through the flow, so skip WelcomeView
                // If they denied write, they'll get prompted when they try to import
                isAuthorized = true
            }
        } else {
            isAuthorized = false
        }
    }

    func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
        UserDefaults.standard.set(authorized, forKey: "healthKitAuthorized")
    }
}
