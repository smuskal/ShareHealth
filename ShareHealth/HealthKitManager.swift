import Foundation
import HealthKit

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()
    @Published var isAuthorized = UserDefaults.standard.bool(forKey: "healthKitAuthorized")
    private let healthStore = HKHealthStore()

    private init() {
        refreshAuthorizationState()
    }

    func setAuthorized(_ authorized: Bool) {
        if Thread.isMainThread {
            isAuthorized = authorized
            UserDefaults.standard.set(authorized, forKey: "healthKitAuthorized")
            UserDefaults.standard.set(authorized, forKey: "healthExportAuthorized")
        } else {
            DispatchQueue.main.async {
                self.isAuthorized = authorized
                UserDefaults.standard.set(authorized, forKey: "healthKitAuthorized")
                UserDefaults.standard.set(authorized, forKey: "healthExportAuthorized")
            }
        }
    }

    func refreshAuthorizationState(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            setAuthorized(false)
            completion?(false)
            return
        }

        let typesToRead = HealthDataExporter.requiredReadTypes()
        let typesToWrite = HealthDataExporter.requiredWriteTypes()

        healthStore.getRequestStatusForAuthorization(toShare: typesToWrite, read: typesToRead) { status, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("HealthKit authorization status error: \(error.localizedDescription)")
                }

                let authorized: Bool
                switch status {
                case .unnecessary:
                    authorized = true
                case .shouldRequest, .unknown:
                    authorized = false
                @unknown default:
                    authorized = false
                }

                self.setAuthorized(authorized)
                completion?(authorized)
            }
        }
    }
}
